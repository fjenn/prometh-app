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
# Best-first video weights. Prefer the largest complete catalog folder.
# Tuple: (HF repo, revision, on-disk folder stem, catalog id, pipeline).
# pipeline: "wan21" → mlx_wan_prompt_to_video.py; "wan22" → mlx_wan22_generate.py.
VIDEO_CANDIDATES = [
    ("FastVideo/FastMetal-14B-QAD", "fbc50323c677ee29a62d94204a62c996e505ac89",
     "FastVideo--FastMetal-14B-QAD--fbc50323c677", "video-14b", "wan21"),
    ("FastVideo/FastMetal-5B-QAD", "5e4819ec9c8dd062443cf015bd9022c700eca458",
     "FastVideo--FastMetal-5B-QAD--5e4819ec9c8d", "video-5b", "wan22"),
    ("FastVideo/FastMetal-1.3B-QAD", "2dac0154b217adabf8895d6cde7d6d93e68b7bec",
     "FastVideo--FastMetal-1.3B-QAD--2dac0154b217", "video", "wan21"),
]
MODEL = VIDEO_CANDIDATES[-1][0]
REVISION = VIDEO_CANDIDATES[-1][1]
# Wan2.1 (1.3B / 14B) defaults used by Prometh.
WAN21_WIDTH = 832
WAN21_HEIGHT = 480
WAN21_FRAMES = 81
WAN21_FPS = 16
# Wan2.2 TI2V 5B: README quickstart uses script defaults + --fast.
# Script defaults are 448x832 / 121 frames / 24 fps (native training res is 704x1280).
WAN22_WIDTH = 832
WAN22_HEIGHT = 448
WAN22_FRAMES = 121
WAN22_FPS = 24
SECONDS = 5.0


def _video_ready(root: Path) -> bool:
    """True only when DiT, VAE weights, and text-encoder shards look complete."""
    dit = root / "mlx_dit.safetensors"
    if not dit.is_file() or dit.stat().st_size < 1_000_000:
        return False
    vae_weight = root / "vae" / "diffusion_pytorch_model.safetensors"
    if not vae_weight.is_file() or vae_weight.stat().st_size < 1_000_000:
        # Wan2.1 1.3B/14B may ship VAE under a nested name; accept any large safetensor.
        vae_dir = root / "vae"
        if not vae_dir.is_dir():
            return False
        vae_ok = any(
            p.is_file() and p.stat().st_size >= 1_000_000
            for p in vae_dir.rglob("*.safetensors")
        )
        if not vae_ok:
            return False
    te = root / "text_encoder"
    if not te.is_dir():
        return False
    te_weights = [
        p for p in te.rglob("*.safetensors")
        if p.is_file() and p.stat().st_size >= 1_000_000 and ".partial" not in p.name
    ]
    if not te_weights:
        return False
    # Sharded UMT5 (5B) needs all three parts; single-file encoders (1.3B) need one.
    index = te / "model.safetensors.index.json"
    if index.is_file():
        try:
            import json as _json
            meta = _json.loads(index.read_text())
            expected = {
                te / name
                for name in set((meta.get("weight_map") or {}).values())
            }
            if expected and not all(p.is_file() and p.stat().st_size >= 1_000_000 for p in expected):
                return False
        except Exception:
            return False
    return True


def _selected_video() -> tuple[str, str, str, str]:
    override = os.environ.get("PROMETH_VIDEO_MODEL_ID", "").strip()
    models = Path.home() / "Library/Application Support/Prometh/Models"
    # Explicit override wins for plan/tests even before weights finish downloading.
    if override:
        for repo, revision, folder, catalog_id, pipeline in VIDEO_CANDIDATES:
            aliases = {repo, folder, revision, catalog_id}
            if override in aliases:
                return repo, revision, folder, pipeline
    for repo, revision, folder, catalog_id, pipeline in VIDEO_CANDIDATES:
        root = models / folder
        if _video_ready(root):
            return repo, revision, folder, pipeline
    fallback = VIDEO_CANDIDATES[-1]
    return fallback[0], fallback[1], fallback[2], fallback[4]


def _geometry(pipeline: str) -> tuple[int, int, int, int, str]:
    if pipeline == "wan22":
        return WAN22_WIDTH, WAN22_HEIGHT, WAN22_FRAMES, WAN22_FPS, "taehv"
    return WAN21_WIDTH, WAN21_HEIGHT, WAN21_FRAMES, WAN21_FPS, "wan-vae"


