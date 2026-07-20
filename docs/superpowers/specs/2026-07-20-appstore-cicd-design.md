---
title: App Store Connect CI/CD design
---

# App Store Connect CI/CD design

Automates building, signing, and uploading Marklens to App Store Connect for
both macOS and iOS, triggered the same way the existing GitHub-release
snapshot is: publishing a GitHub Release.

## Background

This repo already has:

- `.github/workflows/ci.yml` — `unit-tests` / `build-macos` / `build-ios` run
  independently on every push/PR. Debug builds, ad-hoc signed (macOS) or
  unsigned (iOS simulator). Not store-distributable.
- `.github/workflows/release.yml` — on `release: published`, attaches an
  ad-hoc-signed Release-config macOS `.zip` (built by `ci.yml`'s
  `build-macos` job) to the GitHub Release. No App Store involvement, no
  rebuild at release time.

Neither platform currently has any App Store Connect automation — both are
submitted manually via Xcode Organizer today.

Marklens is a single multiplatform Xcode target (`supportedDestinations:
[macOS, iOS]`, one scheme, one shared `Info.plist`/`CURRENT_PROJECT_VERSION`)
plus a macOS-only QuickLook app extension (`platformFilter: macOS`) embedded
in the main app.

## Goal

Publishing a GitHub Release should, in addition to what `release.yml`
already does, build fresh Release archives for macOS and iOS, sign them with
the real Apple Distribution certificate, and upload them to App Store
Connect (TestFlight processing) — without requiring the developer to run
Xcode Organizer for the upload step. Submitting for review stays manual.

## Decisions

These were settled through user Q&A before this design was written; each
came with a rejected alternative that's worth recording so a future reader
doesn't wonder why it isn't done that way.

