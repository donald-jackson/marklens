---
title: Developer ID (DMG) CI secrets
---

# Developer ID (DMG) CI secrets

Setup guide for the credentials the `dmg.yml` GitHub Actions workflow needs to build, sign, and notarize the `.dmg` people download from GitHub Releases to install Marklens **outside** the Mac App Store.

Only **two new secrets** — everything else `dmg.yml` needs (the App Store Connect API key it notarizes with, and the CI keychain password) is already set up by [App Store Connect CI secrets](appstore-connect-secrets.md).

Do this signed in as the account that manages the `997P2237XV` team (`apple@ddj.solutions`), with **Account Holder** access — Admin is not enough, Apple restricts Developer ID certificate creation to the Account Holder.

```
export REPO=donald-jackson/marklens
```

---

## Why a *different* certificate from the App Store one

The `DISTRIBUTION_CERTIFICATE_P12` secret already in the repo is an **Apple Distribution** certificate. That one only signs builds destined for the App Store: Apple will not notarize anything signed with it, and macOS will not accept it on a download. Direct distribution needs a **Developer ID Application** certificate, which is a separate certificate type issued from the same team.

The two coexist happily — adding this one doesn't affect `appstore.yml` in any way.

---

## 1. Developer ID Application certificate

Apple allows a maximum of **two** Developer ID Application certificates per team, and (unlike other types) **they cannot be revoked and reissued freely** — treat the exported `.p12` as the backup copy that matters, and keep it somewhere safe.

**If the team already has one**: open **Keychain Access**, look under *My Certificates* for `Developer ID Application: ...`. If it's there with a private key nested under its disclosure triangle, skip to the export step.

**To create one**: Xcode → Settings → Accounts → select your Apple ID → **Manage Certificates** → **+** → **Developer ID Application**. (Or on the portal: [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) → **+** → *Developer ID Application* → *G2 Sub-CA*, which needs a CSR generated from Keychain Access → Certificate Assistant.)

**To export**: in **Keychain Access**, select both the `Developer ID Application: ...` certificate **and** the private key nested underneath it → right-click → **Export 2 items…** → save as `.p12` → set an export password when prompted.

```bash
base64 -i DeveloperIDCert.p12 | tr -d '\n' | gh secret set DEVELOPER_ID_CERTIFICATE_P12 --repo "$REPO"
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo "$REPO" --body "<the export password you set>"
```

Exporting only the certificate without its private key is the usual mistake — the workflow fails at `Import Developer ID signing certificate` with no `Developer ID Application` identity found, and prints whatever identities the `.p12` *did* contain.

---

## 2. Notarization credentials

Nothing to do — `dmg.yml` notarizes with `xcrun notarytool` using the **existing** App Store Connect API key secrets (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT`) from step 1 of [App Store Connect CI secrets](appstore-connect-secrets.md). The **App Manager** access level that key was created with covers notarization.

---

## Verify

```bash
gh secret list --repo "$REPO"
```

Alongside the 11 App Store secrets you should now see:

- `DEVELOPER_ID_CERTIFICATE_P12`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`

Then run the workflow:

```bash
gh workflow run dmg.yml --repo "$REPO" -f tag=v1.0.2
gh run watch --repo "$REPO"
```

Expect roughly 8–12 minutes: most of it is the Release build, plus 1–5 minutes waiting on Apple's notary service.

---

## Checking the result

Download the `.dmg` from the release **in a browser** (a `curl` download doesn't set the quarantine attribute, so it won't exercise Gatekeeper at all), then:

```bash
spctl --assess --type open --context context:primary-signature -vv ~/Downloads/Marklens.dmg
xcrun stapler validate ~/Downloads/Marklens.dmg
```

Both should pass. The real test is opening the `.dmg` and dragging `Marklens.app` to Applications on a Mac that has never built this project — it should launch on double-click with no warning at all.

---

## When this needs to be redone

- **Developer ID Application certificate**: expires after 5 years. Notarized builds already out in the wild keep working after it expires (that's what the `--timestamp` on every signature is for), but CI can't sign new ones — re-run step 1.
- **API key**: shared with `appstore.yml`; if it's revoked, notarization fails alongside App Store uploads. See step 1 of [App Store Connect CI secrets](appstore-connect-secrets.md).