def job_plan(prompt: str, seconds: float = SECONDS) -> dict:
    repo, revision, _, pipeline = _selected_video()
    width, height, frames, fps, decode = _geometry(pipeline)
    return {
        "model": repo,
        "revision": revision,
        "fastvideo": FASTVIDEO_COMMIT,
        "pipeline": pipeline,
        "width": width,
        "height": height,
        "frames": frames,
        "fps": fps,
        "seconds": seconds,
        "silent": True,
        "decodeBackend": decode,
        "prompt": prompt,
    }


def trim_duration(start: float, end: float) -> float:
    if start < 0 or end <= start:
        raise ValueError("trim range is empty")
    return round(end - start, 3)


def standin_command(path: Path, seconds: float, width: int = WAN21_WIDTH, height: int = WAN21_HEIGHT) -> list[str]:
    return [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"color=c=black:s={width}x{height}:d={seconds}",
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
        wan22 = root / "examples/inference/basic/mlx_wan22_generate.py"
        if script.is_file() and wan22.is_file():
            return root
        if script.is_file():
            return root
    return None


def fastmetal_root() -> Path | None:
    override = os.environ.get("PROMETH_FASTMETAL_ROOT")
    if override:
        root = Path(override)
        if _video_ready(root):
            return root
    _, _, folder, _ = _selected_video()
    root = Path.home() / "Library/Application Support/Prometh/Models" / folder
    if _video_ready(root):
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
    """Wan2.1 FastMetal 1.3B / 14B entrypoint."""
    return [
        python,
        str(Path(__file__).with_name("bounded_video.py")),
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
        str(WAN21_HEIGHT),
        "--width",
        str(WAN21_WIDTH),
        "--num-frames",
        str(WAN21_FRAMES),
        "--fps",
        str(WAN21_FPS),
        "--decode-backend",
        "wan-vae",
        "--seed",
        "1024",
    ]


def wan22_command(python: str, script: Path, model: Path, prompt: str, output: Path) -> list[str]:
    """Wan2.2 FastMetal-5B-QAD entrypoint (README quickstart + Prometh geometry)."""
    return [
        python,
        str(Path(__file__).with_name("bounded_video.py")),
        str(script),
        "--text-encoder-root",
        str(model),
        # Encode on Metal, then unload before DiT. The upstream CPU default
        # retains mmap weight pages in RSS alongside converted CPU tensors.
        "--text-encoder-device",
        "auto",
        "--mlx-checkpoint",
        str(model),
        "--vae-root",
        str(model / "vae"),
        "--prompt",
        prompt,
        "--output-path",
        str(output),
        "--height",
        str(WAN22_HEIGHT),
        "--width",
        str(WAN22_WIDTH),
        "--num-frames",
        str(WAN22_FRAMES),
        "--fps",
        str(WAN22_FPS),
        "--decode-backend",
        "taehv",
        "--seed",
        "1024",
        "--fast",
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
            if self._spawn(
                standin_command(output, plan["seconds"], plan["width"], plan["height"])
            ) != 0 or self._cancelled:
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
        pipeline = plan.get("pipeline") or "wan21"
        if pipeline == "wan22":
            script = checkout / "examples/inference/basic/mlx_wan22_generate.py"
            command = wan22_command(fastvideo_python(checkout), script, model, prompt, output)
        else:
            script = checkout / "examples/inference/basic/mlx_wan_prompt_to_video.py"
            command = fastvideo_command(fastvideo_python(checkout), script, model, prompt, output)
        if not script.is_file():
            raise RuntimeError("Video is not ready yet.")
        env = os.environ.copy()
        env["PYTHONPATH"] = str(checkout) + os.pathsep + env.get("PYTHONPATH", "")
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HUB_OFFLINE"] = "1"
        log = output.with_suffix(".log")
        code = self._spawn(command, cwd=checkout, env=env, log=log)
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
                return
            if op == "trim":
                result = worker.trim(
                    Path(message["source"]),
                    Path(message["output"]),
                    float(message["start"]),
                    float(message["end"]),
                )
                emit({"ok": True, "trim": result})
                return
            emit({"ok": False, "error": "unknown op"})
            return
        except Exception as error:
            # Cancel races the blocking generate/trim: the child is killed first,
            # then RuntimeError("cancelled") surfaces here before the cancel op
            # is read from the inbox.
            if str(error) == "cancelled" or worker._cancelled:
                emit({"ok": True, "cancelled": True})
            else:
                emit({"ok": False, "error": str(error)})
            return


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