| Decision | Chosen | Rejected alternative and why |
|---|---|---|
| Trigger | `release: published` (same event as `release.yml`), plus `workflow_dispatch` for manual re-runs/testing | A separate `v*` git tag push, or workflow_dispatch-only. Rejected: a second ritual alongside "publish a GitHub Release" would fragment the release process the developer already uses; workflow_dispatch-only isn't really "automated." |
| Submission scope | Upload only — binary reaches App Store Connect/TestFlight processing, developer submits for review by hand | Auto-submit for review via `deliver`. Rejected: a bad automated run could submit something unintended to review, and it would require maintaining release notes/metadata as repo files. |
| Cert/profile management | Manually export cert + profiles, store as base64 GitHub secrets | `fastlane match`. Rejected: match needs a second private git repo plus a passphrase secret — meaningful extra infrastructure for a solo-maintainer app where certs/profiles change rarely. |
| Build number | CI auto-increments `CURRENT_PROJECT_VERSION` by querying App Store Connect | Manual bump in `project.yml` (today's practice, e.g. "Bump build to N" commits). Rejected: the developer chose to remove this manual step now that two platforms need coordinated numbers. |
| Existing GitHub zip asset | Keep it — publishing a release still attaches the ad-hoc macOS `.zip` *and* uploads to App Store Connect | Drop it now that real signed builds exist. Rejected: the zip is useful for anyone who wants to run the build before it clears App Review. |
| Workflow structure | New standalone `appstore.yml`, mirroring the `ci.yml` job-separation pattern | Fold App Store jobs into `release.yml`. Rejected: mixes "attach a GitHub asset" concerns with "submit real credentials to Apple" concerns in one file; keeping them separate keeps the higher-stakes path easy to reason about in isolation. |

## Architecture

### New files

- **`.github/workflows/appstore.yml`** — two independent jobs,
  `appstore-macos` and `appstore-ios`, both `runs-on: macos-15`. Each does
  its own fresh checkout → XcodeGen generate → `bundle exec fastlane
  <platform> release`. Neither reuses `ci.yml`'s or `release.yml`'s build
  steps — those produce Debug/ad-hoc-unsigned artifacts, which are a
  different thing from a manually-signed Release archive for App Store
  submission. The ~4 lines of setup boilerplate (checkout, xcodegen,
  fetch-assets, generate-project) are duplicated rather than extracted into
  a composite action — three workflow files each with a handful of setup
  steps isn't enough duplication to justify the abstraction yet.
- **`fastlane/Fastfile`** — `platform :mac do lane :release ... end` and
  `platform :ios do lane :release ... end`. Each lane:
  1. `setup_ci` — creates a temporary CI keychain (auto-cleaned up at the
     end of the runner's life anyway, but this is fastlane's standard
     practice).
  2. `import_certificate` — decodes and imports the Distribution `.p12`
     from secrets into that keychain.
  3. `install_provisioning_profile` — once for the main app's profile, once
     more for the QuickLook profile on the macOS lane only.
  4. Compute next build number (see below) and set
     `CURRENT_PROJECT_VERSION` for the build.
  5. `build_app` (gym) — Release config, manual signing, inline
     `export_options` hash (method `app-store`, explicit
     provisioning-profile-per-bundle-ID mapping). No checked-in
     `.plist` export-options files.
  6. `upload_to_testflight` — `skip_submission: true`. Uploads and lets
     Apple process the build; does not submit for review.
- **`fastlane/Appfile`** — app identifier `solutions.ddj.marklens`, team ID
  `997P2237XV` (not secret, already in `project.yml`).
- **`Gemfile` / `Gemfile.lock`** — pins the fastlane gem version so CI
  doesn't silently pick up a new fastlane release mid-flight.
- **`docs/appstore-connect-secrets.md`** — already written (see that file)
  — step-by-step instructions for generating and populating all 9 secrets.

### Secrets (see `docs/appstore-connect-secrets.md` for full detail)

`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY_CONTENT`, `DISTRIBUTION_CERTIFICATE_P12`,
`DISTRIBUTION_CERTIFICATE_PASSWORD`, `CI_KEYCHAIN_PASSWORD`,
`PROVISIONING_PROFILE_MACOS`, `PROVISIONING_PROFILE_IOS`,
`PROVISIONING_PROFILE_QUICKLOOK`.

The App Store Connect API key (rather than an Apple ID + app-specific
password) is what lets `upload_to_testflight` and the build-number lookup
authenticate without an interactive 2FA prompt.

### Build numbering

macOS and iOS share one `CURRENT_PROJECT_VERSION` (one target, one
`Info.plist`). Each lane independently calls fastlane's
`latest_testflight_build_number` scoped across both platforms' existing App
Store Connect history, and uploads `max(macOS, iOS) + 1`. Because both
lanes read the same shared history independently, they converge on the same
number without the two parallel jobs needing to coordinate — no "compute
once in a setup job, pass to both" indirection required.

This increment happens only in the generated Xcode project inside that CI
run — it is never committed back to `project.yml` or the repo, consistent
with "nothing in this workflow writes back to the repository" below. The
value in `project.yml` (`CURRENT_PROJECT_VERSION: "3"`) is a floor, not a
tracked history; App Store Connect is the source of truth for what's
actually been uploaded.

`MARKETING_VERSION` (e.g. `1.0.1` → `1.0.2`) stays a manual edit in
`project.yml`, same as today — that's an intentional version bump, not
something to automate.

### Signing

`project.yml` is untouched — `CODE_SIGN_STYLE: Automatic` remains the
default for local Xcode development. `appstore.yml`'s fastlane lanes
override signing at build time only (`CODE_SIGN_STYLE=Manual`, explicit
`CODE_SIGN_IDENTITY="Apple Distribution"`, explicit provisioning profile per
bundle ID), the same pattern `ci.yml` already uses for its ad-hoc
`CODE_SIGN_IDENTITY="-"` override. Local `xcodebuild`/Xcode behavior for the
developer doesn't change.

### Error handling

Each lane fails at the first problem (expired cert, missing secret, signing
mismatch, upload rejection) with fastlane's standard error output in the
job log. `appstore-macos` and `appstore-ios` are independent — one
platform's failure never blocks or masks the other's. Nothing in this
workflow writes back to the repository or touches `main`; a failed run is
simply re-run via `workflow_dispatch` once the underlying problem (usually
an expired secret — see the "when this needs to be redone" section of
`docs/appstore-connect-secrets.md`) is fixed.

### Testing plan

Unlike `release.yml`, there's no safe throwaway-and-delete test path here —
even a successful "upload only" run creates a real TestFlight build in App
Store Connect. Plan:

1. Lint `appstore.yml` (actionlint) and the `Fastfile` (Ruby syntax check)
   before any secrets exist.
2. User populates the 9 secrets per `docs/appstore-connect-secrets.md`.
3. First real run via manual `workflow_dispatch`, watched live — this is
   the actual end-to-end test, and needs the user's live credentials, so it
   can't be self-verified the way the GitHub-release zip attachment was
   earlier in this project.
4. Once clean, `release: published` becomes the standing trigger.

## Out of scope (for this design)

- Auto-submitting builds for App Review (explicitly rejected above).
- `fastlane match` / automated cert-renewal (explicitly rejected above).
- Release notes / "What's New" metadata automation — still written by hand
  in App Store Connect, same as today.
- Cert/profile expiry monitoring or alerting — CI failing with a clear
  error when a cert expires is considered sufficient signal for a
  solo-maintainer project; a proactive expiry check could be added later if
  it becomes annoying in practice.
