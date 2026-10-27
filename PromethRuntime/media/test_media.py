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
    assert Path(command[1]).name == "bounded_video.py"
    assert command[2] == "mlx_wan_prompt_to_video.py"
    assert command[command.index("--decode-backend") + 1] == "wan-vae"
    assert command[command.index("--width") + 1] == "832"
    assert command[command.index("--height") + 1] == "480"
    assert command[command.index("--num-frames") + 1] == "81"
    assert "--mlx-checkpoint" in command


def test_wan22_command_uses_fast_taehv() -> None:
    command = media_worker.wan22_command(
        "python3",
        Path("mlx_wan22_generate.py"),
        Path("/models/FastMetal-5B"),
        "river at golden hour",
        Path("/tmp/river.mp4"),
    )
    assert Path(command[1]).name == "bounded_video.py"
    assert command[2] == "mlx_wan22_generate.py"
    assert command[command.index("--decode-backend") + 1] == "taehv"
    assert command[command.index("--width") + 1] == "832"
    assert command[command.index("--height") + 1] == "448"
    assert command[command.index("--num-frames") + 1] == "121"
    assert "--fast" in command
    assert "--text-encoder-root" in command
    assert command[command.index("--text-encoder-device") + 1] == "auto"
    assert "--vae-root" in command


def test_plan_and_trim_math() -> None:
    # Pin the fallback so machines with video-14b/5b installed still exercise 1.3B plan math.
    os.environ["PROMETH_VIDEO_MODEL_ID"] = "video"
    try:
        plan = media_worker.job_plan("waves at sunset")
        assert plan["fastvideo"] == "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f"
        assert plan["model"] == "FastVideo/FastMetal-1.3B-QAD"
        assert plan["revision"] == "2dac0154b217adabf8895d6cde7d6d93e68b7bec"
        assert plan["pipeline"] == "wan21"
        assert plan["width"] == 832 and plan["height"] == 480
        assert plan["seconds"] == 5.0 and plan["silent"] is True
        assert abs(media_worker.trim_duration(1.0, 3.0) - 2.0) < 0.1
    finally:
        os.environ.pop("PROMETH_VIDEO_MODEL_ID", None)


def test_plan_for_video_5b_uses_wan22() -> None:
    os.environ["PROMETH_VIDEO_MODEL_ID"] = "video-5b"
    try:
        plan = media_worker.job_plan("river at golden hour")
        assert plan["model"] == "FastVideo/FastMetal-5B-QAD"
        assert plan["revision"] == "5e4819ec9c8dd062443cf015bd9022c700eca458"
        assert plan["pipeline"] == "wan22"
        assert plan["width"] == 832 and plan["height"] == 448
        assert plan["frames"] == 121
        assert plan["decodeBackend"] == "taehv"
    finally:
        os.environ.pop("PROMETH_VIDEO_MODEL_ID", None)


def test_standin_trim_and_poster(tmp_path: Path) -> None:
    os.environ["PROMETH_MEDIA_MOCK"] = "1"
    worker = media_worker.Worker()
    clip = tmp_path / "clip.mp4"
    poster = tmp_path / "poster.png"
    plan = worker.generate("waves at sunset", clip, poster)
    assert plan["mock"] is True
    assert clip.stat().st_size > 1000
    assert poster.stat().st_size > 24
    info = probe(clip)
    assert info["width"] == 832 and info["height"] == 480
    assert abs(info["duration"] - 5.0) < 0.2
    trimmed = tmp_path / "clip-v2.mp4"
    result = worker.trim(clip, trimmed, 1.0, 3.0)
    assert abs(result["duration"] - 2.0) < 0.1
    assert clip.exists() and trimmed.exists()
    trimmed_info = probe(trimmed)
    assert abs(trimmed_info["duration"] - 2.0) <= 0.1
    assert trimmed_info["width"] == 832


def test_cancel_kills_the_child(tmp_path: Path) -> None:
    script = ROOT / "PromethRuntime" / "media" / "media_worker.py"
    env = os.environ.copy()
    env["PROMETH_MEDIA_MOCK"] = "1"
    # Replace ffmpeg with a sleeper by putting a stub first on PATH.
    bindir = tmp_path / "bin"
    bindir.mkdir(parents=True)
    pidfile = tmp_path / "child.pid"
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
        "output": str(tmp_path / "slow.mp4"),
        "poster": str(tmp_path / "slow.png"),
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
    test_wan22_command_uses_fast_taehv()
    test_plan_and_trim_math()
    test_plan_for_video_5b_uses_wan22()
    test_standin_trim_and_poster(tmp / "standin")
    test_cancel_kills_the_child(tmp / "cancel")
    print(json.dumps({"passed": True, "tests": 6, "fastvideo": media_worker.FASTVIDEO_COMMIT}))


if __name__ == "__main__":
    main()
