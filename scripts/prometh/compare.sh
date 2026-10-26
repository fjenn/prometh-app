#!/bin/bash
# Place each Prometh screenshot beside the reference screenshot of the same name.
# Usage: compare.sh <prometh-dir> <reference-dir> <output-dir>
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: compare.sh <prometh-dir> <reference-dir> <output-dir>" >&2
  exit 1
fi

prometh="$1"
reference="$2"
output="$3"
mkdir -p "$output"

compiler="$(mktemp -d "${TMPDIR:-/tmp}/prometh-compare.XXXXXX")"
cat > "$compiler/main.swift" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: compare <left> <right> <output>\n", stderr)
    exit(2)
}
guard let left = NSImage(contentsOfFile: args[1]), let right = NSImage(contentsOfFile: args[2]) else {
    fputs("unreadable image\n", stderr)
    exit(3)
}
let gap: CGFloat = 24
let width = left.size.width + right.size.width + gap
let height = max(left.size.height, right.size.height)
let canvas = NSImage(size: NSSize(width: width, height: height))
canvas.lockFocus()
NSColor.windowBackgroundColor.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
left.draw(in: NSRect(x: 0, y: (height - left.size.height) / 2, width: left.size.width, height: left.size.height))
right.draw(in: NSRect(x: left.size.width + gap, y: (height - right.size.height) / 2, width: right.size.width, height: right.size.height))
canvas.unlockFocus()
guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("could not encode png\n", stderr)
    exit(4)
}
try png.write(to: URL(fileURLWithPath: args[3]))
SWIFT
swiftc -O -o "$compiler/compare" "$compiler/main.swift"

missing=0
shopt -s nullglob
shots=("$prometh"/*.png)
if [[ ${#shots[@]} -eq 0 ]]; then
  echo "no screenshots in $prometh" >&2
  exit 1
fi
for shot in "${shots[@]}"; do
  name="$(basename "$shot")"
  [[ "$name" == paired-* || "$name" == proof-* ]] && continue
  ref="$reference/$name"
  if [[ ! -f "$ref" ]]; then
    echo "missing reference for $name" >&2
    missing=1
    continue
  fi
  "$compiler/compare" "$shot" "$ref" "$output/paired-$name"
  echo "paired $name"
done
exit "$missing"
