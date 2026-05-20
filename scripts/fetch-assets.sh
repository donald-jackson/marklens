#!/usr/bin/env bash
# Fetches mermaid.js and highlight.js into the bundled Web resources directory.
# Run once after cloning (and whenever you want to upgrade asset versions).

set -euo pipefail

MERMAID_VERSION="11.4.1"
HLJS_VERSION="11.10.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/MarklensCore/Sources/MarklensCore/Resources/Web"
mkdir -p "$DEST"

echo "Fetching mermaid@${MERMAID_VERSION} (UMD single-file build)..."
curl -fsSL "https://cdn.jsdelivr.net/npm/mermaid@${MERMAID_VERSION}/dist/mermaid.min.js" \
    -o "$DEST/mermaid.min.js"

echo "Fetching highlight.js@${HLJS_VERSION} (common subset)..."
curl -fsSL "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@${HLJS_VERSION}/build/highlight.min.js" \
    -o "$DEST/highlight.min.js"

echo "Fetching highlight.js themes..."
curl -fsSL "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@${HLJS_VERSION}/build/styles/github.min.css" \
    -o "$DEST/hljs-light.css"
curl -fsSL "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@${HLJS_VERSION}/build/styles/github-dark.min.css" \
    -o "$DEST/hljs-dark.css"

echo "Done. Bundled assets are in: $DEST"
ls -lh "$DEST"
