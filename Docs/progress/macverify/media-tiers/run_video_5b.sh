#!/bin/bash
# Measure FastMetal 5B exactly as media_worker.wan22_command does.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
OUTDIR="$ROOT/Docs/progress/macverify/media-tiers"
PY="$ROOT/PromethRuntime/media/.venv/bin/python3"
CHECKOUT="$ROOT/PromethRuntime/media/fastvideo"
MODEL="$HOME/Library/Application Support/Prometh/Models/FastVideo--FastMetal-5B-QAD--5e4819ec9c8d"
RUN="${1:-1}"
LABEL="video-5b-timed${RUN}"
CLIP="$OUTDIR/video-5b-timed${RUN}.mp4"
export PYTHONPATH="$CHECKOUT"
export PYTHONNOUSERSITE=1
export PYTHONUNBUFFERED=1
# Model weights are local; leave hub online so first-run TAEHV/RIFE caches can fill.
unset HF_HUB_OFFLINE || true
export PROMETH_VIDEO_MODEL_ID=video-5b


pgrep -lf 'llama-server|mlx-vlm-server|nativ_server' && {
  echo "REFUSING: chat/mlx server still running" >&2
  exit 2
} || true

exec "$OUTDIR/timed_run.sh" "$LABEL" -- \
  "$PY" "$CHECKOUT/examples/inference/basic/mlx_wan22_generate.py" \
  --text-encoder-root "$MODEL" \
  --mlx-checkpoint "$MODEL" \
  --vae-root "$MODEL/vae" \
  --prompt "a calm ocean wave rolling onto a sandy beach at sunset" \
  --output-path "$CLIP" \
  --height 448 --width 832 --num-frames 121 --fps 24 \
  --decode-backend taehv --seed 1024 --fast
