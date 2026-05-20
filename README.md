# Marklens

A native, click-to-open Markdown viewer for **macOS** and **iPadOS**.
Single SwiftUI codebase. Renders code blocks (highlight.js) and Mermaid diagrams. Offline — no network.

## Project layout

```
marklens/
├── Marklens/                     # SwiftUI app (macOS + iPadOS)
├── MarklensCore/                 # SwiftPM package: parser → HTML + bundled web assets
├── MarklensQuickLook/            # macOS Quick Look extension
├── Samples/welcome.md            # test fixture
├── scripts/fetch-assets.sh       # downloads mermaid.js + highlight.js
└── project.yml                   # XcodeGen config
```

## First-time setup

```bash
# 1. Download bundled web assets (mermaid, highlight.js, themes)
./scripts/fetch-assets.sh

# 2. Install XcodeGen if you don't have it
brew install xcodegen

# 3. Generate the Xcode project from project.yml
./scripts/generate-project.sh    # wraps `xcodegen generate` + patches a known XcodeGen quirk

# 4. Open in Xcode
open Marklens.xcodeproj
```

Then select the **Marklens** scheme and either:
- Run on **My Mac** for the macOS build (Quick Look extension included)
- Run on an **iPad simulator / device** for the iPadOS build (no Quick Look — iOS doesn't support it)

The macOS-only Quick Look extension is conditionally excluded from iOS builds via a patched `platformFilters = (macos,)` entry — see `scripts/generate-project.sh`.

> **iPad runtime**: if Xcode shows "iOS X.Y is not installed", open Xcode → Settings → Components and install the matching iOS simulator runtime.

## Running tests (CLI)

The MarklensCore package can be tested without opening Xcode:

```bash
cd MarklensCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

7 tests cover heading/paragraph rendering, inline formatting, code blocks, the **mermaid passthrough** (escaped → raw), tables, and links.

## Architecture

- **swift-markdown** (Apple) parses `.md` to AST.
- `HTMLFormatter` emits HTML; a tiny post-processor swaps `<pre><code class="language-mermaid">…</code></pre>` for `<div class="mermaid">…</div>` (with unescaped content — Mermaid parses its own text).
- A single **WKWebView** displays the result. `loadHTMLString(html, baseURL:)` resolves relative paths to the bundled `Resources/Web/` folder, so styles/scripts load with zero network access.
- Theme flips do not reload — JS is injected to update `data-theme` and the active hljs stylesheet.

Why this hybrid? Pure-Swift rendering with `AttributedString` makes Mermaid + tables + code highlight painful. Pure-WKWebView pays ~150ms parsing markdown in JS on every open. Native parse + WKWebView paint is the sweet spot.

## Out of scope (v1)

Editor, file browser/library, iCloud sync, search across files, PDF export, plugins. The viewer-only scope is intentional — fastest possible path from `double-click` to `rendered`.

## Asset versions

`scripts/fetch-assets.sh` pins:

- mermaid `11.4.1`  (UMD single-file build, ~2.5 MB)
- highlight.js `11.10.0` (common subset, ~120 KB)
- highlight.js themes: GitHub light + GitHub dark

Edit the script to bump versions.

## File handling on macOS

After first launch, right-click any `.md` file in Finder → **Open With** → Marklens. To make it the default:

```
Get Info on a .md file → "Open with: Marklens" → "Change All..."
```

The bundled Quick Look extension activates automatically — select a `.md` file in Finder and press **Space** for an instant preview without opening the app.
