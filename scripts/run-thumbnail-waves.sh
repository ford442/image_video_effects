#!/usr/bin/env bash
# Run thumbnail coverage waves on a GPU workstation.
# Usage: bash scripts/run-thumbnail-waves.sh [--wave=attract|W1|W2|W3|all]
set -euo pipefail
cd "$(dirname "$0")/.."

WAVE="${1:-all}"
WAVE="${WAVE#--wave=}"

run_category() {
  local cat="$1"
  echo "=== thumbs:generate --missing --category=$cat ==="
  npm run thumbs:generate -- --missing --category="$cat"
}

retry_integrity_failures() {
  echo "=== auditing + retrying invalid committed thumbnails ==="
  python3 scripts/audit_thumbnail_integrity.py || true
  local ids
  ids="$(node -e "const r=require('./reports/thumbnail_integrity_audit.json'); process.stdout.write((r.entries||[]).map(e=>e.id).join(','))")"
  if [[ -n "$ids" ]]; then
    npm run thumbs:generate -- --force --ids="$ids"
  else
    echo "No integrity failures to retry."
  fi
}

wave_priority() {
  echo "=== thumbs:generate --missing --priority=attract ==="
  npm run thumbs:generate -- --missing --priority=attract
}

wave_w1() {
  run_category generative
}

wave_w2() {
  run_category simulation
  run_category interactive-mouse
}

wave_w3() {
  run_category visual-effects
  run_category distortion
  run_category liquid-effects
  run_category image
  run_category post-processing
  run_category artistic
  run_category retro-glitch
  run_category lighting-effects
  run_category geometric
  run_category hybrid
  run_category advanced-hybrid
}

echo "Building production app..."
SKIP_WASM_BUILD=1 npm run build
retry_integrity_failures

case "$WAVE" in
  attract|priority) wave_priority ;;
  W1) wave_w1 ;;
  W2) wave_w2 ;;
  W3) wave_w3 ;;
  all)
    wave_priority
    wave_w1
    wave_w2
    wave_w3
    ;;
  *)
    echo "Unknown wave: $WAVE (use attract, W1, W2, W3, or all)"
    exit 1
    ;;
esac

python3 scripts/audit_thumbnail_integrity.py || true
npm run thumbs:status
echo "Done. Review reports/thumbnail-failures.json and triage skip allowlist."
