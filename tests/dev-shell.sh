#!/usr/bin/env bash
# Run Omalaunch's menu from this checkout, without installing it as a plugin.
#
#   tests/dev-shell.sh                 open the launcher's starting view
#   tests/dev-shell.sh emoji           open straight into the Emoji grid
#   tests/dev-shell.sh files           open straight into the file browser
#
# The argument is an extension capability. Escape closes the launcher and exits.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
capability="${1:-}"

if ! command -v quickshell >/dev/null 2>&1; then
  echo "dev-shell: quickshell is not installed" >&2
  exit 1
fi

if [[ ! -d $omarchy_path/shell/Commons ]]; then
  echo "dev-shell: no Omarchy shell modules under $omarchy_path/shell" >&2
  exit 1
fi

work="$(mktemp -d -t omalaunch-dev-XXXXXX)"
trap 'rm -rf "$work"' EXIT

# `import qs.Commons` resolves against the shell root, so Omarchy's modules have
# to sit beside this checkout. Symlink them rather than copying: a stale copy of
# Style/Color would hide theme regressions.
for module in "$omarchy_path"/shell/*; do
  name="$(basename "$module")"
  [[ $name == shell.qml || $name == plugins ]] && continue
  ln -s "$module" "$work/$name"
done
ln -s "$root" "$work/omalaunch"
cp "$root/tests/dev-shell.qml" "$work/shell.qml"

OMALAUNCH_DEV_SOURCE="$root" \
OMALAUNCH_DEV_CAPABILITY="$capability" \
  exec quickshell --no-color -p "$work/shell.qml"
