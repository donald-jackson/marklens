# App Store Connect CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate building, signing, and uploading Marklens to App Store Connect (TestFlight processing) for both macOS and iOS when a GitHub Release is published, without touching how the app is submitted for review or how it's built locally in Xcode.

**Architecture:** A new `.github/workflows/appstore.yml` with two independent jobs (`appstore-macos`, `appstore-ios`), each decoding signing secrets, running `bundle exec fastlane <platform> release`, and cleaning up. `fastlane/Fastfile` holds the actual build/sign/upload logic, shared between both platforms via one Ruby helper method. Full rationale and rejected alternatives: `docs/superpowers/specs/2026-07-20-appstore-cicd-design.md`.

**Tech Stack:** GitHub Actions (`macos-15` runners), fastlane (`build_app`/gym, `upload_to_testflight`/pilot, `app_store_connect_api_key`), Ruby via `ruby/setup-ruby@v1`, XcodeGen (already in use by `ci.yml`/`release.yml`).

## Global Constraints

- Trigger: `release: published` **and** `workflow_dispatch` — nothing else.
- Upload only. Nothing in this plan calls an action that submits for App Review (`skip_submission: true` on every `upload_to_testflight` call, always).
- No `fastlane match`. Certs/profiles come from GitHub secrets, decoded to files in CI.
- CI computes and sets the build number for that run only — never edit or commit `CURRENT_PROJECT_VERSION` back into `project.yml`.
- `project.yml`'s `CODE_SIGN_STYLE: Automatic` stays as the default for local Xcode development — signing overrides happen only inside the fastlane lanes, never in `project.yml`.
- `.github/workflows/release.yml` (the ad-hoc macOS zip attached to GitHub Releases) is untouched — this plan adds a second, independent workflow alongside it, not a replacement.
- Secret names and provisioning-profile names must exactly match `docs/appstore-connect-secrets.md` (already written, do not change it): secrets `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT`, `DISTRIBUTION_CERTIFICATE_P12`, `DISTRIBUTION_CERTIFICATE_PASSWORD`, `CI_KEYCHAIN_PASSWORD`, `PROVISIONING_PROFILE_MACOS`, `PROVISIONING_PROFILE_IOS`, `PROVISIONING_PROFILE_QUICKLOOK`; profile names `Marklens macOS App Store`, `Marklens iOS App Store`, `MarklensQuickLook macOS App Store`.
- App identifier `solutions.ddj.marklens`, QuickLook extension identifier `solutions.ddj.marklens.QuickLook`, team ID `997P2237XV` (all already public in `project.yml`, not secret).

---

## Task 1: Fastlane configuration (Gemfile, Appfile, Fastfile)

**Files:**
- Create: `Gemfile`
- Create: `Gemfile.lock` (generated, not hand-written)
- Create: `fastlane/Appfile`
- Create: `fastlane/Fastfile`

**Interfaces:**
- Produces: `bundle exec fastlane mac release` and `bundle exec fastlane ios release` — the two lane invocations Task 2's workflow will call. Both read the same 9 secret env vars (listed in Global Constraints) plus `PROVISIONING_PROFILE_MACOS_PATH`, `PROVISIONING_PROFILE_IOS_PATH`, `PROVISIONING_PROFILE_QUICKLOOK_PATH`, `DISTRIBUTION_CERTIFICATE_PATH` (file paths, set by Task 2's workflow after decoding the base64 secrets — these three `_PATH` vars are NOT secrets themselves, just where Task 2 writes the decoded files).

- [ ] **Step 1: Write the Gemfile**

```ruby
source "https://rubygems.org"

gem "fastlane"
```

- [ ] **Step 2: Generate Gemfile.lock**

Run: `bundle lock`

Expected: creates `Gemfile.lock` in the repo root, resolving `fastlane` and its transitive dependencies. The system Ruby here is 2.6.10 (old, but fastlane deliberately supports it) — if `bundle lock` fails to resolve because of a Ruby-version constraint from a dependency, fall back to a newer local Ruby:

```bash
brew install ruby
$(brew --prefix ruby)/bin/gem install bundler
$(brew --prefix ruby)/bin/bundle lock
```

Either way, end state is a committed `Gemfile.lock` that resolves cleanly.

- [ ] **Step 3: Write fastlane/Appfile**

