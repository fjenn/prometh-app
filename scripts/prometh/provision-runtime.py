#!/usr/bin/env python3
"""Provision relocatable Python 3.12 package targets, never virtualenvs.

A fresh clone bootstraps the same standalone interpreter as the server build.
Reader/search/connector locks include hashes. media/requirements.lock records
all versions in the validated media environment (FastVideo is pinned below).
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEARXNG_REF = "1412926f5c80ffabc90719450578eb98fda9e161"
FASTVIDEO_REF = "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f"


def run(command: list[str], **kwargs: object) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.check_call(command, **kwargs)


def bundled_python(override: str | None) -> Path:
    if override:
        candidates = [Path(override)]
    else:
        products = ROOT / "build/NativDevelopmentDerivedData/Build/Products"
        relative = "Prometh.app/Contents/Frameworks/NativServerKit.framework/Resources/mlx-vlm-server/python/bin/python3"
        candidates = [products / mode / relative for mode in ("Release", "Debug")]
        candidates.append(ROOT / "dist/mlx-vlm-server/python/bin/python3")
    for candidate in candidates:
        if candidate.is_file():
            run([str(candidate), "-c", "import sys; assert sys.version_info[:2] == (3,12)"])
            return candidate.resolve()
    if override:
        raise SystemExit("--python must point to the bundled Python 3.12")
    run([os.sys.executable, str(ROOT / "PythonDistribution/Scripts/build_mlx_vlm_server.py")])
    return bundled_python(None)


def checkout(url: str, ref: str, destination: Path) -> None:
    run(["git", "init", "-q", str(destination)])
    run(["git", "-C", str(destination), "config", "core.autocrlf", "false"])
    run(["git", "-C", str(destination), "fetch", "-q", "--depth", "1", url, ref])
    run(["git", "-C", str(destination), "checkout", "-q", "FETCH_HEAD"])


def clean_target(target: Path) -> None:
    # pip's entrypoint scripts have provisioning-machine shebangs; launches use
    # python -m or tracked scripts instead. Bytecode and provenance aren't needed.
    for path in sorted(target.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.name in {"__pycache__", ".pytest_cache"} and path.is_dir():
            shutil.rmtree(path)
        elif path.name == "direct_url.json" or path.suffix == ".pyc":
            path.unlink()
    shutil.rmtree(target / "bin", ignore_errors=True)


def provision(name: str, python: Path) -> None:
    directory = ROOT / "PromethRuntime" / name
    target = directory / "site-packages"
    with tempfile.TemporaryDirectory(prefix="prometh-provision-") as temporary:
        stage = Path(temporary) / "site-packages"
        command = [str(python), "-m", "pip", "install", "--target", str(stage), "--no-compile", "--no-deps"]
        if name != "media":
            command += ["--require-hashes"]
        run(command + ["-r", str(directory / "requirements.lock")])
        if name == "searxng":
            source = Path(temporary) / "searxng"
            checkout("https://github.com/searxng/searxng", SEARXNG_REF, source)
            environment = os.environ.copy()
            environment.update(PYTHONPATH=str(stage), PYTHONDONTWRITEBYTECODE="1", PYTHONNOUSERSITE="1")
            environment.pop("GITHUB_REPOSITORY", None)
            environment.pop("GITHUB_REF_NAME", None)
            run([str(python), "-m", "searx.version", "freeze"], cwd=source, env=environment)
            run([str(python), "-m", "pip", "install", "--target", str(stage), "--no-compile", "--no-deps", "--no-build-isolation", "--use-pep517", str(source)], env=environment)
        elif name == "media":
            source = Path(temporary) / "fastvideo"
            checkout("https://github.com/hao-ai-lab/FastVideo", FASTVIDEO_REF, source)
            # Copy the package non-editably, plus the two supported inference
            # entrypoints. Preserve the full package: lazy imports reach beyond
            # mlx_runtime. No checkout metadata, assets, docs or UI is shipped.
            shutil.copytree(source / "fastvideo", stage / "fastvideo", ignore=shutil.ignore_patterns("__pycache__", "tests", "test_*"))
            for filename in ("mlx_wan_prompt_to_video.py", "mlx_wan22_generate.py"):
                dest = stage / "examples/inference/basic" / filename
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source / "examples/inference/basic" / filename, dest)
            shutil.copy2(source / "LICENSE", stage / "fastvideo/LICENSE")
        clean_target(stage)
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(stage, target, symlinks=True)
    print(f"provisioned {name}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", help="existing standalone Python 3.12")
    for name in ("reader", "searxng", "composio", "media"):
        parser.add_argument("--" + name, action="store_true")
    args = parser.parse_args()
    python = bundled_python(args.python)
    selected = [name for name in ("reader", "searxng", "composio", "media") if getattr(args, name)]
    for name in selected or ["reader", "searxng", "composio", "media"]:
        provision("composio_mcp" if name == "composio" else name, python)


if __name__ == "__main__":
    main()
