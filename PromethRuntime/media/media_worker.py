"""Video jobs for Prometh. FastVideo is checked out beside this file, not vendored."""

from __future__ import annotations

import json
import os
import queue
import signal
import subprocess
import sys
import threading
from pathlib import Path

FASTVIDEO_COMMIT = "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f"
MODEL = "FastVideo/FastMetal-1.3B-QAD"
REVISION = "2dac0154b217adabf8895d6cde7d6d93e68b7bec"
WIDTH = 832
HEIGHT = 480
SECONDS = 5.0


def job_plan(prompt: str, seconds: float = SECONDS) -> dict:
    return {
        "model": MODEL,
        "revision": REVISION,
        "fastvideo": FASTVIDEO_COMMIT,
        "width": WIDTH,
        "height": HEIGHT,
        "seconds": seconds,
        "silent": True,
        "decodeBackend": "wan-vae",
        "prompt": prompt,
    }


def trim_duration(start: float, end: float) -> float:
    if start < 0 or end <= start:
        raise ValueError("trim range is empty")
    return round(end - start, 3)


def standin_command(path: Path, seconds: float) -> list[str]:
    return [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"color=c=black:s={WIDTH}x{HEIGHT}:d={seconds}",
        "-an",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        str(path),
    ]


def trim_command(source: Path, dest: Path, start: float, end: float) -> list[str]:
    return [
        "ffmpeg",
        "-y",
        "-ss",
        f"{start:.3f}",
        "-to",
        f"{end:.3f}",
        "-i",
        str(source),
        "-an",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        str(dest),
    ]


def poster_command(source: Path, dest: Path) -> list[str]:
    return ["ffmpeg", "-y", "-i", str(source), "-frames:v", "1", str(dest)]


def fastvideo_checkout() -> Path | None:
    override = os.environ.get("PROMETH_FASTVIDEO_SRC")
    candidates = [Path(override)] if override else []
    candidates.append(Path(__file__).resolve().parent / "fastvideo")
    for root in candidates:
        script = root / "examples/inference/basic/mlx_wan_prompt_to_video.py"
        if script.is_file():
            return root
    return None


def fastmetal_root() -> Path | None:
    override = os.environ.get("PROMETH_FASTMETAL_ROOT")
    candidates = [Path(override)] if override else []
    candidates.append(
        Path.home()
        / "Library/Application Support/Prometh/Models/FastVideo--FastMetal-1.3B-QAD--2dac0154b217"
    )
    for root in candidates:
        if (root / "mlx_dit.safetensors").is_file() and (root / "vae").is_dir():
            return root
    return None


def fastvideo_python(checkout: Path) -> str:
    override = os.environ.get("PROMETH_MEDIA_PYTHON")
    if override:
        return override
    venv = checkout.parent / ".venv" / "bin" / "python3"
    if venv.is_file():
        return str(venv)
    return sys.executable


def fastvideo_command(python: str, script: Path, model: Path, prompt: str, output: Path) -> list[str]:
    return [
        python,
        str(script),
        "--model-root",
        str(model),
        "--mlx-checkpoint",
        str(model),
        "--prompt",
        prompt,
        "--output-path",
        str(output),
        "--height",
        str(HEIGHT),
        "--width",
        str(WIDTH),
        "--num-frames",
        "81",
        "--fps",
        "16",
        "--decode-backend",
        "wan-vae",
        "--seed",
        "1024",
    ]


class Worker:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._process: subprocess.Popen | None = None
        self._cancelled = False

    def cancel(self) -> None:
        with self._lock:
            self._cancelled = True
            process = self._process
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def _spawn(
        self,
        command: list[str],
        cwd: Path | None = None,
        env: dict | None = None,
        log: Path | None = None,
    ) -> int:
        handle = open(log, "ab") if log is not None else subprocess.DEVNULL
        with self._lock:
            if self._cancelled:
                if log is not None:
                    handle.close()
                return -1
            self._process = subprocess.Popen(
                command,
                cwd=str(cwd) if cwd else None,
                env=env,
                stdout=handle,
                stderr=subprocess.STDOUT if log is not None else subprocess.DEVNULL,
                start_new_session=True,
            )
            process = self._process
        code = process.wait()
        if log is not None:
            handle.close()
        with self._lock:
            self._process = None
        return code

    def generate(self, prompt: str, output: Path, poster: Path) -> dict:
        plan = job_plan(prompt)
        output.parent.mkdir(parents=True, exist_ok=True)
        if os.environ.get("PROMETH_MEDIA_MOCK") == "1":
            if self._spawn(standin_command(output, plan["seconds"])) != 0 or self._cancelled:
                output.unlink(missing_ok=True)
                raise RuntimeError("cancelled" if self._cancelled else "stand-in failed")
            if self._spawn(poster_command(output, poster)) != 0:
                raise RuntimeError("poster failed")
            plan["output"] = str(output)
            plan["poster"] = str(poster)
            plan["mock"] = True
            return plan
        checkout = fastvideo_checkout()
        model = fastmetal_root()
        if checkout is None or model is None:
            raise RuntimeError("Video is not ready yet.")
        output = output.expanduser().resolve()
        poster = poster.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        script = checkout / "examples/inference/basic/mlx_wan_prompt_to_video.py"
        env = os.environ.copy()
        env["PYTHONPATH"] = str(checkout) + os.pathsep + env.get("PYTHONPATH", "")
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HUB_OFFLINE"] = "1"
        log = output.with_suffix(".log")
        code = self._spawn(
            fastvideo_command(fastvideo_python(checkout), script, model, prompt, output),
            cwd=checkout,
            env=env,
            log=log,
        )
        if code != 0 or self._cancelled or not output.is_file():
            output.unlink(missing_ok=True)
            raise RuntimeError("cancelled" if self._cancelled else "video generation failed")
        if self._spawn(poster_command(output, poster)) != 0:
            raise RuntimeError("poster failed")
        plan["output"] = str(output)
        plan["poster"] = str(poster)
        plan["mock"] = False
        return plan

    def trim(self, source: Path, dest: Path, start: float, end: float) -> dict:
        duration = trim_duration(start, end)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if self._spawn(trim_command(source, dest, start, end)) != 0:
            raise RuntimeError("trim failed")
        return {"start": start, "end": end, "duration": duration, "output": str(dest), "version": 2}


def main() -> None:
    worker = Worker()

    def stop(_signum: int, _frame: object) -> None:
        worker.cancel()
        os._exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    inbox: queue.Queue = queue.Queue()

    def read() -> None:
        for line in sys.stdin:
            if not line.strip():
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                inbox.put({"op": "invalid"})
                continue
            if message.get("op") == "cancel":
                worker.cancel()
            inbox.put(message)
        inbox.put({"op": "eof"})

    threading.Thread(target=read, name="media-reader", daemon=True).start()
    while True:
        message = inbox.get()
        op = message.get("op")
        if op == "cancel":
            emit({"ok": True, "cancelled": True})
            return
        if op == "eof":
            return
        try:
            if op == "generate":
                emit({"event": "progress", "fraction": 0.1})
                plan = worker.generate(
                    message.get("prompt") or "",
                    Path(message["output"]),
                    Path(message["poster"]),
                )
                emit({"ok": True, "event": "done", "plan": plan})
            elif op == "trim":
                result = worker.trim(
                    Path(message["source"]),
                    Path(message["output"]),
                    float(message["start"]),
                    float(message["end"]),
                )
                emit({"ok": True, "trim": result})
            else:
                emit({"ok": False, "error": "unknown op"})
        except Exception as error:
            emit({"ok": False, "error": str(error)})


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
