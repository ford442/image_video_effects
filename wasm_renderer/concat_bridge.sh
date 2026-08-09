#!/bin/bash
# Synchronize wasm_renderer/bridge/*.js into WASM bridge modules and sync copies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/bridge"
OUT="$SCRIPT_DIR/wasm_bridge.js"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBLIC_WASM="$REPO_ROOT/public/wasm"
SRC_WASM="$REPO_ROOT/src/wasm"

mkdir -p "$PUBLIC_WASM/bridge" "$SRC_WASM/bridge" "$BRIDGE_DIR"

# Copy bridge submodules across canonical and distribution paths
cp "$SRC_WASM/bridge/"*.js "$BRIDGE_DIR/"
cp "$SRC_WASM/bridge/"*.js "$PUBLIC_WASM/bridge/"

# Sync barrel file
cp "$SRC_WASM/wasm_bridge.js" "$OUT"
cp "$SRC_WASM/wasm_bridge.js" "$PUBLIC_WASM/wasm_bridge.js"

if [ -f "$SCRIPT_DIR/wasm_bridge.d.ts" ]; then
  cp "$SCRIPT_DIR/wasm_bridge.d.ts" "$SRC_WASM/wasm_bridge.d.ts"
fi

echo "✅ Bridge modules synchronized to public/wasm/ and src/wasm/"
