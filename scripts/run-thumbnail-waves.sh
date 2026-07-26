#!/usr/bin/env bash
# Run thumbnail coverage waves on a GPU workstation.
# Usage: bash scripts/run-thumbnail-waves.sh [--wave=W1|W2|W3|all]
set -euo pipefail
cd "$(dirname "$0")/.."

WAVE="${1:-all}"
WAVE="${WAVE#--wave=}"

run_category() {
  local cat="$1"
  echo "=== thumbs:generate --missing --category=$cat ==="
  npm run thumbs:generate -- --missing --category="$cat"
}

wave_w1() {
  run_category generative
  run_category visual-effects
}

wave_w2() {
  run_category simulation
  run_category distortion
  run_category liquid-effects
}

wave_w3() {
  run_category image
  run_category post-processing
  run_category artistic
  run_category retro-glitch
  run_category lighting-effects
  run_category geometric
  run_category hybrid
  run_category advanced-hybrid
  run_category interactive-mouse
}

echo "Building production app..."
SKIP_WASM_BUILD=1 npm run build

case "$WAVE" in
  W1) wave_w1 ;;
  W2) wave_w2 ;;
  W3) wave_w3 ;;
  all)
    wave_w1
    wave_w2
    wave_w3
    ;;
  *)
    echo "Unknown wave: $WAVE (use W1, W2, W3, or all)"
    exit 1
    ;;
esac

npm run thumbs:status
python3 scripts/audit_thumbnail_integrity.py || true
echo "Done. Review reports/thumbnail-failures.json and triage skip allowlist."
