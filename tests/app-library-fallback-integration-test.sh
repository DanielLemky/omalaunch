#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v quickshell >/dev/null 2>&1; then
  echo "ok - app library fallback harness skipped (quickshell unavailable)"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/LauncherAppLibrary.qml" "$root"/tests/app-library-fallback-{fixture.qml,state.js,harness.qml} "$tmp/"
python3 - "$root/Menu.qml" "$tmp/app-library-fallback-harness.qml" <<'PY'
import pathlib
import re
import sys

menu = pathlib.Path(sys.argv[1]).read_text()
block = re.search(r'  LauncherAppLibrary \{.*?\n  \}', menu, re.S).group()
binding = re.search(r'^    fallbackEnabled: (.+)$', block, re.M).group(1)
harness = pathlib.Path(sys.argv[2])
harness.write_text(harness.read_text().replace('/* MENU_FALLBACK_ENABLED */ false', binding))
PY
output="$(QT_QPA_PLATFORM=offscreen timeout 10 quickshell --no-color -p "$tmp/app-library-fallback-harness.qml" 2>&1)"
printf '%s\n' "$output"
if grep -F 'HARNESS_FAIL' <<<"$output" >/dev/null; then exit 1; fi
grep -F 'HARNESS_OK app library fallback lifecycle' <<<"$output" >/dev/null
test "$(grep -c 'Omalaunch: fallback app library could not load:' <<<"$output")" -eq 1
if grep -E 'TypeError|ReferenceError|Binding loop|cleanup failed' <<<"$output"; then exit 1; fi
echo "ok - fallback selection, recovery, and launch feedback cleanup"
