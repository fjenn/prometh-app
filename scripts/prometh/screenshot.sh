#!/bin/bash
# Capture the front Prometh window into Docs/progress/<milestone>/<name>.png.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: screenshot.sh <name>" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/../.." && pwd)"
milestone="${PROMETH_MILESTONE:-M1}"
destination="$root/Docs/progress/$milestone/$1.png"
mkdir -p "$(dirname "$destination")"

window_id="$("$root/scripts/prometh/windowid.sh")"

if [[ -z "$window_id" ]]; then
  echo "error: no Prometh window to capture" >&2
  exit 1
fi

screencapture -o -l "$window_id" "$destination"
echo "$destination"
