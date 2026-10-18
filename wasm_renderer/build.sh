#!/bin/bash
set -euo pipefail
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

# Resolve the repo's wasm_renderer directory (always relative to this script,
# regardless of where the script is invoked from).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Source directory: $SCRIPT_DIR"

# Always sync JS bridge from src/wasm/bridge/*.ts (no emcc required).
bash "$SCRIPT_DIR/concat_bridge.sh"

# Find emsdk: emcc already on PATH wins, else EMSDK_ENV / $EMSDK / ~/emsdk (see the script).
source "$SCRIPT_DIR/emsdk_env_locate.sh"

# Check if emcc is available early.
# Missing emcc is a hard failure unless SKIP_WASM_BUILD=1 (headless dev VMs without emsdk).
if ! command -v emcc &> /dev/null; then
    if [ "${SKIP_WASM_BUILD:-}" = "1" ]; then
        echo "[INFO] SKIP_WASM_BUILD=1 — skipping WASM build (emcc not found)."
        echo "       Use committed artifacts in public/wasm/ or run on a machine with emsdk."
        echo "       Bridge was still synced from src/wasm/bridge/*.ts."
        exit 0
    fi
    echo "❌ Error: emcc not found. Install the Emscripten SDK to build the WASM renderer."
    echo "   See: https://emscripten.org/docs/getting_started/downloads.html"
    echo "   To skip intentionally (e.g. CI job using pre-built artifacts): SKIP_WASM_BUILD=1 npm run wasm:build"
    exit 1
fi

if [ "${SKIP_WASM_BUILD:-}" = "1" ]; then
    echo "[INFO] SKIP_WASM_BUILD=1 — skipping emcc compile (bridge was synced above)."
    echo "       Use committed artifacts in public/wasm/."
    exit 0
fi

# Writable emscripten cache (system libs + the emdawnwebgpu port headers).
# Override to keep per-emsdk caches apart: EM_CACHE=$HOME/.cache/em-6.0.12 npm run wasm:build
export EM_CACHE="${EM_CACHE:-/tmp/emscripten_cache}"

# Print diagnostics
em++ --version | head -1
echo "EM_CACHE: $EM_CACHE"
echo "EMCC_CFLAGS: ${EMCC_CFLAGS:-<unset>}"

# Clear any legacy EMCC_CFLAGS that might carry -sUSE_WEBGPU=1 forward from
# older emsdk installs.
unset EMCC_CFLAGS

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Profile: release (default, the committed artifact) or debug (npm run wasm:build:debug).
# WASM_ASAN=1 adds the debug profile's AddressSanitizer flags. The profiles live in
# src/contracts/wasm_compile_flags.json.
PROFILE="${WASM_PROFILE:-release}"
PROFILE_ARGS=("$PROFILE")
if [ "${WASM_ASAN:-}" = "1" ]; then PROFILE_ARGS+=(--asan); fi
BUILD_DIR="$SCRIPT_DIR/$(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" outdir "${PROFILE_ARGS[@]}")"
mkdir -p "$BUILD_DIR"
echo "Profile: $PROFILE${WASM_ASAN:+ (+ASan)}  Output: ${BUILD_DIR#"$REPO_ROOT"/}"

# Export lists live in src/contracts/wasm_exports.json — do not hardcode them here.
EXPORTED="$(node "$REPO_ROOT/scripts/format-wasm-exports.js" functions)"
RUNTIME_METHODS="$(node "$REPO_ROOT/scripts/format-wasm-exports.js" runtime)"
# Toolchain pin + std/opt/port/-s flags live in src/contracts/wasm_compile_flags.json.
mapfile -t COMPILE_FLAGS < <(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" args "${PROFILE_ARGS[@]}")
JS_OUTPUT_NAME="$(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" output)"
WASM_OUTPUT_NAME="${JS_OUTPUT_NAME%.js}.wasm"

bash "$REPO_ROOT/scripts/emcc-version-gate.sh"
# canvas_configure.h is generated from src/contracts/canvas_configure.json (committed).
node "$REPO_ROOT/scripts/gen-canvas-configure-header.js" --check
# webgpu_limits.h is generated from src/contracts/webgpu_limits.json (committed).
node "$REPO_ROOT/scripts/gen-webgpu-limits-header.js" --check

