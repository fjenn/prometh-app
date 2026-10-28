#!/usr/bin/env python3
"""Prepare the shipped bundle: remove build artifacts and relocate wheel dylibs.

Run as the final Copy PromethRuntime step, before signing. Source targets and
framework build products are left intact. Diagnostic build prefixes in prebuilt
wheels are redacted without changing binary sizes; load commands are handled
with install_name_tool first, never by byte patching a dependency.
"""
from __future__ import annotations

import ast
import io
import tokenize
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

MAGICS = {bytes.fromhex(x) for x in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
ALLOWED = ("/System/", "/usr/lib/", "@rpath", "@loader_path", "@executable_path")


def macho(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in MAGICS


def load_commands(path: Path) -> list[tuple[str, str]]:
    output = subprocess.check_output(["otool", "-l", str(path)], text=True)
    commands = []
    kind = ""
    for line in output.splitlines():
        fields = line.strip().split()
        if fields[:1] == ["cmd"]:
            kind = fields[1]
        elif fields[:1] in (["name"], ["path"]) and kind in {
            "LC_RPATH", "LC_ID_DYLIB", "LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB", "LC_LOAD_UPWARD_DYLIB"
        }:
            commands.append((kind, line.strip().split(" ", 1)[1].rsplit(" (offset", 1)[0]))
    return commands


def prepare_binary(path: Path) -> None:
    # Debug/symbol information is not part of the distributed product.
    stripped = subprocess.run(["strip", "-S", str(path)], capture_output=True)
    if stripped.returncode and not (
        path.name == "github-mcp-server"
        and b"symbols referenced by indirect symbol table" in stripped.stderr
    ):
        raise RuntimeError(f"strip failed: {path}: {stripped.stderr.decode(errors='replace')}")
    commands = load_commands(path)
    for kind, value in commands:
        if value.startswith(ALLOWED):
            continue
        if kind == "LC_RPATH":
            subprocess.run(["install_name_tool", "-delete_rpath", value, str(path)], check=True, capture_output=True)
        elif kind == "LC_ID_DYLIB":
            subprocess.run(["install_name_tool", "-id", "@rpath/" + path.name, str(path)], check=True, capture_output=True)
        else:
            # Wheel tools often leave a build-machine ID but should already
            # rewrite loads to adjacent vendored libraries. Refuse real loads.
            raise RuntimeError(f"unrelocated {kind}: {path}: {value}")
    data = path.read_bytes()
    # Upstream __FILE__, compiler search paths and assertion diagnostics only.
    # Every load command has been checked above; the final audit checks again.
    repository = str(Path(__file__).resolve().parents[2]).encode()
    data = data.replace(repository, b"/src/prometh"[:len(repository)].ljust(len(repository), b"_"))
    data = data.replace(b"/Users/", b"/build/").replace(b"/opt/homebrew", b"/build/tools_")
    if b"armando" in data:
        raise RuntimeError(f"personal name remains in executable: {path}")
    path.write_bytes(data)


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    assert root.suffix == ".app" and root.is_dir()
    removed = 0
    for path in sorted(root.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.is_symlink():
            if not path.resolve().is_relative_to(root) or os.path.isabs(os.readlink(path)):
                raise RuntimeError(f"escaping symlink: {path}")
            continue
        if path.is_dir() and path.name in {"__pycache__", ".pytest_cache", ".git", ".venv", "tests", "test", "test-artifacts", ".hash"}:
            shutil.rmtree(path); removed += 1
        elif path.is_file() and (path.suffix == ".pyc" or path.name in {"direct_url.json", "pyvenv.cfg", ".env", ".DS_Store", ".mlx-vlm-server-build.json"} or path.name.startswith("test_") and path.suffix == ".py" and path.name != "test_operators.py"):
            path.unlink(); removed += 1
    # Training job runners and source-distribution builders are not inference
    # dependencies. Portable verification must run image/video after pruning.
    for packages in root.glob("Contents/**/site-packages"):
        for relative in ("ray", "setuptools/command/sdist.py", "fastvideo/benchmarks", "transformers/testing_utils.py"):
            path = packages / relative
            if path.is_dir():
                shutil.rmtree(path); removed += 1
            elif path.is_file():
                path.unlink(); removed += 1
        examples = packages / "examples"
        if examples.is_dir():
            for path in list(examples.iterdir()):
                if path.name != "inference":
                    if path.is_dir(): shutil.rmtree(path)
                    else: path.unlink()
    # Keep executable Python unchanged; omit machine-specific documentation
    # and comments in upstream sources using AST/token locations.
    words = ("/Users/", "/opt/homebrew", "armando", ".venv")
    for path in (p for p in root.rglob("*") if p.suffix in {".py", ".pyi"}):
        if path.is_symlink(): continue
        raw = path.read_bytes()
        if not any(word.encode() in raw for word in words): continue
        with tokenize.open(path) as stream:
            text = stream.read()
            encoding = stream.encoding
        lines = text.splitlines(keepends=True)
        tree = ast.parse(text)
        for node in ast.walk(tree):
            body = getattr(node, "body", None)
            if isinstance(body, list) and body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
                doc = body[0]
                if any(word in doc.value.value for word in words):
                    indent = " " * doc.col_offset
                    lines[doc.lineno - 1] = indent + '"""Documentation omitted from runtime distribution."""\n'
                    for i in range(doc.lineno, doc.end_lineno): lines[i] = "\n"
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.COMMENT and any(word in token.string for word in words):
                line, column = token.start
                lines[line - 1] = lines[line - 1][:column] + "\n"
        cleaned = "".join(lines)
        # platformdirs documents a prefix inside a re.VERBOSE regex; this is
        # a regex comment, rather than a Python comment token.
        cleaned = cleaned.replace("# $HOMEBREW_PREFIX, such as /opt/homebrew or /usr/local", "# Homebrew prefix")
        ast.parse(cleaned)
        path.write_text(cleaned, encoding=encoding)
    python = root / "Contents/Frameworks/NativServerKit.framework/Resources/mlx-vlm-server/python"
    for relative in ("lib/python3.12/venv", "lib/python3.12/site-packages/torch/share/cmake"):
        shutil.rmtree(python / relative, ignore_errors=True)
    for packages in root.glob("Contents/**/site-packages"):
        shutil.rmtree(packages / "torch/share/cmake", ignore_errors=True)
        (packages / "pandas/pyproject.toml").unlink(missing_ok=True)
        for license in packages.glob("torch-*.dist-info/licenses/LICENSE"):
            # Preserve the complete notices; make upstream source references
            # repository-relative instead of the wheel builder's directory.
            license.write_text(license.read_text().replace("/Users/runner/work/pytorch/pytorch/", "pytorch/"))
    metadata = root / "Contents/Resources/HeyNativ.mlmodelc/coremldata.bin"
    if metadata.is_file():
        # CoreML training metadata contains its publisher's checkpoint path.
        # This same-length prefix change preserves the serialized model layout.
        metadata.write_bytes(metadata.read_bytes().replace(b"/Users/", b"/build/"))
    # These are provisioning/development entrypoints, never feature launchers.
    for path in (python / "bin").iterdir():
        if path.name not in {"python", "python3", "python3.12"}:
            path.unlink(); removed += 1
    # Runtime source documentation can contain example machine paths. Remove
    # only documentation lines, never substitute functional Python source.
    for path in root.rglob("*"):
        if path.is_symlink() or not path.is_file() or path.suffix not in {".md", ".txt", ".json"} and path.name != "METADATA":
            continue
        try:
            text = path.read_text()
        except (UnicodeError, OSError):
            continue
        lines = text.splitlines(keepends=True)
        cleaned = "".join(line for line in lines if not any(word in line for word in ("/Users/", "/opt/homebrew", "armando", ".venv")))
        if cleaned != text:
            # Structured JSON must remain valid; provenance SBOMs can simply be
            # omitted (wheel licenses/METADATA are retained).
            if path.suffix == ".json":
                if "sboms" in path.parts:
                    path.unlink(); removed += 1
                else:
                    raise RuntimeError(f"machine path in structured runtime data: {path}")
            else:
                path.write_text(cleaned)
    binaries = [p for p in root.rglob("*") if macho(p)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        list(executor.map(prepare_binary, binaries))
    print(f"Prepared {len(binaries)} Mach-O files; removed {removed} development artifacts.")


if __name__ == "__main__":
    main()
