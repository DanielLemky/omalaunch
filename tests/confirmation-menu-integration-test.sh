#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v quickshell >/dev/null 2>&1; then
  echo "ok - Quickshell confirmation-menu harness skipped (quickshell unavailable)"
  exit 0
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/ConfirmationMenu.qml" "$root/tests/confirmation-menu-harness.qml" "$tmp/"
ln -s /usr/share/omarchy/shell/Commons "$tmp/Commons"
ln -s /usr/share/omarchy/shell/Ui "$tmp/Ui"
output="$(timeout 8 quickshell --no-color -p "$tmp/confirmation-menu-harness.qml" 2>&1)"
printf '%s\n' "$output"
grep -q "HARNESS_OK confirmation menu order default and escape behavior" <<<"$output"
echo "ok - Confirmation menu handles independent order, default, and Escape"
