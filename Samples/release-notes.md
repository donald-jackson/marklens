# Release notes

## 1.2.0 — 2026-05-28

### New
- **Outline sidebar.** Long documents now show a collapsible table of
  contents on the left. Click any heading to jump.
- **Find in document.** ⌘F opens an in-page finder with match highlighting.
- **Print to PDF presets.** Choose between *Continuous* (one long page)
  and *Paginated* (US Letter / A4) when exporting.

### Improved
- Mermaid diagrams now scale crisply at every zoom level (vector, not raster).
- Cold-launch time for a 1 MB document dropped from 820 ms to ~310 ms.
- Code blocks pick up a subtle scrollbar instead of the always-on rail.

### Fixed
- Quick Look no longer rendered a stale theme after switching System
  Appearance while the preview pane was open.
- Some `.markdown` files (vs `.md`) weren't appearing in *Open Recent*.

---

## 1.1.0 — 2026-04-12

### New
- **Zoom controls** on macOS (⌘+ / ⌘− / ⌘0) and pinch-to-zoom on iPad.
- **Export as PDF** from the toolbar.
- Drag-and-drop a `.md` file onto the app icon to open it.

### Improved
- Reading width now adapts to window size instead of capping at 760 px;
  wide windows finally use their real estate.

### Fixed
- WKWebView occasionally went blank on launch when the sandbox didn't
  have `network.client` (required for WebContent XPC, even offline).

---

## 1.0.0 — 2026-03-04

The first release. 🎉

- Native rendering on macOS and iPadOS
- Offline code highlighting via highlight.js
- Offline diagrams via Mermaid 11
- Quick Look extension on macOS
- Full GitHub-flavored Markdown: tables, task lists, strikethrough

> Marklens is open source under the MIT license. Source on
> [GitHub](https://github.com/donald-jackson/marklens).
