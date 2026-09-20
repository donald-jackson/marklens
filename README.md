# Marklens

A native, click-to-open Markdown viewer for **macOS** and **iPadOS**.
Single SwiftUI codebase. Renders code blocks (highlight.js) and Mermaid diagrams,
both bundled offline. No editor, no library — just `double-click` → rendered.

<p align="center">
  <img src="design/icon.svg" width="160" alt="Marklens icon"/>
</p>

## Why

Existing markdown viewers on macOS are either heavyweight editors (Bear, Obsidian, Typora),
default to plain-text preview (Quick Look), or are web apps wrapped in Electron. Marklens is
a small native binary that opens instantly, renders correctly (GFM tables, task lists,
Mermaid, syntax highlighting), and gets out of your way.

## Features

- ✓ Native SwiftUI shell (macOS 14+, iPadOS 17+)
- ✓ GitHub-flavored markdown via Apple's `swift-markdown`
- ✓ Code syntax highlighting (highlight.js, ~50KB bundled)
- ✓ Mermaid diagrams (mermaid.js, fully offline)
- ✓ LaTeX math — `$…$` and `$$…$$` (KaTeX, fully offline)
- ✓ Light/dark theme follows system, no reload
- ✓ macOS Quick Look extension — press space on any `.md`
- ✓ Drag-and-drop, Open With, recent files (all from `DocumentGroup`)

## Project layout

```
marklens/
├── Marklens/                     SwiftUI app (macOS + iPadOS)
├── MarklensCore/                 SwiftPM package: parser → HTML + bundled web assets
├── MarklensQuickLook/            macOS Quick Look extension
├── Samples/welcome.md            test fixture
├── design/icon.svg               source-of-truth app icon
├── scripts/
│   ├── fetch-assets.sh           downloads mermaid.js + highlight.js
│   └── generate-project.sh       xcodegen + a pbxproj patch (see below)
└── project.yml                   XcodeGen config
```

## Getting started

```bash
# 1. Download bundled web assets (~2.6 MB of mermaid + highlight.js)
./scripts/fetch-assets.sh

# 2. Install XcodeGen + cairosvg (only if you'll regenerate icons)
brew install xcodegen
pipx install cairosvg     # or `python3 -m pip install cairosvg`

# 3. Generate the Xcode project from project.yml
./scripts/generate-project.sh

# 4. Open in Xcode
open Marklens.xcodeproj
```

Select the **Marklens** scheme and either:
- Run on **My Mac** for the macOS build (Quick Look extension included)
- Run on an **iPad simulator / device** for the iPadOS build (no Quick Look — iOS doesn't support it)

> **iPad runtime**: if Xcode shows "iOS X.Y is not installed", open Xcode → Settings → Components and install the matching iOS simulator runtime.

## Tests

The MarklensCore package can be tested without opening Xcode:

```bash
cd MarklensCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

7 tests cover heading/paragraph rendering, inline formatting, fenced code blocks,
mermaid passthrough (escaped → unescaped), tables, and links.

## Architecture (short version)

- **swift-markdown** (Apple) parses to AST. `HTMLFormatter` emits HTML.
- A tiny post-processor swaps `<pre><code class="language-mermaid">…</code></pre>` for `<div class="mermaid">…</div>` (with unescaped content — Mermaid parses its own text).
- A single **WKWebView** displays the result. `loadHTMLString(html, baseURL:)` resolves relative paths to the bundled `Resources/Web/` folder, so styles/scripts load with zero network access.
- Theme flips do **not** reload — JS is injected to update `data-theme` and the active hljs stylesheet.

Why hybrid native+WKWebView? Pure-Swift rendering with `AttributedString` makes
Mermaid + tables + code highlight painful. Pure-WKWebView pays ~150ms parsing
markdown in JS on every open. Native parse + WKWebView paint is the sweet spot,
and it's the same architecture Bear, Quiver, and Obsidian use.

## Gotchas captured in code

A few things tripped me up during the build. They're all fixed now; recording
them here so future contributors don't relive them.

- **`com.apple.security.network.client` is required** even for purely local content.
  Without it WKWebView's WebContent XPC process can't initialize under sandbox and
  the view silently renders nothing — no error, no delegate callback. See
  `Marklens/Marklens.entitlements`.
- **`Bundle.module.url(forResource:withExtension:)` doesn't resolve directories.**
  Look up a known file (`styles.css`) and take its parent. See
  `MarklensCore/Sources/MarklensCore/WebResources.swift`.
- **XcodeGen's `platformFilter: macOS` writes `maccatalyst` to pbxproj** (means
  "Mac Catalyst only" — excludes native macOS too). And **Xcode 17 ignores the
  singular `platformFilter`** for "only on this platform" semantics — it wants
  the array form `platformFilters = (macos,)`. `scripts/generate-project.sh`
  patches both occurrences.
- **Quick Look NSExtension priority is fragile.** Ad-hoc-signed dev builds need a
  manual `pluginkit -e use -i solutions.ddj.marklens.QuickLook` election to win over
  the system's built-in plain-text preview for `.md`.

## Asset versions

`scripts/fetch-assets.sh` pins:

- mermaid `11.4.1` (UMD single-file build, ~2.5 MB)
- highlight.js `11.10.0` (common subset, ~120 KB)
- highlight.js themes: GitHub light + GitHub dark
- KaTeX `0.18.7` (~270 KB JS + 24 KB CSS + 20 woff2 faces, ~300 KB)

Edit the script to bump versions.

## File handling on macOS

After first launch, right-click any `.md` file in Finder → **Open With** → Marklens.
To make it the default:

```
Get Info on a .md file → Open with: Marklens → Change All...
```

The bundled Quick Look extension activates automatically — select a `.md` in Finder
and press **Space** for an instant preview without opening the app.

## License

Marklens is released under the [MIT License](LICENSE).

Third-party dependencies (swift-markdown, swift-cmark, mermaid.js, highlight.js)
are all under permissive licenses — see [NOTICES.md](NOTICES.md) for the full
attribution and license texts. License audit on initial release: clear of GPL /
LGPL / AGPL / SSPL.

## Contributing

PRs welcome. Quick start:

```bash
git clone https://github.com/YOURUSER/marklens.git
cd marklens
./scripts/fetch-assets.sh
./scripts/generate-project.sh
cd MarklensCore && xcrun swift test    # confirm tests pass before changes
```

Please run the snapshot tests before opening a PR, and keep commit messages
focused on the *why* rather than the *what*.
