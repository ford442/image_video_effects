#!/usr/bin/env bash
# measure_wasm_build_flags.sh — size of the real build under extra emcc flag variants.
#
# Builds exactly what build.sh builds (contract flags, TU list, export lists) plus each
# variant's extra flags, into wasm_renderer/build/experiments/, and prints a markdown
# table. The table goes to stdout only: BUILD_FLAG_EXPERIMENTS.md carries hand-written
# analysis, so paste the table into a new dated section yourself.
#
# Usage (emsdk on PATH or under ~/emsdk):
#   bash wasm_renderer/measure_wasm_build_flags.sh                # all variants
#   bash wasm_renderer/measure_wasm_build_flags.sh baseline closure1
# Size only. A smaller binary says nothing about whether init still works: ASYNCIFY
# variants need a real-GPU run (#1080) before they can be adopted.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/experiments"
mkdir -p "$BUILD_DIR"

# shellcheck source=wasm_renderer/emsdk_env_locate.sh
source "$SCRIPT_DIR/emsdk_env_locate.sh"
if ! command -v emcc &>/dev/null; then
  echo "emcc not found — source emsdk_env.sh first"
  exit 1
fi

export EM_CACHE="${EM_CACHE:-/tmp/emscripten_cache}"
unset EMCC_CFLAGS

EXPORTED="$(node "$REPO_ROOT/scripts/format-wasm-exports.js" functions)"
RUNTIME_METHODS="$(node "$REPO_ROOT/scripts/format-wasm-exports.js" runtime)"
mapfile -t COMPILE_FLAGS < <(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" args)
SOURCES=()
while IFS= read -r src; do SOURCES+=("$SCRIPT_DIR/$src"); done \
  < <(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" sources)

# name -> extra flags. Later flags win in emcc, so these override the contract.
declare -A VARIANTS=(
  [baseline]=""
  [no-exceptions-rtti]="-fno-exceptions -fno-rtti"
  [no-exceptions]="-fno-exceptions"
  [no-rtti]="-fno-rtti"
  [env-web]="-sENVIRONMENT=web"
  [env-web-worker]="-sENVIRONMENT=web,worker"
  [closure1]="--closure 1"
  [asyncify-imports]="-sASYNCIFY_IMPORTS=emwgpuWaitAny"
  [asyncify-ignore-indirect]="-sASYNCIFY_IGNORE_INDIRECT"
)
ORDER=(baseline no-exceptions-rtti no-exceptions no-rtti env-web env-web-worker closure1 asyncify-imports asyncify-ignore-indirect)
if [ "$#" -gt 0 ]; then ORDER=("$@"); fi

echo "emcc: $(emcc -v 2>&1 | head -1)" >&2
echo
echo "| Variant | .wasm bytes | .js bytes | Status |"
echo "|---------|------------:|----------:|--------|"
for name in "${ORDER[@]}"; do
  if [ -z "${VARIANTS[$name]+x}" ]; then echo "unknown variant: $name" >&2; exit 1; fi
  out="$BUILD_DIR/$name.js"
  rm -f "$BUILD_DIR/$name".{js,wasm}
  # shellcheck disable=SC2086 — the variant string is a flag list
  if em++ "${COMPILE_FLAGS[@]}" ${VARIANTS[$name]} "${SOURCES[@]}" "-I$SCRIPT_DIR" \
       -sEXPORTED_FUNCTIONS="${EXPORTED}" -sEXPORTED_RUNTIME_METHODS="${RUNTIME_METHODS}" \
       -o "$out" >"$BUILD_DIR/$name.log" 2>&1; then
    echo "| \`${name}\` | $(wc -c <"$BUILD_DIR/$name.wasm") | $(wc -c <"$out") | built |"
  else
    echo "| \`${name}\` | — | — | failed: $(grep -m1 -E 'error|Error' "$BUILD_DIR/$name.log" | cut -c1-90 | tr '|' '/') |"
  fi
done
