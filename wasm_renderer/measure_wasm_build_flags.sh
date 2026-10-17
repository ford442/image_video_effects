#!/usr/bin/env bash
# measure_wasm_build_flags.sh — size (and optionally smoke-test) Emscripten flag
# experiments against the real build: the release flags and exports from
# src/contracts/wasm_compile_flags.json + wasm_exports.json, plus one variant's
# extra flags. Prints Markdown table rows for BUILD_FLAG_EXPERIMENTS.md.
#
#   bash wasm_renderer/measure_wasm_build_flags.sh            # sizes only
#   SMOKE=1 bash wasm_renderer/measure_wasm_build_flags.sh    # + SwiftShader smoke per variant
#   VARIANTS="baseline closure" bash wasm_renderer/measure_wasm_build_flags.sh
#
# SMOKE=1 needs a production build (npm run build): each variant's js/wasm is
# swapped into build/wasm/ for `playwright --project=swiftshader-smoke` (WASM
# init, every parity shader, the multi-slot stack), then the original is restored.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/experiments"
mkdir -p "$BUILD_DIR"

# Same emsdk lookup as build.sh: the first candidate that exists wins.
for f in "/content/build_space/emsdk/emsdk_env.sh" "$ROOT/emsdk/emsdk_env.sh" "$HOME/emsdk/emsdk_env.sh"; do
  if [ -f "$f" ]; then source "$f" >/dev/null 2>&1; break; fi
done
command -v emcc &>/dev/null || { echo "emcc not found — source emsdk_env.sh first"; exit 1; }
bash "$ROOT/scripts/emcc-version-gate.sh" >&2
unset EMCC_CFLAGS
export PATH="$ROOT/node_modules/.bin:$PATH"

mapfile -t BASE_FLAGS < <(node "$ROOT/scripts/format-wasm-compile-flags.js" args)
SOURCES=()
while IFS= read -r src; do SOURCES+=("$SCRIPT_DIR/$src"); done \
  < <(node "$ROOT/scripts/format-wasm-compile-flags.js" sources)
EXPORTED="$(node "$ROOT/scripts/format-wasm-exports.js" functions)"
RUNTIME_METHODS="$(node "$ROOT/scripts/format-wasm-exports.js" runtime)"

# Direct-call chains to wgpuInstanceWaitAny (scripts/check-asyncify-exports.mjs):
# the five async exports and the helpers LTO leaves out of line.
ASYNCIFY_ONLY_FILE="$BUILD_DIR/asyncify-only.txt"
cat > "$ASYNCIFY_ONLY_FILE" <<'EOF'
initWasmRenderer
loadShader
reloadShader
resizeCanvas
setColorFormat
wgpuInstanceWaitAny
pixelocity::WebGPURenderer::CompileShaderPipeline(char const*, char const*, unsigned int, unsigned int, unsigned int, pixelocity::ShaderPipeline&)
pixelocity::WebGPURenderer::CreateDevice()::$_5::operator()(WGPUTextureFormat, char const*) const
pixelocity::WebGPURenderer::CreateHistoryTextureFailSoft()
pixelocity::WebGPURenderer::RecreateTextures()
pixelocity::WebGPURenderer::TryCreateHistoryTexture(unsigned int, unsigned int, unsigned int)
EOF

variant_flags() {
  case "$1" in
    baseline)        ;;
    asyncify-only)   echo "-sASYNCIFY_ONLY=@$ASYNCIFY_ONLY_FILE" ;;
    no-exceptions)   echo "-fno-exceptions -fno-rtti" ;;
    filesystem0)     echo "-sFILESYSTEM=0" ;;
    emmalloc)        echo "-sMALLOC=emmalloc" ;;
    strict)          echo "-sSTRICT" ;;
    incoming-api)    echo "-sINCOMING_MODULE_JS_API=[locateFile]" ;;
    closure)         echo "--closure=1" ;;
    combined)        echo "${COMBINED_FLAGS:?set COMBINED_FLAGS to the adopted flags}" ;;
    *) echo "unknown variant $1" >&2; exit 2 ;;
  esac
}

smoke() {
  local dir="$1" live="$ROOT/build/wasm"
  [ -f "$live/pixelocity_wasm.wasm" ] || { echo "no build/ (npm run build)"; return; }
  cp "$live/pixelocity_wasm.js" "$BUILD_DIR/.live.js"
  cp "$live/pixelocity_wasm.wasm" "$BUILD_DIR/.live.wasm"
  cp "$dir/pixelocity_wasm.js" "$dir/pixelocity_wasm.wasm" "$live/"
  local result
  if (cd "$ROOT" && npx playwright test tests/wasm-renderer.smoke.spec.ts --project=swiftshader-smoke \
        -g 'initializes|WASM smoke:|multi-slot' > "$dir/smoke.log" 2>&1); then
    result="pass ($(grep -Eo '[0-9]+ passed' "$dir/smoke.log"))"
  else
    result="FAIL ($(grep -Eo '[0-9]+ (passed|failed|skipped)' "$dir/smoke.log" | paste -sd, -))"
  fi
  cp "$BUILD_DIR/.live.js" "$live/pixelocity_wasm.js"
  cp "$BUILD_DIR/.live.wasm" "$live/pixelocity_wasm.wasm"
  echo "$result"
}

echo "| Variant | Flags | .wasm bytes | .js bytes | Δ .wasm vs baseline | Smoke (SwiftShader) |"
echo "|---------|-------|------------:|----------:|--------------------:|---------------------|"
BASE_WASM=""
for name in ${VARIANTS:-baseline asyncify-only no-exceptions filesystem0 emmalloc strict incoming-api closure}; do
  dir="$BUILD_DIR/$name"
  mkdir -p "$dir"
  read -r -a extra <<< "$(variant_flags "$name")"
  if ! em++ "${BASE_FLAGS[@]}" "${extra[@]}" "${SOURCES[@]}" "-I$SCRIPT_DIR" \
       -sEXPORTED_FUNCTIONS="$EXPORTED" -sEXPORTED_RUNTIME_METHODS="$RUNTIME_METHODS" \
       -o "$dir/pixelocity_wasm.js" > "$dir/build.log" 2>&1; then
    echo "| $name | \`${extra[*]:-}\` | — | — | — | build FAILED: $(grep -m1 -E 'error' "$dir/build.log" | cut -c1-120) |"
    continue
  fi
  wasm=$(wc -c < "$dir/pixelocity_wasm.wasm")
  js=$(wc -c < "$dir/pixelocity_wasm.js")
  [ -z "$BASE_WASM" ] && BASE_WASM=$wasm
  delta=$(( wasm - BASE_WASM ))
  pct=$(awk -v d="$delta" -v b="$BASE_WASM" 'BEGIN { printf "%+.1f%%", 100 * d / b }')
  result="not run"
  [ "${SMOKE:-0}" = "1" ] && result="$(smoke "$dir")"
  echo "| $name | \`${extra[*]:-}\` | $wasm | $js | $delta ($pct) | $result |"
done
