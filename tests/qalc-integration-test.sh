#!/bin/bash
set -euo pipefail

command -v qalc >/dev/null || {
  echo "not ok - qalc is required (install Arch package: libqalculate)" >&2
  exit 1
}

assert_result() {
  local expression="$1" expected="$2" actual
  actual=$(qalc -t -m 1500 "$expression")
  if [[ $actual != "$expected" ]]; then
    printf 'not ok - %s\n  expected: %s\n  actual:   %s\n' "$expression" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'ok - %s => %s\n' "$expression" "$actual"
}

assert_result "10 + 20" "30"
assert_result "2 + 3 * 4" "14"
assert_result "(2 + 3) * 4" "20"
assert_result "1 km to m" "1000 m"

currency=$(qalc -t -m 1500 "10 USD to CAD")
if [[ $currency != CAD\ * ]]; then
  printf 'not ok - currency conversion\n  expected CAD result, actual: %s\n' "$currency" >&2
  exit 1
fi
printf 'ok - 10 USD to CAD => %s\n' "$currency"
