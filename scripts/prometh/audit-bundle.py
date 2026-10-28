#!/usr/bin/env python3
"""Fail closed on local paths, escaping links, credentials or build artifacts.

Reports file names and keyword counts only, never matching contents. Use
--baseline to inventory an unprepared app without rejecting expected findings.
"""
from __future__ import annotations
import argparse
import concurrent.futures
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare-bundle.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
FORBIDDEN = (b"/Users/", b"armando", b"/opt/homebrew", b".venv", b"composio.env")
KEYWORDS = (b"composio", b"api_key", b"apikey", b"secret", b"token", b"bearer", b"gho_", b"ghp_", b"sk-", b"hf_", b"ak_")
CREDENTIAL_SHAPES = (
    rb"(?<![A-Za-z0-9_])gh[opsu]_[A-Za-z0-9]{30,}",
    rb"(?<![A-Za-z0-9_])sk-[A-Za-z0-9]{24,}",
    rb"(?<![A-Za-z0-9_])hf_[A-Za-z0-9]{30,}",
)


def credential_shape(data: bytes) -> bool:
    # Locate prefixes with byte search before applying the boundary/length
    # regex. Scanning multi-GB native libraries with a leading lookbehind is
    # needlessly expensive; the accepted credential shapes remain identical.
    for prefix, pattern in (
        (b"gho_", CREDENTIAL_SHAPES[0]), (b"ghp_", CREDENTIAL_SHAPES[0]),
        (b"ghs_", CREDENTIAL_SHAPES[0]), (b"ghu_", CREDENTIAL_SHAPES[0]),
        (b"sk-", CREDENTIAL_SHAPES[1]), (b"hf_", CREDENTIAL_SHAPES[2]),
    ):
        start = 0
        expression = re.compile(pattern)
        while (start := data.find(prefix, start)) >= 0:
            if expression.match(data, start):
                return True
            start += len(prefix)
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    root = args.bundle.resolve()
    hits, links, artifacts, binaries, credentials = [], [], [], [], []
    keywords = {word.decode(): [] for word in KEYWORDS}
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            target = os.readlink(path)
            if os.path.isabs(target) or not path.resolve().is_relative_to(root):
                links.append({"file": relative, "target": target})
            continue
        if not path.is_file():
            continue
        if any(part in {"__pycache__", ".venv", ".git", ".pytest_cache", "tests", "test-artifacts", "chats"} for part in path.relative_to(root).parts) or path.suffix == ".pyc" or path.name in {".env", "direct_url.json", "pyvenv.cfg"}:
            artifacts.append(relative)
        data = path.read_bytes()
        if credential_shape(data):
            credentials.append(relative)
        is_macho = data[:4] in prepare.MAGICS
        if is_macho:
            binaries.append(path)
        patterns = [word.decode() for word in FORBIDDEN if word in data or word in relative.encode()]
        if patterns:
            kind = "Mach-O" if is_macho else "pyvenv.cfg" if path.name == "pyvenv.cfg" else "direct_url.json" if path.name == "direct_url.json" else path.suffix if path.suffix in {".pyc", ".pth"} else "shebang" if data.startswith(b"#!") else "other"
            hits.append({"file": relative, "kind": kind, "patterns": patterns})
        lower = data.lower()
        for word in KEYWORDS:
            count = lower.count(word)
            if count:
                keywords[word.decode()].append({"file": relative, "count": count})
    def check_binary(path: Path) -> dict:
        commands = prepare.load_commands(path)
        # Record otool -L as well as actual LC_* records, distinguishing IDs.
        loads = subprocess.check_output(["otool", "-L", str(path)], text=True)
        return {"file": str(path.relative_to(root)), "otool_L": loads.replace(str(root), "<bundle>"), "commands": commands,
                "external": [(kind, value) for kind, value in commands if not value.startswith(prepare.ALLOWED)]}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        loads = list(pool.map(check_binary, binaries))
    external = [value for value in loads if value["external"]]
    result = {"bundle": str(root), "forbidden_hits": hits, "unsafe_symlinks": links, "development_artifacts": artifacts, "credential_shaped_files": credentials,
              "macho_count": len(binaries), "macho_load_commands": loads, "external_load_commands": external, "keyword_review_inventory": keywords}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"forbidden_files": len(hits), "unsafe_symlinks": len(links), "development_artifacts": len(artifacts), "credential_shaped_files": len(credentials), "external_macho_commands": len(external), "Mach-O": len(binaries), "keyword_files": {k: len(v) for k, v in keywords.items()}}, indent=2))
    if not args.baseline:
        subprocess.run([os.sys.executable, str(Path(__file__).with_name("check-bundle-secret.py")), str(root)], check=True)
        if hits or links or artifacts or external or credentials:
            raise SystemExit("Bundle audit failed; inspect the report (file names only).")


if __name__ == "__main__":
    main()
