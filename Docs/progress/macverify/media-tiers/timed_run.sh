#!/bin/bash
# Single timed media generation. Usage: timed_run.sh <label> -- <command...>
set -uo pipefail
OUTDIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="$1"; shift
[[ "${1:-}" == "--" ]] && shift
LOG="$OUTDIR/${LABEL}.log"
TIMEF="$OUTDIR/${LABEL}.time.txt"
FOOT="$OUTDIR/${LABEL}.footprint.txt"
: > "$LOG"; : > "$TIMEF"; : > "$FOOT"
echo "START $(date -u +%Y-%m-%dT%H:%M:%SZ) label=$LABEL" | tee -a "$LOG"
echo "CMD: $*" | tee -a "$LOG"
echo "chat:" | tee -a "$LOG"
pgrep -lf 'mlx-vlm-server|llama-server|nativ_server' | tee -a "$LOG" || echo NONE | tee -a "$LOG"

# Run time in foreground of this script so wait works; sample in background.
/usr/bin/time -l "$@" >"$LOG.stdout" 2>"$TIMEF" &
TP=$!
sleep 2
PP=$(pgrep -P "$TP" | head -1 || true)
# Prefer the real python/mlx child if present
for cand in $(pgrep -P "$TP" || true); do
  if ps -p "$cand" -o command= | rg -q 'python|mlx'; then PP=$cand; fi
done
echo "time_pid=$TP child_pid=$PP" | tee -a "$LOG"
(
  while kill -0 "${PP:-0}" 2>/dev/null; do
    footprint -p "$PP" -f bytes 2>/dev/null | rg 'phys_footprint' >> "$FOOT" || true
    sleep 1
  done
) &
SAMP=$!
wait "$TP"
EC=$?
wait "$SAMP" 2>/dev/null || true
cat "$LOG.stdout" >> "$LOG"
rm -f "$LOG.stdout"
echo "EXIT:$EC" | tee -a "$TIMEF"
echo "END $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$LOG"
# Summarize
python3 - <<PY
import re
from pathlib import Path
label="$LABEL"
timef=Path("$TIMEF").read_text()
foot=Path("$FOOT").read_text()
rss=fp=None
for line in timef.splitlines():
    if "maximum resident set size" in line.lower():
        rss=int(line.split()[0])
    if "peak memory footprint" in line.lower():
        fp=int(line.split()[0])
def parse_foot(text):
    vals=[]
    for line in text.splitlines():
        m=re.search(r'phys_footprint(?:_peak)?:\s*([\d.]+)\s*([KMGT]?B)', line, re.I)
        if not m: continue
        n=float(m.group(1)); u=m.group(2).upper()
        mult={'B':1,'KB':1024,'MB':1024**2,'GB':1024**3,'TB':1024**4}[u]
        vals.append(n*mult)
    return max(vals) if vals else None
phys=parse_foot(foot)
mlx=[]
for line in Path("$LOG").read_text().splitlines()+timef.splitlines():
    if "peak memory" in line.lower() and "gi" in line.lower():
        mlx.append(line.strip())
print(f"SUMMARY {label}")
print(f"  exit={$EC}")
print(f"  time_l_max_rss_gib={None if rss is None else round(rss/1024**3,3)}")
print(f"  time_l_peak_footprint_gib={None if fp is None else round(fp/1024**3,3)}")
print(f"  sampled_phys_footprint_max_gib={None if phys is None else round(phys/1024**3,3)}")
for m in mlx[-6:]:
    print(f"  mlx_line: {m}")
PY
exit "$EC"
