#!/bin/bash
# Batch 17 Kimi swarm runner — Weekly Upgrade Swarm (6 repairs + 2 creations, mixed categories).
# Each task: kimi-cli (quiet+yolo) -> extract WGSL -> naga gate (in extractor).
# Manual rescue fallback: any timeout/quota/extract failure lands in agents/swarm-outputs/kimi-rejects/.
set -u
cd /root/image_video_effects

BRIEF_DIR="agents/swarm-tasks/kimi-briefs/2026-07-18"
REJECT_DIR="agents/swarm-outputs/kimi-rejects"
KIMI="/root/.local/bin/kimi-cli"
TIMEOUT_SEC=420
mkdir -p "$REJECT_DIR"

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
    cp "$raw" "$REJECT_DIR/${shader}_timeout.md" 2>/dev/null || true
    return 2
  fi
  if grep -q "access_terminated_error\|usage limit" "$raw"; then
    echo "[$key] QUOTA EXHAUSTED"
    cp "$raw" "$REJECT_DIR/${shader}_quota.md" 2>/dev/null || true
    return 3
  fi

  python3 scripts/extract_kimi_wgsl.py "$shader" "$raw"
  local erc=$?
  if [ $erc -eq 0 ]; then
    echo "[$key] EXTRACT+VALIDATE OK"
  else
    echo "[$key] EXTRACT/VALIDATE FAILED rc=$erc (see $REJECT_DIR/)"
  fi
  return $erc
}

FAILED=()
run_task R1 gen-hyper-labyrinth            || FAILED+=("R1:$?")
run_task R2 gen-topology-flow              || FAILED+=("R2:$?")
run_task R3 gen-mycelium-network           || FAILED+=("R3:$?")
run_task R4 pixel-sort-explorer            || FAILED+=("R4:$?")
run_task R5 rainbow-vector-field           || FAILED+=("R5:$?")
run_task R6 heat-haze-mirage               || FAILED+=("R6:$?")
run_task C1 gen-audio-reactive-tide-pools  || FAILED+=("C1:$?")
run_task C2 audio-reactive-prism-shatter   || FAILED+=("C2:$?")

echo "════════════════════════════════════════════════════════"
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "ALL 8 TASKS COMPLETED OK"
else
  echo "FAILURES (manual rescue needed): ${FAILED[*]}"
fi
