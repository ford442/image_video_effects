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

# Set writable cache for TOT emscripten
export EM_CACHE=${EM_CACHE:-/tmp/emscripten_cache}

# Build
emcmake cmake -B build -S .
emmake make -C build

# Copy to public
mkdir -p ../public/wasm
cp build/pixelocity_wasm.js ../public/wasm/
cp build/pixelocity_wasm.wasm ../public/wasm/

echo "✅ WASM build complete! Output in public/wasm/"
