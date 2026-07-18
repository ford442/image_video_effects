#!/bin/bash
# Retry runner for Batch 16 Kimi swarm tasks (R3, R4, R6, C1, C2).
# Each task: kimi-cli (quiet+yolo) -> extract WGSL -> naga gate (in extractor).
set -u
cd /root/image_video_effects

BRIEF_DIR="agents/swarm-tasks/kimi-briefs/2026-07-17"
KIMI="/root/.local/bin/kimi-cli"
TIMEOUT_SEC=420

run_task() {
  local key="$1"
  local shader="$2"
  local brief="$BRIEF_DIR/${key}_${shader}.md"
  local raw="/tmp/kimi_${key}_${shader}.txt"

  echo "────────────────────────────────────────────────────────"
  echo "[$key] $shader — start $(date +%T)"
  if [ ! -f "$brief" ]; then
    echo "[$key] MISSING BRIEF: $brief"
    return 1
  fi

  timeout "$TIMEOUT_SEC" "$KIMI" --quiet --yolo < "$brief" > "$raw" 2>&1
  local rc=$?
  echo "[$key] kimi-cli exit=$rc at $(date +%T) ($(wc -c < "$raw") bytes raw)"
  if [ $rc -eq 124 ]; then
    echo "[$key] TIMED OUT after ${TIMEOUT_SEC}s"
    cp "$raw" "swarm-outputs/kimi-rejects/${shader}_timeout.md" 2>/dev/null || true
    return 2
  fi
  if grep -q "access_terminated_error\|usage limit" "$raw"; then
    echo "[$key] QUOTA EXHAUSTED"
    return 3
  fi

  python3 scripts/extract_kimi_wgsl.py "$shader" "$raw"
  local erc=$?
  if [ $erc -eq 0 ]; then
    echo "[$key] EXTRACT+VALIDATE OK"
  else
    echo "[$key] EXTRACT/VALIDATE FAILED rc=$erc (see swarm-outputs/kimi-rejects/)"
  fi
  return $erc
}

FAILED=()
run_task R3 gen-ethereal-cyber-chrono-nebula-phoenix || FAILED+=("R3:$?")
run_task R4 gen-fireworks-comet-trail              || FAILED+=("R4:$?")
run_task R6 gen-fireworks-crossette                || FAILED+=("R6:$?")
run_task C1 gen-audio-reactive-quantum-pollen      || FAILED+=("C1:$?")
run_task C2 gen-magnetic-liquid-glyphs             || FAILED+=("C2:$?")

echo "════════════════════════════════════════════════════════"
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "ALL 5 TASKS COMPLETED OK"
else
  echo "FAILURES: ${FAILED[*]}"
fi
