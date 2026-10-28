#!/bin/bash
# Build Prometh.app from the Nativ Xcode project and ad-hoc sign it.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

if command -v node >/dev/null 2>&1; then
  "$root/scripts/prometh/build-webui.sh"
fi

make xcode-build NATIV_PRODUCT_NAME=Prometh

app="$root/build/NativDevelopmentDerivedData/Build/Products/Debug/Prometh.app"
if [[ ! -d "$app" ]]; then
  echo "error: Prometh.app was not produced at $app" >&2
  exit 1
fi

PYTHONDONTWRITEBYTECODE=1 python3 scripts/prometh/sign-bundle.py "$app"
codesign -s - --force --deep --entitlements Configuration/Prometh-AdHoc.entitlements "$app"
echo "Built and ad-hoc signed $app"
