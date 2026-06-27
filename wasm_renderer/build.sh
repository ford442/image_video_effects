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

# Check if emcc is available early.
# Missing emcc is a hard failure unless SKIP_WASM_BUILD=1 (headless dev VMs without emsdk).
if ! command -v emcc &> /dev/null; then
    if [ "${SKIP_WASM_BUILD:-}" = "1" ]; then
        echo "[INFO] SKIP_WASM_BUILD=1 — skipping WASM build (emcc not found)."
        echo "       Use committed artifacts in public/wasm/ or run on a machine with emsdk."
        exit 0
    fi
    echo "❌ Error: emcc not found. Install the Emscripten SDK to build the WASM renderer."
    echo "   See: https://emscripten.org/docs/getting_started/downloads.html"
    echo "   To skip intentionally (e.g. CI job using pre-built artifacts): SKIP_WASM_BUILD=1 npm run wasm:build"
    exit 1
fi

# Set writable cache location for TOT emscripten

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
_reloadShader,\
_setActiveShader,\
_setSlotShader,\
_setSlotParams,\
_setSlotMode,\
_updateUniforms,\
_updateMousePos,\
_setMouseDown,\
_updateAudioData,\
_updateAudioFrequencyBins,\
_updateDepthMap,\
_setInputSource,\
_addRipple,\
_clearRipples,\
_setTime,\
_setZoomParams,\
_getFPS,\
_getSupportsDeepWorkgroup,\
_getSlotShaderId,\
_getSlotEnabled,\
_getSlotMode,\
_getGPUTimings,\
_setRecording,\
_isRecording,\
_getAdapterSummary,\
_getLastInitErrorStage,\
_getLastInitErrorMessage,\
_isRendererInitialized,\
_loadImageData,\
_uploadVideoFrame,\
_resizeCanvas,\
_beginFrameCapture,\
_getFrameCaptureState,\
_readCapturedFrame,\
_endFrameCapture,\
_getCanvasWidth,\
_getCanvasHeight,\
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
    -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,HEAPU8,HEAPF32 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sNO_EXIT_RUNTIME=1 \
    -sMODULARIZE=1 \
    -sEXPORT_NAME=PixelocityWASM \
    -sASYNCIFY \
    -o "$BUILD_DIR/pixelocity_wasm.js"

# Copy output to public folder (repo-relative path)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLIC_WASM="$REPO_ROOT/public/wasm"
mkdir -p "$PUBLIC_WASM"
cp "$BUILD_DIR/pixelocity_wasm.js" "$BUILD_DIR/pixelocity_wasm.wasm" "$PUBLIC_WASM/"
# Canonical bridge: wasm_renderer/wasm_bridge.js → runtime + webpack import paths
cp "$SCRIPT_DIR/wasm_bridge.js" "$PUBLIC_WASM/"
cp "$SCRIPT_DIR/wasm_bridge.js" "$REPO_ROOT/src/wasm/wasm_bridge.js"
if [ -f "$SCRIPT_DIR/wasm_bridge.d.ts" ]; then
    cp "$SCRIPT_DIR/wasm_bridge.d.ts" "$REPO_ROOT/src/wasm/wasm_bridge.d.ts"
fi

echo "✅ WASM build complete!"
echo "   Emscripten output: public/wasm/pixelocity_wasm.{js,wasm}"
echo "   Bridge copies:     public/wasm/wasm_bridge.js, src/wasm/wasm_bridge.js"
echo "   Edit bridge only:  wasm_renderer/wasm_bridge.js"
