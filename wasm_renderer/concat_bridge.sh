#!/bin/bash
# Concatenate wasm_renderer/bridge/*.js into wasm_bridge.js and sync copies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/bridge"
OUT="$SCRIPT_DIR/wasm_bridge.js"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODULES=(
  header.js
  state.js
  diagnostics.js
  init.js
  shader.js
  uniforms.js
  capture.js
  recording.js
  api.js
)

: > "$OUT"
for mod in "${MODULES[@]}"; do
  src="$BRIDGE_DIR/$mod"
  if [ ! -f "$src" ]; then
    echo "❌ Missing bridge module: $src" >&2
    exit 1
  fi
  cat "$src" >> "$OUT"
  printf '\n' >> "$OUT"
done

PUBLIC_WASM="$REPO_ROOT/public/wasm"
mkdir -p "$PUBLIC_WASM"
cp "$OUT" "$PUBLIC_WASM/wasm_bridge.js"
cp "$OUT" "$REPO_ROOT/src/wasm/wasm_bridge.js"
if [ -f "$SCRIPT_DIR/wasm_bridge.d.ts" ]; then
  cp "$SCRIPT_DIR/wasm_bridge.d.ts" "$REPO_ROOT/src/wasm/wasm_bridge.d.ts"
fi

echo "✅ Bridge concatenated: $OUT ($(wc -l < "$OUT") lines)"
echo "   Synced to: public/wasm/wasm_bridge.js, src/wasm/wasm_bridge.js"
