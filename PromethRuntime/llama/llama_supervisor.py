"""Start llama-server for Evil Mode and stop it with the app.

The GGUF is not downloaded here. A missing binary fails the launch; it does
not fetch weights.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import threading
import time
from pathlib import Path

LLAMA_CPP_REF = "b11669"
HOST = "127.0.0.1"
ALIAS = "evil"
CTX_SIZE = "8192"
IDLE_SECONDS = 600
MAX_STARTS = 3
GIBIBYTE = 1024**3


def must_unload_other(ram_bytes: int) -> bool:
    """Gemma and Qwen must not both stay resident at 16 GiB or below."""
    return ram_bytes <= 16 * GIBIBYTE


def build_arguments(
    *,
    executable: str,
    model: str,
    port: int,
    api_key: str,
    alias: str = ALIAS,
    host: str = HOST,
) -> list[str]:
    if host != HOST:
        raise ValueError("llama-server must bind 127.0.0.1")
    if not executable or not model or not api_key:
        raise ValueError("llama-server needs an executable, a model, and an api key")
    return [
        executable,
        "--host",
        HOST,
        "--port",
        str(port),
        "--model",
        model,
        "--alias",
        alias,
        "--ctx-size",
        CTX_SIZE,
        "--parallel",
        "1",
        "--jinja",
        "--reasoning",
        "off",
        "--api-key",
        api_key,
    ]


def reserve_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((HOST, 0))
        return int(sock.getsockname()[1])


def pid_alive(pid: int) -> bool:
    if pid <= 1:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


class Supervisor:
    def __init__(
        self,
        *,
        executable: str,
        model: str,
        api_key: str,
        parent_pid: int,
        support: Path,
        port: int | None = None,
        idle_seconds: float = IDLE_SECONDS,
        popen=subprocess.Popen,
        clock=time.monotonic,
    ) -> None:
        self.executable = executable
        self.model = model
        self.api_key = api_key
        self.parent_pid = parent_pid
        self.support = support
        self.port = port if port is not None else reserve_port()
        self.idle_seconds = idle_seconds
        self.popen = popen
        self.clock = clock
        self.process: subprocess.Popen | None = None
        self.started_at = clock()
        self.last_used = self.started_at
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def arguments(self) -> list[str]:
        return build_arguments(
            executable=self.executable,
            model=self.model,
            port=self.port,
            api_key=self.api_key,
        )

    def touch(self) -> None:
        self.last_used = self.clock()

    def idle_due(self) -> bool:
        return self.clock() - self.last_used >= self.idle_seconds

    def start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.touch()
            return
        self.support.mkdir(parents=True, exist_ok=True)
        last_error = "llama-server exited"
        for _ in range(MAX_STARTS):
            try:
                self.process = self.popen(
                    self.arguments(),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except OSError as error:
                last_error = str(error)
                time.sleep(0.2)
                continue
            time.sleep(0.3)
            if self.process.poll() is None:
                self.touch()
                self._write_endpoint()
                self._watch()
                return
            last_error = f"exit {self.process.returncode}"
            time.sleep(0.2)
        raise RuntimeError(last_error)

    def stop(self) -> None:
        self._stop.set()
        process = self.process
        self.process = None
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()

    def _write_endpoint(self) -> None:
        path = self.support / "endpoint.json"
        payload = {
            "host": HOST,
            "port": self.port,
            "alias": ALIAS,
            "apiKey": self.api_key,
        }
        path.write_text(json.dumps(payload), encoding="utf-8")
        os.chmod(path, 0o600)

    def _watch(self) -> None:
        if self._thread is not None:
            return

        def run() -> None:
            while not self._stop.is_set():
                if not pid_alive(self.parent_pid) or self.idle_due():
                    self.stop()
                    return
                process = self.process
                if process is not None and process.poll() is not None:
                    return
                self._stop.wait(0.2)

        self._thread = threading.Thread(target=run, name="llama-parent-watch", daemon=True)
        self._thread.start()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent", type=int, required=True)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--support", required=True)
    parser.add_argument("--port", type=int)
    args = parser.parse_args()
    idle = float(os.environ.get("PROMETH_LLAMA_IDLE_SECONDS", str(IDLE_SECONDS)))
    supervisor = Supervisor(
        executable=args.executable,
        model=args.model,
        api_key=args.api_key,
        parent_pid=args.parent,
        support=Path(args.support),
        port=args.port,
        idle_seconds=idle,
    )
    supervisor.start()
    print(f"LISTENING {supervisor.port}", flush=True)
    while supervisor.process is not None and supervisor.process.poll() is None and not supervisor._stop.is_set():
        time.sleep(0.2)


if __name__ == "__main__":
    main()
