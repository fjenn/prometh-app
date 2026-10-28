#!/usr/bin/env python3
"""Compare the local connector credential to bundle bytes; never disclose it."""
import os
import sys
from pathlib import Path


def main() -> None:
    values = []
    config = Path.home() / ".config/prometh/composio.env"
    if config.is_file():
        for line in config.read_text().splitlines():
            name, separator, value = line.strip().partition("=")
            if separator and name.removeprefix("export ").strip() == "COMPOSIO_API_KEY":
                value = value.strip().strip("\"'")
                if value:
                    values.append(value.encode())
    found = False
    root = Path(sys.argv[1])
    for directory, _, names in os.walk(root):
        for name in names:
            path = Path(directory) / name
            if path.is_symlink():
                continue
            if values:
                data = path.read_bytes()
                if any(value in data for value in values):
                    found = True
    print("found" if found else "not found")
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
