#!/usr/bin/env python3
"""Start unmodified SearXNG and exit if the parent Prometh process disappears."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import threading
import time


def watch(parent_pid: int, child: subprocess.Popen[bytes]) -> None:
    while child.poll() is None:
        try:
            os.kill(parent_pid, 0)
        except OSError:
            child.send_signal(signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
            os._exit(0)
        time.sleep(1)


def main() -> None:
    args = sys.argv[1:]
    parent = None
    if "--parent" in args:
        index = args.index("--parent")
        parent = int(args[index + 1])
        del args[index : index + 2]
    if args[:1] == ["--"]:
        args = args[1:]
    if not args:
        raise SystemExit("usage: launch.py --parent PID -- -m granian ...")
    child = subprocess.Popen([sys.executable, *args])
    if parent is not None:
        threading.Thread(target=watch, args=(parent, child), daemon=True).start()
    raise SystemExit(child.wait())


if __name__ == "__main__":
    main()
