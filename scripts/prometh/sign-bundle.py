#!/usr/bin/env python3
"""Sign native resources from the inside out, with Python JIT/load entitlements."""
import importlib.util
import subprocess
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare-bundle.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
root = Path(sys.argv[1]).resolve()
entitlements = Path(__file__).resolve().parents[2] / "Configuration/Prometh-AdHoc.entitlements"
binaries = sorted((p for p in root.rglob("*") if prepare.macho(p)), key=lambda p: len(p.parts), reverse=True)
for path in binaries:
    subprocess.run(["codesign", "--force", "-s", "-", "--options", "runtime", "--timestamp=none", "--entitlements", str(entitlements), str(path)], check=True, capture_output=True)
print(f"Signed {len(binaries)} native files.")
