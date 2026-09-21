#!/usr/bin/env bash
# Fetches mermaid.js, highlight.js and KaTeX into the bundled Web resources directory.
# Run once after cloning (and whenever you want to upgrade asset versions).

set -euo pipefail

MERMAID_VERSION="11.4.1"
HLJS_VERSION="11.10.0"
KATEX_VERSION="0.18.7"

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

echo "Fetching KaTeX@${KATEX_VERSION}..."
curl -fsSL "https://cdn.jsdelivr.net/npm/katex@${KATEX_VERSION}/dist/katex.min.js" \
    -o "$DEST/katex.min.js"
curl -fsSL "https://cdn.jsdelivr.net/npm/katex@${KATEX_VERSION}/dist/katex.min.css" \
    -o "$DEST/katex.min.css"

# The complete woff2 set for this release. katex.min.css also lists .woff and
# .ttf fallbacks we don't ship — WebKit stops after woff2 succeeds, so they are
# never requested. The CSS's url(fonts/…) resolves against the stylesheet's own
# location, which is this directory.
echo "Fetching KaTeX fonts (20 woff2 faces)..."
mkdir -p "$DEST/fonts"
for face in \
    KaTeX_AMS-Regular \
    KaTeX_Caligraphic-Bold KaTeX_Caligraphic-Regular \
    KaTeX_Fraktur-Bold KaTeX_Fraktur-Regular \
    KaTeX_Main-Bold KaTeX_Main-BoldItalic KaTeX_Main-Italic KaTeX_Main-Regular \
    KaTeX_Math-BoldItalic KaTeX_Math-Italic \
    KaTeX_SansSerif-Bold KaTeX_SansSerif-Italic KaTeX_SansSerif-Regular \
    KaTeX_Script-Regular \
    KaTeX_Size1-Regular KaTeX_Size2-Regular KaTeX_Size3-Regular KaTeX_Size4-Regular \
    KaTeX_Typewriter-Regular ; do
    curl -fsSL "https://cdn.jsdelivr.net/npm/katex@${KATEX_VERSION}/dist/fonts/${face}.woff2" \
        -o "$DEST/fonts/${face}.woff2"
done

echo "Done. Bundled assets are in: $DEST"
ls -lh "$DEST"
