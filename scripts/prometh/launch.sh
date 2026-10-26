#!/bin/bash
# Launch Prometh. --fresh uses a throwaway support directory and clears defaults.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
app="$root/build/NativDevelopmentDerivedData/Build/Products/Debug/Prometh.app"
log_dir="${PROMETH_LOG_DIR:-$root/Docs/progress/${PROMETH_MILESTONE:-M1}}"
mkdir -p "$log_dir"
log_file="$log_dir/launch.log"

fresh=0
args=()
for arg in "$@"; do
  if [[ "$arg" == "--fresh" ]]; then
    fresh=1
  else
    args+=("$arg")
  fi
done

if [[ ! -d "$app" ]]; then
  echo "error: $app is missing. Run scripts/prometh/build.sh first." >&2
  exit 1
fi

env_args=()
if [[ "$fresh" == "1" ]]; then
  support="$(mktemp -d "${TMPDIR:-/tmp}/prometh-fresh.XXXXXX")"
  export PROMETH_SUPPORT_DIR="$support"
  defaults delete studio.prometh.Prometh >/dev/null 2>&1 || true
  env_args+=(--env "PROMETH_SUPPORT_DIR=$support")
  echo "fresh support: $support" | tee "$log_file"
fi

: > "$log_file"
open_cmd=(open -n "$app" --stdout "$log_file" --stderr "$log_file")
if [[ ${#env_args[@]} -gt 0 ]]; then
  open_cmd+=("${env_args[@]}")
fi
if [[ ${#args[@]} -gt 0 ]]; then
  open_cmd+=(--args "${args[@]}")
fi
"${open_cmd[@]}"

deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  window_id="$("$root/scripts/prometh/windowid.sh" || true)"
  if [[ -n "$window_id" ]]; then
    echo "window ready $window_id" | tee -a "$log_file"
    exit 0
  fi
  sleep 0.4
done

echo "error: Prometh window did not appear" | tee -a "$log_file" >&2
exit 1
