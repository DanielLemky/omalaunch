#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v quickshell >/dev/null 2>&1; then
  echo "ok - Quickshell live-query process harness skipped (quickshell unavailable)"
  exit 0
fi

output="$(timeout 8 quickshell --no-color -p "$root/tests/live-query-process-harness.qml" 2>&1)"
printf '%s\n' "$output"
grep -F 'HARNESS_OK latest accepted; stale output rejected' <<<"$output" >/dev/null

echo "ok - Quickshell live-query process harness coalesces latest and rejects stale output"
