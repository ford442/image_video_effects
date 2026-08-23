#!/bin/bash
# JS bridge source of truth is src/wasm/bridge/*.js (webpack imports src/wasm/wasm_bridge.js).
# This script copies those modules OUT to wasm_renderer/bridge/ and public/wasm/bridge/.
# Editing wasm_renderer/bridge/*.js is a no-op — the next wasm:build overwrites it from src/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/bridge"
OUT="$SCRIPT_DIR/wasm_bridge.js"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBLIC_WASM="$REPO_ROOT/public/wasm"
SRC_WASM="$REPO_ROOT/src/wasm"

mkdir -p "$PUBLIC_WASM/bridge" "$SRC_WASM/bridge" "$BRIDGE_DIR"

# src/wasm/bridge → wasm_renderer/bridge + public/wasm/bridge
cp "$SRC_WASM/bridge/"*.js "$BRIDGE_DIR/"
cp "$SRC_WASM/bridge/"*.js "$PUBLIC_WASM/bridge/"

# src/wasm/wasm_bridge.js barrel → wasm_renderer + public
cp "$SRC_WASM/wasm_bridge.js" "$OUT"
cp "$SRC_WASM/wasm_bridge.js" "$PUBLIC_WASM/wasm_bridge.js"

# Types remain canonical in wasm_renderer/ and copy into src/wasm/
if [ -f "$SCRIPT_DIR/wasm_bridge.d.ts" ]; then
  cp "$SCRIPT_DIR/wasm_bridge.d.ts" "$SRC_WASM/wasm_bridge.d.ts"
fi

echo "✅ Bridge modules synced from src/wasm/bridge → wasm_renderer/bridge + public/wasm/bridge"