```ruby
app_identifier("solutions.ddj.marklens")
team_id("997P2237XV")
```

No `apple_id` — every fastlane action in this project authenticates via the App Store Connect API key, not an Apple ID session.

- [ ] **Step 4: Write fastlane/Fastfile**

```ruby
default_platform(:ios)

APP_IDENTIFIER = "solutions.ddj.marklens"
QUICKLOOK_IDENTIFIER = "solutions.ddj.marklens.QuickLook"
TEAM_ID = "997P2237XV"
KEYCHAIN_NAME = "appstore-ci.keychain-db"

# One build higher than the highest existing build across *both* platforms'
# App Store Connect history. macOS and iOS share one CURRENT_PROJECT_VERSION
# (one target, one Info.plist) — both lanes call this independently and
# converge on the same number without needing to coordinate with each other,
# since they're reading the same shared history.
def next_build_number(api_key)
  ios_build = latest_testflight_build_number(
    api_key: api_key,
    app_identifier: APP_IDENTIFIER,
    platform: "ios"
  ).to_i
  mac_build = latest_testflight_build_number(
    api_key: api_key,
    app_identifier: APP_IDENTIFIER,
    platform: "osx"
  ).to_i
  [ios_build, mac_build].max + 1
end

# Shared by both platform lanes below. `profiles` is an array of
# { target:, bundle_id:, profile_name:, profile_path: } — one entry per
# Xcode target that needs signing for this platform (macOS has two: the
# main app and the QuickLook extension; iOS has just the main app).
#
# export_options[:provisioningProfiles] (used by `build_app` below) only
# controls the *export* step (archive -> .app/.pkg or .ipa). The `archive`
# step itself still builds under project.yml's CODE_SIGN_STYLE: Automatic
# unless told otherwise — since we deliberately don't touch project.yml,
# update_code_signing_settings flips each target to manual signing with its
# specific profile directly in the generated .xcodeproj before the archive.
def build_and_upload(destination:, profiles:, upload_platform:)
  api_key = app_store_connect_api_key(
    key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ID"),
    issuer_id: ENV.fetch("APP_STORE_CONNECT_API_ISSUER_ID"),
    key_content: ENV.fetch("APP_STORE_CONNECT_API_KEY_CONTENT"),
    is_key_content_base64: false
  )

  keychain_password = ENV.fetch("CI_KEYCHAIN_PASSWORD")
  create_keychain(
    name: KEYCHAIN_NAME,
    password: keychain_password,
    default_keychain: true,
    unlock: true,
    timeout: 1800,
    lock_when_sleeps: false
  )
  import_certificate(
    certificate_path: ENV.fetch("DISTRIBUTION_CERTIFICATE_PATH"),
    certificate_password: ENV.fetch("DISTRIBUTION_CERTIFICATE_PASSWORD"),
    keychain_name: KEYCHAIN_NAME,
    keychain_password: keychain_password
  )
  profiles.each { |p| install_provisioning_profile(path: p[:profile_path]) }

  build_number = next_build_number(api_key)
  increment_build_number(build_number: build_number, xcodeproj: "Marklens.xcodeproj")

  profiles.each do |p|
    update_code_signing_settings(
      path: "Marklens.xcodeproj",
      use_automatic_signing: false,
      team_id: TEAM_ID,
      code_sign_identity: "Apple Distribution",
      targets: [p[:target]],
      profile_name: p[:profile_name]
    )
  end

  build_app(
    project: "Marklens.xcodeproj",
    scheme: "Marklens",
    destination: destination,
    configuration: "Release",
    output_directory: "build/appstore",
    output_name: "Marklens",
    export_options: {
      method: "app-store",
      teamID: TEAM_ID,
      signingStyle: "manual",
      provisioningProfiles: profiles.to_h { |p| [p[:bundle_id], p[:profile_name]] }
    }
  )

  upload_to_testflight(
    api_key: api_key,
    app_identifier: APP_IDENTIFIER,
    platform: upload_platform,
    skip_submission: true,
    skip_waiting_for_build_processing: true
  )
end

platform :mac do
  desc "Build and upload the macOS app to TestFlight processing"
  lane :release do
    build_and_upload(
      destination: "generic/platform=macOS",
      profiles: [
        {
          target: "Marklens",
          bundle_id: APP_IDENTIFIER,
          profile_name: "Marklens macOS App Store",
          profile_path: ENV.fetch("PROVISIONING_PROFILE_MACOS_PATH")
        },
        {
          target: "MarklensQuickLook",
          bundle_id: QUICKLOOK_IDENTIFIER,
          profile_name: "MarklensQuickLook macOS App Store",
          profile_path: ENV.fetch("PROVISIONING_PROFILE_QUICKLOOK_PATH")
        }
      ],
      upload_platform: "osx"
    )
  end
end

platform :ios do
  desc "Build and upload the iOS app to TestFlight processing"
  lane :release do
    build_and_upload(
      destination: "generic/platform=iOS",
      profiles: [
        {
          target: "Marklens",
          bundle_id: APP_IDENTIFIER,
          profile_name: "Marklens iOS App Store",
          profile_path: ENV.fetch("PROVISIONING_PROFILE_IOS_PATH")
        }
      ],
      upload_platform: "ios"
    )
  end
end
```

