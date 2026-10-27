"""Clip plan, stand-in container, trim, poster, and cancel. No FastVideo download."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import media_worker

ROOT = Path(__file__).resolve().parents[2]


def test_fastvideo_command_uses_the_pinned_decoder() -> None:
    command = media_worker.fastvideo_command(
        "python3",
        Path("mlx_wan_prompt_to_video.py"),
        Path("/models/FastMetal"),
        "waves at sunset",
        Path("/tmp/waves.mp4"),
    )
    assert command[command.index("--decode-backend") + 1] == "wan-vae"
    assert command[command.index("--width") + 1] == "832"
    assert command[command.index("--height") + 1] == "480"
    assert command[command.index("--num-frames") + 1] == "81"
    assert "--mlx-checkpoint" in command


def test_plan_and_trim_math() -> None:
    plan = media_worker.job_plan("waves at sunset")
    assert plan["fastvideo"] == "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f"
    assert plan["model"] == "FastVideo/FastMetal-1.3B-QAD"
    assert plan["revision"] == "2dac0154b217adabf8895d6cde7d6d93e68b7bec"
    assert plan["width"] == 832 and plan["height"] == 480
    assert plan["seconds"] == 5.0 and plan["silent"] is True
    assert abs(media_worker.trim_duration(1.0, 3.0) - 2.0) < 0.1


def test_standin_trim_and_poster(tmp: Path) -> None:
    os.environ["PROMETH_MEDIA_MOCK"] = "1"
    worker = media_worker.Worker()
    clip = tmp / "clip.mp4"
    poster = tmp / "poster.png"
    plan = worker.generate("waves at sunset", clip, poster)
    assert plan["mock"] is True
    assert clip.stat().st_size > 1000
    assert poster.stat().st_size > 24
    info = probe(clip)
    assert info["width"] == 832 and info["height"] == 480
    assert abs(info["duration"] - 5.0) < 0.2
    trimmed = tmp / "clip-v2.mp4"
    result = worker.trim(clip, trimmed, 1.0, 3.0)
    assert abs(result["duration"] - 2.0) < 0.1
    assert clip.exists() and trimmed.exists()
    trimmed_info = probe(trimmed)
    assert abs(trimmed_info["duration"] - 2.0) <= 0.1
    assert trimmed_info["width"] == 832


def test_cancel_kills_the_child(tmp: Path) -> None:
    script = ROOT / "PromethRuntime" / "media" / "media_worker.py"
    env = os.environ.copy()
    env["PROMETH_MEDIA_MOCK"] = "1"
    # Replace ffmpeg with a sleeper by putting a stub first on PATH.
    bindir = tmp / "bin"
    bindir.mkdir(parents=True)
    pidfile = tmp / "child.pid"
    stub = bindir / "ffmpeg"
    stub.write_text(
        "#!/bin/sh\necho $$ > \"$PROMETH_SLEEP_PID\"\nexec sleep 30\n",
        encoding="utf-8",
    )
    stub.chmod(0o755)
    env["PATH"] = f"{bindir}:{env.get('PATH', '')}"
    env["PROMETH_SLEEP_PID"] = str(pidfile)
    proc = subprocess.Popen(
        [sys.executable, str(script)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=env,
        text=True,
    )
    assert proc.stdin and proc.stdout
    proc.stdin.write(json.dumps({
        "op": "generate",
        "prompt": "waves",
        "output": str(tmp / "slow.mp4"),
        "poster": str(tmp / "slow.png"),
    }) + "\n")
    proc.stdin.flush()
    deadline = time.time() + 5
    while not pidfile.exists() and time.time() < deadline:
        time.sleep(0.05)
    time.sleep(0.2)
    proc.stdin.write(json.dumps({"op": "cancel"}) + "\n")
    proc.stdin.flush()
    stdout, _ = proc.communicate(timeout=5)
    assert proc.returncode == 0
    assert "\"cancelled\": true" in stdout
    child = int(pidfile.read_text(encoding="utf-8").strip())
    deadline = time.time() + 2
    while time.time() < deadline:
        try:
            os.kill(child, 0)
        except OSError:
            return
        time.sleep(0.05)
    raise AssertionError("cancelled worker left a child running")


def probe(path: Path) -> dict:
    raw = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(path),
        ],
        text=True,
    )
    parsed = json.loads(raw)
    stream = parsed["streams"][0]
    return {
        "width": stream["width"],
        "height": stream["height"],
        "duration": float(parsed["format"]["duration"]),
    }


def main() -> None:
    tmp = Path("/tmp/prometh-media-test")
    subprocess.run(["rm", "-rf", str(tmp)], check=True)
    tmp.mkdir()
    test_fastvideo_command_uses_the_pinned_decoder()
    test_plan_and_trim_math()
    test_standin_trim_and_poster(tmp / "standin")
    test_cancel_kills_the_child(tmp / "cancel")
    print(json.dumps({"passed": True, "tests": 4, "fastvideo": media_worker.FASTVIDEO_COMMIT}))


if __name__ == "__main__":
    main()
