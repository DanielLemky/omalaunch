#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v quickshell >/dev/null 2>&1; then
  echo "ok - Quickshell dynamic-menu model harness skipped (quickshell unavailable)"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/MenuModel.js" "$root/tests/dynamic-menu-model-harness.qml" "$tmp/"
output="$(timeout 8 quickshell --no-color -p "$tmp/dynamic-menu-model-harness.qml" 2>&1)"
printf '%s\n' "$output"
grep -F 'HARNESS_OK dynamic menu normalized in QML' <<<"$output" >/dev/null

echo "ok - Quickshell normalizes dynamic Web Search rows"