- [ ] **Step 5: Verify the Fastfile loads and registers both lanes**

Run: `bundle exec fastlane lanes`

Expected: output lists `fastlane mac release` and `fastlane ios release` (with their `desc` text), and exits 0. This proves the Ruby is syntactically valid and every lane/method reference resolves — it does **not** run either lane (no secrets needed for this check).

If it fails with a `NameError`/`SyntaxError`, fix the Fastfile and re-run this step before moving on.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock fastlane/Appfile fastlane/Fastfile
git commit -m "Add fastlane configuration for App Store Connect uploads"
```

---

## Task 2: Add appstore.yml workflow

**Files:**
- Create: `.github/workflows/appstore.yml`

**Interfaces:**
- Consumes: `bundle exec fastlane mac release` / `bundle exec fastlane ios release` from Task 1, and the 9 secrets from `docs/appstore-connect-secrets.md`.
- Produces: the `appstore-macos` and `appstore-ios` jobs that Task 3 will trigger via `workflow_dispatch`.

- [ ] **Step 1: Create a branch**

```bash
git checkout -b ci/appstore-connect
```

- [ ] **Step 2: Write .github/workflows/appstore.yml**

```yaml
name: App Store Connect

# Fires when a GitHub Release is published: builds fresh Release archives
# for macOS and iOS, signs them with the real Apple Distribution
# certificate, and uploads to App Store Connect for TestFlight processing.
# Submitting for review stays manual — see
# docs/superpowers/specs/2026-07-20-appstore-cicd-design.md.
#
# workflow_dispatch exists because, unlike release.yml, there's no safe
# throwaway-release test path here: even a successful run creates a real
# TestFlight build, so verifying this needs a human watching a manual run.
on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  appstore-macos:
    name: App Store Connect (macOS)
    runs-on: macos-15
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Fetch bundled web assets
        run: ./scripts/fetch-assets.sh

      - name: Generate Xcode project
        run: ./scripts/generate-project.sh

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Decode signing credentials
        env:
          DISTRIBUTION_CERTIFICATE_P12_B64: ${{ secrets.DISTRIBUTION_CERTIFICATE_P12 }}
          PROVISIONING_PROFILE_MACOS_B64: ${{ secrets.PROVISIONING_PROFILE_MACOS }}
          PROVISIONING_PROFILE_QUICKLOOK_B64: ${{ secrets.PROVISIONING_PROFILE_QUICKLOOK }}
        run: |
          mkdir -p /tmp/appstore-secrets
          echo "$DISTRIBUTION_CERTIFICATE_P12_B64" | base64 --decode > /tmp/appstore-secrets/distribution.p12
          echo "$PROVISIONING_PROFILE_MACOS_B64" | base64 --decode > /tmp/appstore-secrets/marklens-macos.provisionprofile
          echo "$PROVISIONING_PROFILE_QUICKLOOK_B64" | base64 --decode > /tmp/appstore-secrets/marklens-quicklook.provisionprofile

      - name: Build and upload to App Store Connect
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.APP_STORE_CONNECT_API_KEY_CONTENT }}
          DISTRIBUTION_CERTIFICATE_PATH: /tmp/appstore-secrets/distribution.p12
          DISTRIBUTION_CERTIFICATE_PASSWORD: ${{ secrets.DISTRIBUTION_CERTIFICATE_PASSWORD }}
          CI_KEYCHAIN_PASSWORD: ${{ secrets.CI_KEYCHAIN_PASSWORD }}
          PROVISIONING_PROFILE_MACOS_PATH: /tmp/appstore-secrets/marklens-macos.provisionprofile
          PROVISIONING_PROFILE_QUICKLOOK_PATH: /tmp/appstore-secrets/marklens-quicklook.provisionprofile
        run: bundle exec fastlane mac release

      - name: Clean up decoded secrets
        if: always()
        run: rm -rf /tmp/appstore-secrets

  appstore-ios:
    name: App Store Connect (iOS)
    runs-on: macos-15
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # Deliberately not pinned to Xcode_16.app like the macOS job above:
      # that specific install only ships an iOS-platform *stub* on this
      # runner image (no matching Simulator/device platform support
      # materialized) — see the "Deliberately not pinned" comment in
      # ci.yml's build-ios job for the full story. Xcode.app (the runner's
      # default) is the one GitHub keeps paired with a fully-installed
      # platform.
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Fetch bundled web assets
        run: ./scripts/fetch-assets.sh

      - name: Generate Xcode project
        run: ./scripts/generate-project.sh

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Decode signing credentials
        env:
          DISTRIBUTION_CERTIFICATE_P12_B64: ${{ secrets.DISTRIBUTION_CERTIFICATE_P12 }}
          PROVISIONING_PROFILE_IOS_B64: ${{ secrets.PROVISIONING_PROFILE_IOS }}
        run: |
          mkdir -p /tmp/appstore-secrets
          echo "$DISTRIBUTION_CERTIFICATE_P12_B64" | base64 --decode > /tmp/appstore-secrets/distribution.p12
          echo "$PROVISIONING_PROFILE_IOS_B64" | base64 --decode > /tmp/appstore-secrets/marklens-ios.mobileprovision

      - name: Build and upload to App Store Connect
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.APP_STORE_CONNECT_API_KEY_CONTENT }}
          DISTRIBUTION_CERTIFICATE_PATH: /tmp/appstore-secrets/distribution.p12
          DISTRIBUTION_CERTIFICATE_PASSWORD: ${{ secrets.DISTRIBUTION_CERTIFICATE_PASSWORD }}
          CI_KEYCHAIN_PASSWORD: ${{ secrets.CI_KEYCHAIN_PASSWORD }}
          PROVISIONING_PROFILE_IOS_PATH: /tmp/appstore-secrets/marklens-ios.mobileprovision
        run: bundle exec fastlane ios release

      - name: Clean up decoded secrets
        if: always()
        run: rm -rf /tmp/appstore-secrets