# Single-pass compile+link via emcc.
# --use-port=emdawnwebgpu runs emdawnwebgpu.py's process_args() exactly once
# at the combined compile/link step.  In a cmake two-step build the flag leaks
# into per-TU compile invocations and recent Emscripten rejects the resulting
# USE_WEBGPU state with "invalid command line setting `-sUSE_WEBGPU=1`".
#
# Module layout (see wasm_renderer/README.md):
#   renderer.cpp      — lifecycle facade (Initialize/Shutdown, slot API, params)
#   device.cpp        — instance/adapter/device/limits/surface/present
#   resources.cpp     — textures, buffers, samplers, resize
#   pipeline.cpp      — shaders, compute/blit pipelines, bind groups
#   frame.cpp         — multi-slot Render(), capture readback
#   audio_depth.cpp   — image/video upload, depth map, audio bins
#   wasm_internal.cpp — shared helpers (limits check, workgroup parse)
#
# Compile flags review (2026-07). Flags themselves are in
# src/contracts/wasm_compile_flags.json (2026-09) — the notes below explain them:
#   -sASYNCIFY          — required for wgpuInstanceWaitAny (adapter/device callbacks).
#                        Adds binary size + async transform cost; do not remove unless
#                        emdawn moves to fully synchronous request APIs.
#   -O2                 — default; -O3 trades ~5-10% size for marginal shader perf.
#                        Benchmark before switching on priority shaders.
#   -sALLOW_MEMORY_GROWTH — needed for 2048² rgba32f ping-pong stacks + staging.
#                        Experiment (2026-07-19): -sINITIAL_MEMORY=67108864 had zero
#                        .wasm size delta vs default; not adopted — see BUILD_FLAG_EXPERIMENTS.md.
#   compatibleSurface=nullptr in device.cpp — intentional; see device.cpp comment.
#
# Source files are referenced by absolute path so this script can be run from
# any CWD without accidentally picking up stale
# copies that still use the old WebGPU C++ API or html5_webgpu.h.
# The TU list is wasm_compile_flags.json `sources` (also read by `npm run wasm:compdb`).
echo "=== Compiling + linking ==="
SOURCES=()
while IFS= read -r src; do
    SOURCES+=("$SCRIPT_DIR/$src")
done < <(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" sources)
echo "Flags: ${COMPILE_FLAGS[*]}"
em++ "${COMPILE_FLAGS[@]}" \
    "${SOURCES[@]}" \
    "-I$SCRIPT_DIR" \
    -sEXPORTED_FUNCTIONS="${EXPORTED}" \
    -sEXPORTED_RUNTIME_METHODS="${RUNTIME_METHODS}" \
    -o "$BUILD_DIR/$JS_OUTPUT_NAME"

# Only the release profile replaces the committed artifact. A debug (-O0, ASSERTIONS,
# optional ASan) module must never land in public/wasm/ where it could be committed.
if [ "$PROFILE" != "release" ]; then
    echo "✅ WASM $PROFILE build complete (public/wasm/ untouched)"
    echo "   Output: ${BUILD_DIR#"$REPO_ROOT"/}/{$JS_OUTPUT_NAME,$WASM_OUTPUT_NAME}"
    echo "   To try it locally: copy those over public/wasm/, then 'git checkout public/wasm' when done."
    exit 0
fi

# Copy output to public folder (repo-relative path)
PUBLIC_WASM="$REPO_ROOT/public/wasm"
mkdir -p "$PUBLIC_WASM"
cp "$BUILD_DIR/$JS_OUTPUT_NAME" "$BUILD_DIR/$WASM_OUTPUT_NAME" "$PUBLIC_WASM/"
echo "✅ WASM build complete!"
echo "   Emscripten output: public/wasm/pixelocity_wasm.{js,wasm}"
echo "   Bridge copies:     public/wasm/wasm_bridge.js, src/wasm/wasm_bridge.js"
echo "   Edit JS bridge:    src/wasm/bridge/*.js (sync via concat_bridge.sh)"
