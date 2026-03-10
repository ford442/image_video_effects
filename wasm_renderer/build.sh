#!/bin/bash
set -e

cd "$(dirname "$0")"

# Activate Emscripten if available
if [ -f "/opt/emsdk/emsdk_env.sh" ]; then
  source /opt/emsdk/emsdk_env.sh
elif [ -f "$HOME/emsdk/emsdk_env.sh" ]; then
  source "$HOME/emsdk/emsdk_env.sh"
elif [ -f "../../emsdk/emsdk_env.sh" ]; then
  source "../../emsdk/emsdk_env.sh"
fi

# Check if emcmake is available before proceeding
if ! command -v emcmake &> /dev/null; then
    echo "⚠️ Warning: emcmake not found. Skipping WASM build."
    exit 0
fi

# Build
emcmake cmake -B build -S .
emmake make -C build

# Copy to public
mkdir -p ../public/wasm
cp build/pixelocity_wasm.js ../public/wasm/
cp build/pixelocity_wasm.wasm ../public/wasm/

echo "✅ WASM build complete! Output in public/wasm/"
