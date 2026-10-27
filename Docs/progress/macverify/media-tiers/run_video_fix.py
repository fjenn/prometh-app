#!/usr/bin/env python3
"""Time the production command with an uncached prompt (true cold pipeline)."""
import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "PromethRuntime/media"))
import media_worker

parser = argparse.ArgumentParser()
parser.add_argument("model", choices=("video", "video-5b", "video-14b"))
parser.add_argument("run", type=int)
args = parser.parse_args()
if subprocess.run(["pgrep", "-f", "llama-server|mlx-vlm-server|nativ_server"], capture_output=True).returncode == 0:
    raise SystemExit("Refusing measurement with chat server running")
repo, revision, folder, _, pipeline = next(c for c in media_worker.VIDEO_CANDIDATES if c[3] == args.model)
outdir = Path(__file__).resolve().parent
label = f"{args.model}-timed{args.run}-fix"
model = Path.home() / "Library/Application Support/Prometh/Models" / folder
checkout = ROOT / "PromethRuntime/media/fastvideo"
python = str(ROOT / "PromethRuntime/media/.venv/bin/python3")
script = checkout / "examples/inference/basic" / ("mlx_wan22_generate.py" if pipeline == "wan22" else "mlx_wan_prompt_to_video.py")
command = (media_worker.wan22_command if pipeline == "wan22" else media_worker.fastvideo_command)(
    python, script, model, "a calm ocean wave rolling onto a sandy beach at sunset", outdir / f"{label}.mp4",
)
command.append("--no-prompt-cache")
env = os.environ.copy()
env.update(PYTHONPATH=str(checkout), PYTHONNOUSERSITE="1", PYTHONUNBUFFERED="1", HF_HUB_OFFLINE="1")
raise SystemExit(subprocess.call([str(outdir / "timed_run.sh"), label, "--", *command], env=env, cwd=ROOT))
