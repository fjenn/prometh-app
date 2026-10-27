#!/bin/bash
# Measure FLUX.2 Klein 4B 4-bit exactly as Prometh defaults: 512x512, 4 steps.
# Uses bundled mlx-vlm generate CLI (same stack as /v1/images/generations).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
OUTDIR="$ROOT/Docs/progress/macverify/media-tiers"
PYROOT="$ROOT/build/NativDevelopmentDerivedData/Build/Products/Release/NativServerKit.framework/Versions/A/Resources/mlx-vlm-server"
PY="$PYROOT/python/bin/python3"
MODEL="$HOME/Library/Application Support/Prometh/Models/Runpod--FLUX.2-klein-4B-mflux-4bit--7ee1b3aa8178"
RUN="${1:-1}"
OUT="$OUTDIR/images-4b-run${RUN}.png"
LABEL="images-4b-timed${RUN}"
export PYTHONNOUSERSITE=1
export PYTHONUNBUFFERED=1
export HF_HUB_OFFLINE=1
export MLX_VLM_MODEL_PATHS="$HOME/Library/Application Support/Prometh/Models"

# Ensure chat not loaded
pgrep -lf 'llama-server|mlx-vlm-server|nativ_server' && {
  echo "REFUSING: chat/mlx server still running" >&2
  exit 2
} || true

exec "$OUTDIR/timed_run.sh" "$LABEL" -- \
  "$PY" -m mlx_vlm.generate \
  --model "$MODEL" \
  --output-modality image \
  --task generate \
  --prompt "a calm ocean wave rolling onto a sandy beach at sunset, photorealistic" \
  --size 512x512 \
  --steps 4 \
  --seed 1024 \
  --output "$OUT"
