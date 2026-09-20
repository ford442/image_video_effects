#!/bin/bash
set -euo pipefail
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

# Resolve the repo's wasm_renderer directory (always relative to this script,
# regardless of where the script is invoked from).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Source directory: $SCRIPT_DIR"

# Always sync JS bridge from src/wasm/bridge/*.ts (no emcc required).
bash "$SCRIPT_DIR/concat_bridge.sh"

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

# Set writable cache location for TOT emscripten

export EM_CACHE=/tmp/emscripten_cache

# Print diagnostics
em++ --version | head -1
echo "EM_CACHE: $EM_CACHE"
echo "EMCC_CFLAGS: ${EMCC_CFLAGS:-<unset>}"

# Clear any legacy EMCC_CFLAGS that might carry -sUSE_WEBGPU=1 forward from
# older emsdk installs.
unset EMCC_CFLAGS

BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Export lists live in src/contracts/wasm_exports.json — do not hardcode them here.
EXPORTED="$(node "$REPO_ROOT/scripts/format-wasm-exports.js" functions)"
RUNTIME_METHODS="$(node "$REPO_ROOT/scripts/format-wasm-exports.js" runtime)"
# Toolchain pin + std/opt/port/-s flags live in src/contracts/wasm_compile_flags.json.
# Two variants from the same sources: "asyncify" (fallback, today's ABI) and
# "jspi" (primary where WebAssembly.Suspending exists). Never spell the async
# mode flags here — the contract owns them (verify:wasm-invariants).
FLAGS_JS="$REPO_ROOT/scripts/format-wasm-compile-flags.js"
mapfile -t VARIANTS < <(node "$FLAGS_JS" variants)

bash "$REPO_ROOT/scripts/emcc-version-gate.sh"

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
#   ASYNCIFY / JSPI     — one of the two is required for wgpuInstanceWaitAny (adapter,
#                        device, error-scope pops). The fallback graph uses ASYNCIFY
#                        (+~31% .wasm); the jspi graph uses JSPI and lists every export
#                        that can reach WaitAny in jspiExports. See BUILD_FLAG_EXPERIMENTS.md.
#   -O2                 — default; -O3 trades ~5-10% size for marginal shader perf.
#                        Benchmark before switching on priority shaders.
#   -sALLOW_MEMORY_GROWTH — needed for 2048² rgba32f ping-pong stacks + staging.
#                        Experiment (2026-07-19): -sINITIAL_MEMORY=67108864 had zero
#                        .wasm size delta vs default; not adopted — see BUILD_FLAG_EXPERIMENTS.md.
#   compatibleSurface=nullptr in device.cpp — intentional; see device.cpp comment.
#
# Source files are referenced by absolute path so this script can be run from
# any CWD (e.g. /content/build_space/) without accidentally picking up stale
# copies that still use the old WebGPU C++ API or html5_webgpu.h.
echo "=== Compiling + linking ==="
SOURCES=(
    "$SCRIPT_DIR/main.cpp"
    "$SCRIPT_DIR/renderer.cpp"
    "$SCRIPT_DIR/device.cpp"
    "$SCRIPT_DIR/resources.cpp"
    "$SCRIPT_DIR/pipeline.cpp"
    "$SCRIPT_DIR/frame.cpp"
    "$SCRIPT_DIR/timing.cpp"
    "$SCRIPT_DIR/audio_depth.cpp"
    "$SCRIPT_DIR/wasm_internal.cpp"
)
PUBLIC_WASM="$REPO_ROOT/public/wasm"
mkdir -p "$PUBLIC_WASM"
for VARIANT in "${VARIANTS[@]}"; do
    mapfile -t COMPILE_FLAGS < <(node "$FLAGS_JS" args --variant="$VARIANT")
    JS_OUTPUT_NAME="$(node "$FLAGS_JS" output --variant="$VARIANT")"
    WASM_OUTPUT_NAME="${JS_OUTPUT_NAME%.js}.wasm"
    echo "--- variant: $VARIANT → $JS_OUTPUT_NAME"
    echo "Flags: ${COMPILE_FLAGS[*]}"
    em++ "${COMPILE_FLAGS[@]}" \
        "${SOURCES[@]}" \
        "-I$SCRIPT_DIR" \
        -sEXPORTED_FUNCTIONS="${EXPORTED}" \
        -sEXPORTED_RUNTIME_METHODS="${RUNTIME_METHODS}" \
        -o "$BUILD_DIR/$JS_OUTPUT_NAME"
    cp "$BUILD_DIR/$JS_OUTPUT_NAME" "$BUILD_DIR/$WASM_OUTPUT_NAME" "$PUBLIC_WASM/"
    echo "   $WASM_OUTPUT_NAME: $(wc -c < "$BUILD_DIR/$WASM_OUTPUT_NAME") bytes"
done

echo "✅ WASM build complete!"
echo "   Emscripten output: public/wasm/pixelocity_wasm.{js,wasm} (ASYNCIFY fallback)"
echo "                      public/wasm/pixelocity_wasm_jspi.{js,wasm} (JSPI primary)"
echo "   Bridge copies:     public/wasm/wasm_bridge.js, src/wasm/wasm_bridge.js"
echo "   Edit JS bridge:    src/wasm/bridge/*.ts (sync via concat_bridge.sh)"
