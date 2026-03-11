#!/bin/bash
set -euo pipefail
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

# Resolve the repo's wasm_renderer directory (always relative to this script,
# regardless of where the script is invoked from).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Source directory: $SCRIPT_DIR"

# Source Emscripten from wherever emsdk lives
CANDIDATES=(
    "/content/build_space/emsdk/emsdk_env.sh"
    "${REPO_ROOT:-}/emsdk/emsdk_env.sh"
    "$HOME/emsdk/emsdk_env.sh"
    "/usr/local/emsdk/emsdk_env.sh"
)
for f in "${CANDIDATES[@]}"; do
    if [ -f "$f" ]; then
        # shellcheck disable=SC1090
        source "$f"
        break
    fi
done

# Set writable cache location for TOT emscripten

# Check if emcc is available before proceeding
if ! command -v emcc &> /dev/null; then
    echo "⚠️ Warning: emcc not found. Skipping WASM build."
    exit 0
fi

export EM_CACHE=/tmp/emscripten_cache

# Print diagnostics
emcc --version | head -1
echo "EM_CACHE: $EM_CACHE"
echo "EMCC_CFLAGS: ${EMCC_CFLAGS:-<unset>}"

# Clear any legacy EMCC_CFLAGS that might carry -sUSE_WEBGPU=1 forward from
# older emsdk installs.
unset EMCC_CFLAGS

BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

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
# --use-port=emdawnwebgpu runs emdawnwebgpu.py's process_args() exactly once
# at the combined compile/link step.  In a cmake two-step build the flag leaks
# into per-TU compile invocations and recent Emscripten rejects the resulting
# USE_WEBGPU state with "invalid command line setting `-sUSE_WEBGPU=1`".
#
# Source files are referenced by absolute path so this script can be run from
# any CWD (e.g. /content/build_space/) without accidentally picking up stale
# copies that still use the old WebGPU C++ API or html5_webgpu.h.
echo "=== Compiling + linking ==="
emcc -std=c++20 -O2 \
    --use-port=emdawnwebgpu \
    "$SCRIPT_DIR/main.cpp" \
    "$SCRIPT_DIR/renderer.cpp" \
    "-I$SCRIPT_DIR" \
    -sEXPORTED_FUNCTIONS="${EXPORTED}" \
    -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,HEAPU8 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sNO_EXIT_RUNTIME=1 \
    -sMODULARIZE=1 \
    -sEXPORT_NAME=PixelocityWASM \
    -o "$BUILD_DIR/pixelocity_wasm.js"

# Copy output to public folder (repo-relative path)
PUBLIC_WASM="$SCRIPT_DIR/../../public/wasm"
mkdir -p "$PUBLIC_WASM"
cp "$BUILD_DIR/pixelocity_wasm.js" "$BUILD_DIR/pixelocity_wasm.wasm" "$PUBLIC_WASM/"
cp "$SCRIPT_DIR/wasm_bridge.js" "$PUBLIC_WASM/"


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
