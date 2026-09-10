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
python - "$root/Menu.qml" "$tmp/AppLibraryReconciliationFixture.qml" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
start = source.index('  onAppLibraryChanged: {')
end = source.index('  property bool deleteConfirmOpen:', start)
timer = re.search(r'  Timer \{\n    id: appRowsMergeDebounce\b.*?\n  \}', source, re.S)
assert timer is not None
Path(sys.argv[2]).write_text('''import QtQuick
import "app-library-fallback-state.js" as State
Item {
  id: root
  property var appLibrary: null
  property var providersLoaded: ({apps: true})
  property int providerRevision: 0
  property double appIconIndexUpdatedAt: 0
  property bool appIconRefreshPending: false
  function mergeAppRows() {
    State.reconciliations++
    State.lastLibraryWasNull = root.appLibrary === null
  }
''' + source[start:end] + timer.group(0) + '\n}\n')
PY
output="$(QT_QPA_PLATFORM=offscreen timeout 10 quickshell --no-color -p "$tmp/app-library-fallback-harness.qml" 2>&1)"
printf '%s\n' "$output"
if grep -F 'HARNESS_FAIL' <<<"$output" >/dev/null; then exit 1; fi
grep -F 'HARNESS_OK app library fallback lifecycle' <<<"$output" >/dev/null
test "$(grep -c 'Omalaunch: fallback app library could not load:' <<<"$output")" -eq 1
if grep -E 'TypeError|ReferenceError|Binding loop|cleanup failed' <<<"$output"; then exit 1; fi
echo "ok - fallback selection, recovery, and launch feedback cleanup"
