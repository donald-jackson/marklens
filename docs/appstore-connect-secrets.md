---
title: App Store Connect CI secrets
---

# App Store Connect CI secrets

Setup guide for the credentials the `appstore.yml` GitHub Actions workflow needs to build, sign, and upload Marklens to App Store Connect for both macOS and iOS. Nine secrets total — do this once (and again whenever a cert/profile expires).

Do this signed in as the account that manages App Store Connect for Marklens (`apple@ddj.solutions`), with Account Holder or Admin access on the `997P2237XV` team.

All `gh secret set` commands below assume:

```
export REPO=donald-jackson/marklens
```

---

## 1. App Store Connect API key

Used to authenticate uploads and look up existing build numbers, without putting an Apple ID/password or 2FA into CI.

1. Go to [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api).
2. Click **+** to generate a new key. Name it something like `GitHub Actions CI`. Access level: **App Manager**.
3. Download the `.p8` file **immediately** — App Store Connect only lets you download it once.
4. Note the **Key ID** (shown in the key's row) and the **Issuer ID** (shown at the top of the Integrations page, same for all keys).

```bash
gh secret set APP_STORE_CONNECT_API_KEY_ID --repo "$REPO" --body "<Key ID>"
gh secret set APP_STORE_CONNECT_API_ISSUER_ID --repo "$REPO" --body "<Issuer ID>"
gh secret set APP_STORE_CONNECT_API_KEY_CONTENT --repo "$REPO" < AuthKey_XXXXXXXXXX.p8
```

(The `.p8` is already PEM text, so it goes in as-is — unlike the `.p12`/provisioning profiles below, which are binary and need base64 first.)

---

## 2. Distribution certificate

One **Apple Distribution** certificate covers both Mac and iOS App Store signing.

**If you already have one** (the cert you use for manual App Store uploads today): open **Keychain Access**, find `Apple Distribution: ...` under *My Certificates* — it should have a disclosure triangle with a private key nested underneath. Select both the cert and the key, right-click → **Export 2 items…**, save as a `.p12`, and set an export password when prompted.

**If you don't have one yet**: Xcode → Settings → Accounts → select your Apple ID → **Manage Certificates** → **+** → **Apple Distribution**. Then export as above.

```bash
base64 -i DistributionCert.p12 | tr -d '\n' | gh secret set DISTRIBUTION_CERTIFICATE_P12 --repo "$REPO"
gh secret set DISTRIBUTION_CERTIFICATE_PASSWORD --repo "$REPO" --body "<the export password you set>"
```

---

## 3. CI keychain password

Just a random string — protects the throwaway keychain fastlane creates on each CI run. Not tied to anything else; generate it once and forget it.

```bash
gh secret set CI_KEYCHAIN_PASSWORD --repo "$REPO" --body "$(openssl rand -base64 32)"
```

---

## 4. App Store provisioning profiles

Three profiles: the main app on each platform, plus the macOS-only QuickLook extension. Create these at [developer.apple.com/account/resources/profiles/list](https://developer.apple.com/account/resources/profiles/list) if they don't already exist — type **App Store**, matching App ID, signed with the Distribution cert from step 2 — then download each `.mobileprovision`/`.provisionprofile`.

| Profile | App ID | Platform |
|---|---|---|
| Marklens macOS App Store | `solutions.ddj.marklens` | macOS |
| Marklens iOS App Store | `solutions.ddj.marklens` | iOS |
| MarklensQuickLook macOS App Store | `solutions.ddj.marklens.QuickLook` | macOS |

```bash
base64 -i Marklens_macOS_AppStore.provisionprofile | tr -d '\n' | gh secret set PROVISIONING_PROFILE_MACOS --repo "$REPO"
base64 -i Marklens_iOS_AppStore.mobileprovision    | tr -d '\n' | gh secret set PROVISIONING_PROFILE_IOS --repo "$REPO"
base64 -i MarklensQuickLook_AppStore.provisionprofile | tr -d '\n' | gh secret set PROVISIONING_PROFILE_QUICKLOOK --repo "$REPO"
```

---

## Verify

```bash
gh secret list --repo "$REPO"
```

You should see all 9 secrets:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_CONTENT`
- `DISTRIBUTION_CERTIFICATE_P12`
- `DISTRIBUTION_CERTIFICATE_PASSWORD`
- `CI_KEYCHAIN_PASSWORD`
- `PROVISIONING_PROFILE_MACOS`
- `PROVISIONING_PROFILE_IOS`
- `PROVISIONING_PROFILE_QUICKLOOK`

(`DEVELOPMENT_TEAM`, `997P2237XV`, is not a secret — it already lives in `project.yml`.)

---

## When this needs to be redone

- **Distribution certificate**: expires yearly. CI will fail with a clear fastlane signing error when it does — regenerate and re-run step 2.
- **Provisioning profiles**: regenerate if the certificate they reference is revoked/replaced, or if a new capability/entitlement is added to the app. Re-run step 4 for the affected profile(s).
- **API key**: doesn't expire on a fixed schedule, but can be revoked from the Integrations page — if that happens, regenerate and re-run step 1.
