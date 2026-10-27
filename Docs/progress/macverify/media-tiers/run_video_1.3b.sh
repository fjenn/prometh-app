#!/bin/bash
# Measure FastMetal 1.3B exactly as media_worker.fastvideo_command does.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
OUTDIR="$ROOT/Docs/progress/macverify/media-tiers"
PY="$ROOT/PromethRuntime/media/.venv/bin/python3"
CHECKOUT="$ROOT/PromethRuntime/media/fastvideo"
MODEL="$HOME/Library/Application Support/Prometh/Models/FastVideo--FastMetal-1.3B-QAD--2dac0154b217"
RUN="${1:-1}"
CLIP="$OUTDIR/video-1.3b-run${RUN}.mp4"
LOG="$OUTDIR/video-1.3b-run${RUN}.log"
TIMEF="$OUTDIR/video-1.3b-run${RUN}.time.txt"
FOOT="$OUTDIR/video-1.3b-run${RUN}.footprint.txt"
: > "$FOOT"
export PYTHONPATH="$CHECKOUT"
export PYTHONNOUSERSITE=1
export PYTHONUNBUFFERED=1
export HF_HUB_OFFLINE=1
export PROMETH_VIDEO_MODEL_ID=video

echo "chat servers before run:" | tee "$LOG"
pgrep -lf 'mlx-vlm-server|llama-server|nativ_server' | tee -a "$LOG" || echo "NONE" | tee -a "$LOG"

/usr/bin/time -l "$PY" \
  "$CHECKOUT/examples/inference/basic/mlx_wan_prompt_to_video.py" \
  --model-root "$MODEL" \
  --mlx-checkpoint "$MODEL" \
  --prompt "a calm ocean wave rolling onto a sandy beach at sunset" \
  --output-path "$CLIP" \
  --height 480 --width 832 --num-frames 81 --fps 16 \
  --decode-backend wan-vae --seed 1024 \
  > >(tee -a "$LOG") 2> "$TIMEF" &
TIMEPID=$!
sleep 2
PYPID=$(pgrep -f 'mlx_wan_prompt_to_video.py' | head -1 || true)
echo "time_pid=$TIMEPID python_pid=$PYPID" | tee -a "$LOG"
if [[ -n "${PYPID:-}" ]]; then
  (
    while kill -0 "$PYPID" 2>/dev/null; do
      footprint -p "$PYPID" 2>/dev/null | awk -v ts="$(date +%s)" '
        /phys_footprint/ { print ts, $0 }
        /Footprint:/ { print ts, $0 }
      ' >> "$FOOT" || true
      sleep 1
    done
  ) &
  SAMP=$!
fi
wait "$TIMEPID"
EC=$?
[[ -n "${SAMP:-}" ]] && wait "$SAMP" || true
echo "EXIT:$EC" | tee -a "$TIMEF"
ls -lh "$CLIP" | tee -a "$LOG"
exit "$EC"
