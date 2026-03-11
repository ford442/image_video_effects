#!/bin/bash
set -euo pipefail
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

cd "$(dirname "$0")"

# Activate Emscripten if available
if [ -f "/opt/emsdk/emsdk_env.sh" ]; then
  source /opt/emsdk/emsdk_env.sh
elif [ -f "$HOME/emsdk/emsdk_env.sh" ]; then
  source "$HOME/emsdk/emsdk_env.sh"
elif [ -f "../../emsdk/emsdk_env.sh" ]; then
  source "../../emsdk/emsdk_env.sh"
fi

# Set writable cache location for TOT emscripten
export EM_CACHE=/tmp/emscripten_cache

# Print emscripten version for diagnostics
emcc --version | head -1

# Print cache dir and check for any stale USE_WEBGPU env flags
echo "EM_CACHE: $EM_CACHE"
echo "EMCC_CFLAGS: ${EMCC_CFLAGS:-<unset>}"

# Clear any legacy EMCC_CFLAGS that might include -sUSE_WEBGPU=1
# (older emsdk installs sometimes left this behind)
unset EMCC_CFLAGS

# Clean previous build
mkdir -p build

EXPORTED="_main,\
_initWasmRenderer,\
_shutdownWasmRenderer,\
_loadShader,\
_setActiveShader,\
_updateUniforms,\
_addRipple,\
_clearRipples,\
_getFPS,\
_isRendererInitialized,\
_loadImageData,\
_uploadVideoFrame,\
_malloc,\
_free"

# Single-pass compile+link via emcc.
# --use-port=emdawnwebgpu is safe here: it runs emdawnwebgpu.py's
# process_args() exactly once, at link time. In a two-step cmake build the
# flag leaks into per-TU compile invocations and some Emscripten versions
# misinterpret it as -sUSE_WEBGPU=1 during those early passes.
echo "=== Compiling + linking ==="
emcc -std=c++20 -O2 \
    --use-port=emdawnwebgpu \
    main.cpp renderer.cpp \
    -sEXPORTED_FUNCTIONS="${EXPORTED}" \
    -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,HEAPU8 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sNO_EXIT_RUNTIME=1 \
    -sMODULARIZE=1 \
    -sEXPORT_NAME=PixelocityWASM \
    -o build/pixelocity_wasm.js

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

# Copy bridge to src
mkdir -p ../src/wasm
cp wasm_bridge.js ../src/wasm/
cp wasm_bridge.d.ts ../src/wasm/

echo "✅ WASM build complete! Output in public/wasm/"
