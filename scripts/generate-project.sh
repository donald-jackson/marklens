#!/usr/bin/env bash
# Generate Marklens.xcodeproj from project.yml and fix two known XcodeGen
# quirks around the macOS-only QuickLook extension:
#
# 1. XcodeGen writes `platformFilter = maccatalyst` when we asked for macOS
#    on the embed build file and on the PBXTargetDependency entry.
# 2. Xcode 17 requires `platformFilters = (macos,)` (the array form) on
#    the embed build file, not the singular `platformFilter = macos`,
#    or it ignores the filter and tries to embed the .appex into iOS builds.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

PBX="$ROOT/Marklens.xcodeproj/project.pbxproj"

python3 - "$PBX" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

# 1a: embed build file — switch from singular `platformFilter = maccatalyst`
# to array form `platformFilters = (macos,)`. Xcode 17 honors the array
# form for "only this platform" inclusion.
src_new, n_embed = re.subn(
    r'(MarklensQuickLook\.appex in Embed[^\n]*?)platformFilter = maccatalyst',
    r'\1platformFilters = (macos, )',
    src,
)

# 1b: PBXTargetDependency entry — same fix (block form).
src_new, n_dep = re.subn(
    r'(isa = PBXTargetDependency;\s*)platformFilter = maccatalyst(;\s*target = [A-F0-9]+ /\* MarklensQuickLook)',
    r'\1platformFilters = (macos, )\2',
    src_new,
)

path.write_text(src_new)
print(f"✓ patched embed platformFilters ({n_embed}), target-dep platformFilters ({n_dep})")
PY
