#!/bin/bash
# Required Prometh gates, sequentially (dist points into the Debug bundle).
set -euo pipefail
cd "$(dirname "$0")/../.."
label="${1:-verify}"
mkdir -p .prometh-logs
scripts/prometh/build.sh > ".prometh-logs/${label}-build.log" 2>&1
printf '%s: build passed\n' "$label"
make verify > ".prometh-logs/${label}-verify.log" 2>&1
printf '%s: runtime verification passed\n' "$label"
xcodebuild test -scheme Prometh -only-testing:PromethTests \
  -derivedDataPath build/PromethParityTests CODE_SIGNING_ALLOWED=NO \
  > ".prometh-logs/${label}-tests.log" 2>&1
printf '%s: PromethTests passed\n' "$label"
