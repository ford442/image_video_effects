#!/bin/bash
# `npm run build` prebuild step for the WASM renderer (frozen R&D, #1329/#1080).
#
# Default: no emcc needed. Sync the JS bridge from src/wasm/bridge/*.ts and use
# the committed public/wasm/* artifacts. Set BUILD_WASM=1 to also recompile them
# (same as `npm run wasm:build`, which needs the Emscripten SDK).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${BUILD_WASM:-}" = "1" ]; then
    exec bash "$SCRIPT_DIR/build.sh"
fi

bash "$SCRIPT_DIR/concat_bridge.sh"
echo "[INFO] Using committed public/wasm/* artifacts (set BUILD_WASM=1 to rebuild with emcc)."
