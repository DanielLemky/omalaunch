#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$root/manifest.json"

jq -e '
  .schemaVersion == 1
  and .id == "omalaunch"
  and (.name | type == "string" and length > 0)
  and (.version | type == "string" and length > 0)
  and (.author | type == "string" and length > 0)
  and .license == "MIT"
  and (.kinds | type == "array" and length > 0)
  and (.entryPoints | type == "object")
  and .omarchy.clonedFrom == "omarchy.menu"
' "$manifest" >/dev/null

while IFS= read -r entry_point; do
  [[ $entry_point != /* && $entry_point != *..* ]]
  [[ -f "$root/$entry_point" ]]
done < <(jq -r '.entryPoints[]' "$manifest")

echo "ok - manifest is valid"
