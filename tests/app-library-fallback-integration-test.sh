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
output="$(QT_QPA_PLATFORM=offscreen timeout 10 quickshell --no-color -p "$tmp/app-library-fallback-harness.qml" 2>&1)"
printf '%s\n' "$output"
if grep -F 'HARNESS_FAIL' <<<"$output" >/dev/null; then exit 1; fi
grep -F 'HARNESS_OK app library fallback lifecycle' <<<"$output" >/dev/null
test "$(grep -c 'Omalaunch: fallback app library could not load:' <<<"$output")" -eq 1
if grep -E 'TypeError|ReferenceError|Binding loop|cleanup failed' <<<"$output"; then exit 1; fi
echo "ok - fallback selection, recovery, and launch feedback cleanup"
