# Contributing to Marklens

Thanks for your interest in improving Marklens. A few ground rules to keep PRs
landable.

## Scope

Marklens is intentionally a **viewer**, not an editor or library. PRs that add
editing, file browsing, vaults, sync, or plugin systems are likely to be closed.
The whole pitch is: click `.md` → see it rendered, fast, native. Features that
work against that pitch are out of scope.

In scope:
- Markdown rendering bugs / GFM gaps
- Code highlight or Mermaid issues
- Platform polish (keyboard shortcuts, accessibility, dark mode edge cases)
- Performance (faster cold open, large-doc handling)
- Test coverage

## Dev setup

```bash
./scripts/fetch-assets.sh          # downloads mermaid + highlight.js
brew install xcodegen
./scripts/generate-project.sh      # writes Marklens.xcodeproj
open Marklens.xcodeproj
```

## Before opening a PR

1. Tests pass:
   ```bash
   cd MarklensCore
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
   ```
2. Both targets build clean:
   ```bash
   xcodebuild -project Marklens.xcodeproj -scheme Marklens -destination 'platform=macOS' build
   xcodebuild -project Marklens.xcodeproj -scheme Marklens -destination 'generic/platform=iOS Simulator' build
   ```
3. New behavior has a test. The snapshot tests in `MarklensCoreTests` are a
   good template — assert on substrings of the emitted HTML.

## Commit style

Focus the message on the *why*, not the *what*. The diff already shows what.
Multi-paragraph messages are fine and encouraged for non-trivial changes.

## Where things live

| You're touching… | Look in |
|---|---|
| Markdown → HTML logic | `MarklensCore/Sources/MarklensCore/MarkdownRenderer.swift` |
| The HTML template (CSS injection, theme switching) | `MarklensCore/Sources/MarklensCore/HTMLTemplate.swift` + `Resources/Web/styles.css` |
| Window chrome, toolbar | `Marklens/View/Toolbar.swift`, `Marklens/ContentView.swift` |
| WebView config (sandbox, JS, navigation policy) | `Marklens/View/MarkdownWebView.swift` |
| Relative image/link resolution (sandbox folder grant, `marklens-asset:` scheme) | `Marklens/Document/AssetSchemeHandler.swift`, `Marklens/Document/FolderAccessStore.swift`, `MarklensCore/Sources/MarklensCore/RelativeReferenceRewriter.swift` |
| File handling / UTI registration | `Marklens/Info.plist`, `Marklens/Document/MarkdownDocument.swift` |
| Quick Look | `MarklensQuickLook/` |
| App icon | `design/icon.svg` (regenerate PNGs via the recipe in the README) |
| Project structure | `project.yml` (then run `./scripts/generate-project.sh`) |

## License

By contributing, you agree your work will be licensed under the MIT License
(see [LICENSE](LICENSE)).
