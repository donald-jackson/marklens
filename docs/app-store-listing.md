---
title: App Store Listing Copy
---

# App Store listing — Marklens 1.0

Paste these into the matching fields in App Store Connect → My Apps → Marklens → **App Information** and **App Store** tabs. Character limits noted in parentheses.

---

## Name (30 max)

```
Marklens
```

## Subtitle (30 max)

```
Native Markdown viewer
```

Alternates if you want a different angle:

- `Open any Markdown file fast.` (29)
- `Read Markdown. Nothing else.` (29)
- `Mermaid + code, rendered fast.` (30)

---

## Promotional text (170 max — editable any time, no review needed)

```
Click .md, see it rendered. No editor, no fuss — just clean typography,
syntax-highlighted code, and Mermaid diagrams, all offline.
```

---

## Description (4000 max)

```
Marklens is a fast, native Markdown viewer for macOS, iPadOS, and iPhone.
Open any .md file with a click and see it rendered immediately — beautiful
typography, light and dark themes, syntax-highlighted code, and Mermaid
diagrams. No editor, no library, no friction.

HIGHLIGHTS

• Instant render — every .md opens in a clean, focused window
• 30+ language syntax highlighting via highlight.js, bundled offline
• Mermaid 11 diagrams — flowcharts, sequence, state, xy-charts and more
• GitHub-Flavored Markdown — tables, task lists, footnotes, strikethrough
• Light and dark theme matching the system appearance
• Quick Look on macOS — press Space on any .md in Finder for a rendered preview
• Export to PDF on every platform
• Pinch-to-zoom on iPadOS and iPhone, ⌘+ / ⌘− / ⌘0 on macOS
• Open files via drag-and-drop, the Share Sheet, or the Files app

MADE FOR READING

Marklens doesn't try to be a notes app or a knowledge base. It opens a
file, renders it perfectly, and gets out of the way. If you write Markdown
in another tool — VS Code, Obsidian, GitHub, your favorite text editor —
Marklens is the viewer you reach for to look at the result.

PRIVATE BY DESIGN

Marklens collects nothing. No analytics, no telemetry, no crash reports,
no network requests. Every rendering asset — Mermaid, highlight.js,
fonts — ships inside the app. Read the full privacy policy at
https://donald-jackson.github.io/marklens/privacy/

OPEN SOURCE

Marklens is MIT-licensed and developed in the open. Source, issues, and
contribution guide live at https://github.com/donald-jackson/marklens.
```

---

## Keywords (100 max, comma-separated, no spaces after commas to save chars)

```
markdown,md viewer,mermaid,readme,github,gfm,syntax,quicklook,reader,fast,native,diagrams,preview
```

That's 93 chars. Apple ranks each token equally; favour high-intent words.

---

## What's New (4000 max) — version 1.0

```
First release.

• Native rendering on macOS, iPadOS, and iPhone
• Offline code highlighting in 30+ languages via highlight.js
• Offline Mermaid 11 diagrams
• GitHub-Flavored Markdown: tables, task lists, footnotes, strikethrough
• Quick Look extension on macOS — preview .md files in Finder
• Export rendered documents to PDF
• Light and dark themes that follow the system
• MIT-licensed and open source

Thanks for trying Marklens. Feedback and bug reports welcome at
https://github.com/donald-jackson/marklens/issues.
```

---

## App Privacy questionnaire answers

App Store Connect asks a questionnaire before you can submit. For Marklens, every answer is the same:

- **Do you collect data from this app?** → **No**

That's it. No further follow-up questions. Save and you're done with the Privacy section.

---

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | `https://donald-jackson.github.io/marklens/privacy/` |
| Support URL | `https://github.com/donald-jackson/marklens/issues` |
| Marketing URL (optional) | `https://github.com/donald-jackson/marklens` |

---

## Categories

- **Primary**: Productivity
- **Secondary** (optional but recommended): Developer Tools

---

## Age rating

All "No" answers. Final rating: **4+**.

---

## Copyright

App Store Connect → **App Information** → **General Information** → **Copyright** field:

```
© 2026 Donald Jackson
```

Apple's preferred format for individual developers is `© <year> <name>` (the year the app was first published, not the current year — leave it as `2026` for the entire 1.x lifecycle). This string appears at the bottom of the App Store listing under "Information".

The matching `NSHumanReadableCopyright` value in `Marklens/Info.plist` is what macOS shows in **Marklens → About Marklens**:

```xml
<key>NSHumanReadableCopyright</key>
<string>© 2026 Donald Jackson. MIT-licensed.</string>
```

The "MIT-licensed" tail is optional but useful for open-source apps — it signals the licensing without requiring users to find LICENSE on GitHub.

---

## Pricing & availability

- **Price**: Free
- **Availability**: All countries / regions
- **No in-app purchases**

---

## Review notes (App Review Information)

Paste this in the **Notes** field under App Review Information. It pre-empts the one question a reviewer is likely to ask:

```
Marklens declares the com.apple.security.network.client entitlement only
because Apple's WKWebView framework requires it to initialise its
WebContent XPC process when rendering bundled local HTML. The app makes
no network requests and contains no networking code. All assets used to
render Markdown (Mermaid, highlight.js, fonts, themes) are bundled inside
the app and loaded from the main bundle.

Marklens collects no user data. There are no analytics, no telemetry, no
crash reporting frameworks, and no third-party SDKs. PrivacyInfo.xcprivacy
manifests are included for both the app and the Quick Look extension and
declare the same — no tracking, no data collection.

The Quick Look extension renders the same HTML the app produces, using
the same MarklensCore library. It runs sandboxed and inherits the same
empty data-collection profile.

Source: https://github.com/donald-jackson/marklens
```

No demo account required (the app has no login).

---

## Screenshots

Required by App Store Connect:

| Platform | Required size | Min count |
|---|---|---|
| iPhone 6.9" (17 Pro / Max) | 1320 × 2868 | 1 |
| iPad 13" | 2064 × 2752 | 1 |
| Mac | 1280 × 800 (up to 2880 × 1800) | 1 |

Recommended: 3–5 screenshots per platform showing a mix of:
1. Welcome / launch screen
2. A rendered document (try `Samples/welcome.md`)
3. Code-highlighting showcase (`Samples/code-showcase.md`)
4. Mermaid diagrams (`Samples/diagrams.md`)
5. The app icon nicely positioned (Mac only — Quick Look preview in Finder is a great hero shot)

Use `scripts/screenshot.sh` (see repo root) to auto-capture from booted simulators.
