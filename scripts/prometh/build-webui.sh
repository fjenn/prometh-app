#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root/WebUI"
if [[ ! -d node_modules ]]; then npm ci; fi
npm run build
