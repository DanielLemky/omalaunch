#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
converter="$root/extensions/timezone/convert-timezone.py"

assert_contains() {
  local query="$1" expected="$2" actual
  actual=$(python "$converter" "$query")
  [[ $actual == *"$expected"* ]] || {
    printf 'not ok - %s\n  expected to contain: %s\n  actual: %s\n' "$query" "$expected" "$actual" >&2
    exit 1
  }
  printf 'ok - %s => %s\n' "$query" "$actual"
}

assert_contains "time seattle" "America/Los_Angeles"
assert_contains "time 2026-01-15 9am winnipeg to seattle" "7:00 AM PST"
assert_contains "time 2026-11-15 8pm new york to london" "Mon, Nov 16"
assert_contains "time nowhereville" "Unknown timezone: nowhereville"
