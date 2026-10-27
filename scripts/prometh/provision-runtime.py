#!/usr/bin/env python3
"""Install Prometh's Linux/macOS runtime pieces into gitignored virtualenvs.

SearXNG is installed from the pinned git commit, never from the PyPI
package named searxng. Reader packages come from the hash lock. Nothing
under PromethRuntime/**/.venv or reader/vendor is committed.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEARXNG_REF = "1412926f5c80ffabc90719450578eb98fda9e161"
SEARXNG_URL = "https://github.com/searxng/searxng"


def run(command: list[str], **kwargs: object) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.check_call(command, **kwargs)


def venv_python(path: Path) -> Path:
    python = path / "bin" / "python3"
    if python.exists():
        probe = subprocess.run(
            [str(python), "-m", "pip", "--version"],
            capture_output=True,
            text=True,
        )
        if probe.returncode != 0:
            shutil.rmtree(path)
    if not (path / "bin" / "python3").exists():
        run([sys.executable, "-m", "venv", str(path)])
    return path / "bin" / "python3"


def provision_reader() -> None:
    directory = ROOT / "PromethRuntime" / "reader"
    python = venv_python(directory / ".venv")
    run([str(python), "-m", "pip", "install", "--upgrade", "pip"])
    run([
        str(python), "-m", "pip", "install", "--require-hashes",
        "-r", str(directory / "requirements.lock"),
    ])


def provision_searxng() -> None:
    directory = ROOT / "PromethRuntime" / "searxng"
    python = venv_python(directory / ".venv")
    run([str(python), "-m", "pip", "install", "--upgrade", "pip"])
    run([
        str(python), "-m", "pip", "install", "--require-hashes",
        "-r", str(directory / "requirements.lock"),
    ])
    checkout = Path(os.environ.get("PROMETH_SEARXNG_SRC", "/tmp/prometh-searxng-src"))
    if not (checkout / ".git").exists():
        run(["git", "init", "-q", str(checkout)])
    run(["git", "-C", str(checkout), "config", "core.autocrlf", "false"])
    run(["git", "-C", str(checkout), "fetch", "-q", "--depth", "1", SEARXNG_URL, SEARXNG_REF])
    run(["git", "-C", str(checkout), "checkout", "-q", "FETCH_HEAD"])
    env = os.environ.copy()
    env.pop("GITHUB_REPOSITORY", None)
    env.pop("GITHUB_REF_NAME", None)
    subprocess.check_call(
        [str(python), "-m", "searx.version", "freeze"],
        cwd=checkout,
        env=env,
    )
    run([
        str(python), "-m", "pip", "install",
        "--use-pep517", "--no-build-isolation", "--no-deps", str(checkout),
    ])


def provision_composio() -> None:
    directory = ROOT / "PromethRuntime" / "composio_mcp"
    python = venv_python(directory / ".venv")
    run([str(python), "-m", "pip", "install", "--upgrade", "pip"])
    run([
        str(python), "-m", "pip", "install", "--require-hashes",
        "-r", str(directory / "requirements.lock"),
    ])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reader", action="store_true")
    parser.add_argument("--searxng", action="store_true")
    parser.add_argument("--composio", action="store_true")
    args = parser.parse_args()
    if not args.reader and not args.searxng and not args.composio:
        args.reader = args.searxng = args.composio = True
    if args.reader:
        provision_reader()
    if args.searxng:
        provision_searxng()
    if args.composio:
        provision_composio()
    print("provisioned")


if __name__ == "__main__":
    main()
