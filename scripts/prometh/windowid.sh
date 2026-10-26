#!/bin/bash
# Print the on-screen Prometh window id. Does not need Accessibility permission.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
cache="${TMPDIR:-/tmp}/prometh-windowid"
source="$root/windowid.swift"
if [[ ! -x "$cache" || "$source" -nt "$cache" ]]; then
  swiftc -O -o "$cache" "$source"
fi
"$cache" "$@"
