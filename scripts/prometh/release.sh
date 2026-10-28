#!/bin/bash
# Reproducible ad-hoc portable release; nothing is installed or published here.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
export PYTHONDONTWRITEBYTECODE=1
if [[ "${1:-}" == "--provision" ]]; then
  python3 scripts/prometh/provision-runtime.py
elif [[ $# != 0 ]]; then
  echo "usage: $0 [--provision]" >&2; exit 2
fi
for runtime in reader searxng composio_mcp media; do
  [[ -d "PromethRuntime/$runtime/site-packages" ]] || { echo "Missing $runtime: use --provision" >&2; exit 1; }
done
scripts/prometh/build-webui.sh
xcodegen generate
xcodebuild build -scheme Prometh -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData CODE_SIGNING_ALLOWED=NO
app="$root/build/NativDevelopmentDerivedData/Build/Products/Release/Prometh.app"
# Sign every native extension, including .so files stored as framework resources.
python3 scripts/prometh/sign-bundle.py "$app"
codesign -s - --force --deep --options runtime --timestamp=none \
  --entitlements Configuration/Prometh-AdHoc.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
mkdir -p .prometh-logs dist
python3 scripts/prometh/audit-bundle.py "$app" --report .prometh-logs/portable-audit-after.json
python3 scripts/prometh/verify-runtime.py "$app" --report .prometh-logs/portable-release-imports.json
# Keyword inventory is deliberately file names/counts, never matching contents.
# Its manual review is recorded in portable-audit-after.txt during verification.
rm -f dist/Prometh.zip
ditto -c -k --keepParent "$app" dist/Prometh.zip
bytes="$(stat -f '%z' dist/Prometh.zip)"
if (( bytes >= 1950000000 )); then
  echo "error: ZIP $bytes bytes exceeds the 1,950,000,000-byte release limit" >&2; exit 1
fi
printf 'ZIP bytes: %s\n' "$bytes"
shasum -a 256 dist/Prometh.zip