```

- [ ] **Step 3: Lint the workflow**

Run: `actionlint .github/workflows/appstore.yml`
Expected: no output (clean).

Run:
```bash
python3 -c "
import yaml
with open('.github/workflows/appstore.yml') as f:
    yaml.safe_load(f)
print('OK')
"
```
Expected: `OK`.

- [ ] **Step 4: Commit and push**

```bash
git add .github/workflows/appstore.yml
git commit -m "Add appstore.yml: build, sign, and upload to App Store Connect"
git push -u origin ci/appstore-connect
```

- [ ] **Step 5: Open a PR**

```bash
gh pr create --repo donald-jackson/marklens \
  --title "Add App Store Connect upload workflow (macOS + iOS)" \
  --body "Implements docs/superpowers/specs/2026-07-20-appstore-cicd-design.md. Upload-only (no auto-submit-for-review), triggered by publishing a GitHub Release, plus workflow_dispatch for manual runs. Needs the 9 secrets in docs/appstore-connect-secrets.md before it can succeed end-to-end — see that PR's Task 3 for the pre-secrets verification and Task 5 for the live test."
```

---

## Task 3: Verify the workflow fails cleanly at the credentials boundary

No secrets exist yet at this point, so both jobs are expected to fail — the point of this task is confirming *where* and *how* they fail: cleanly, at the App Store Connect API key step, after checkout/XcodeGen/Ruby setup/`bundle install` all succeed. That proves the workflow's plumbing (env var names, working directory, fastlane wiring) is correct, independent of whether real Apple credentials exist yet.

**Files:** none (verification only).

- [ ] **Step 1: Trigger a manual run**

```bash
gh workflow run appstore.yml --repo donald-jackson/marklens --ref ci/appstore-connect
```

- [ ] **Step 2: Watch both jobs**

```bash
gh run list --repo donald-jackson/marklens --workflow appstore.yml --limit 1 --json databaseId --jq '.[0].databaseId'
# then, with that run id:
gh run watch <run-id> --repo donald-jackson/marklens
```

- [ ] **Step 3: Confirm the failure point**

Expected for both `appstore-macos` and `appstore-ios`:
- `Checkout`, `Select Xcode`, `Install XcodeGen`, `Fetch bundled web assets`, `Generate Xcode project`, `Set up Ruby`, `Decode signing credentials` all succeed (the decode step succeeds even with empty secrets — `base64 --decode` on an empty string just produces an empty file).
- `Build and upload to App Store Connect` fails inside the `app_store_connect_api_key` fastlane action, with an authentication/invalid-key error — **not** a `command not found`, `NameError`, or XcodeGen/build failure. (GitHub Actions turns a reference to a nonexistent secret into an *empty string*, not a missing env var, so this fails on invalid/empty key content rather than a Ruby `KeyError` — that's expected here.)

If it fails anywhere earlier than the `app_store_connect_api_key` step, or with a different class of error (Ruby syntax, missing gem, xcodebuild scheme/destination error), that's a real bug in Task 1 or Task 2 — fix it, push to `ci/appstore-connect`, and re-run this task.

- [ ] **Step 4: No commit** — this task only verifies what's already committed.

---

## Task 4: Merge the PR

**Files:** none.

- [ ] **Step 1: Confirm Task 3 passed** (clean failure at the credentials boundary, nothing earlier).

- [ ] **Step 2: Merge**

```bash
gh pr merge --repo donald-jackson/marklens --squash ci/appstore-connect
```

- [ ] **Step 3: Sync local main**

```bash
git checkout main
git pull --ff-only
```

---

## Task 5 (human checkpoint): Populate secrets and run a live end-to-end test

This task cannot be completed autonomously — it requires the user's actual Apple Developer account access to generate credentials, and running it produces a real TestFlight build in App Store Connect (unlike `release.yml`'s zip attachment, there's no throwaway-and-delete path here). The agent's role here is to prompt the user through it and be ready to debug a failure live, not to execute it unattended.

**Files:** none (this task is entirely operational).

- [ ] **Step 1: User populates all 9 secrets**

Following `docs/appstore-connect-secrets.md` end to end. Verify with:

```bash
gh secret list --repo donald-jackson/marklens
```

Expected: all 9 secret names present (see Global Constraints above for the exact list).

- [ ] **Step 2: Trigger a manual run on main**

```bash
gh workflow run appstore.yml --repo donald-jackson/marklens --ref main
```

- [ ] **Step 3: Watch both jobs to completion, together with the user**

```bash
gh run watch <run-id> --repo donald-jackson/marklens
```

Expected: both `appstore-macos` and `appstore-ios` succeed, ending at `upload_to_testflight` reporting the build was uploaded and is processing.

If a job fails, the most likely causes, in rough order of likelihood: a provisioning-profile name typo (must exactly match what's registered in the Apple Developer portal — see the Global Constraints list), `update_code_signing_settings` failing to find a target named `Marklens`/`MarklensQuickLook` (would mean XcodeGen's generated project uses different target names than `project.yml` currently does — check `xcodebuild -list -project Marklens.xcodeproj` for the actual target names if this happens), a profile that doesn't include the QuickLook extension's entitlements, or the Distribution certificate not matching what's referenced in a profile. Fix the specific secret/profile named in fastlane's error output and re-run Step 2.

- [ ] **Step 4: Confirm in App Store Connect**

In App Store Connect → My Apps → Marklens → TestFlight, confirm a new build appears for both macOS and iOS, with the build number that was actually used (from job logs — search for "Successfully uploaded" or check the `increment_build_number` step's output) higher than any prior build.

- [ ] **Step 5: Done**

`release: published` is now the standing trigger — no further manual runs needed unless testing again. Update `docs/superpowers/specs/2026-07-20-appstore-cicd-design.md`'s testing-plan section to note the date this was first verified live, and commit:

```bash
git add docs/superpowers/specs/2026-07-20-appstore-cicd-design.md
git commit -m "Note appstore.yml verified live end-to-end"
git push
```
