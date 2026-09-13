#!/usr/bin/env bash
# emcc-version-gate.sh — fail if the active emcc does not match the pin in
# src/contracts/wasm_compile_flags.json (emsdkVersion).
#
# The committed glue (public/wasm/pixelocity_wasm.js) is minified and does not
# embed the emcc version, so the gate runs on the toolchain before compiling
# rather than on the artifact. build.sh calls this before em++.
#
# Escape hatch for local experiments only (never CI, never committed artifacts):
#   ALLOW_EMCC_VERSION_MISMATCH=1 npm run wasm:build
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED="$(node "$REPO_ROOT/scripts/format-wasm-compile-flags.js" emsdk)"

if ! command -v emcc &>/dev/null; then
    echo "❌ emcc-version-gate: emcc not found (pin is $PINNED)"
    exit 1
fi

# First line looks like: emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 6.0.3 (<hash>)
ACTUAL="$(emcc -v 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

if [ "$ACTUAL" = "$PINNED" ]; then
    echo "✅ emcc $ACTUAL matches pin"
    exit 0
fi

echo "❌ emcc-version-gate: active emcc is '${ACTUAL:-unknown}', pin is '$PINNED'"
echo "   Install the pin:  ./emsdk install $PINNED && ./emsdk activate $PINNED"
echo "   Pin lives in src/contracts/wasm_compile_flags.json (emsdkVersion)."
if [ "${ALLOW_EMCC_VERSION_MISMATCH:-}" = "1" ]; then
    echo "   ALLOW_EMCC_VERSION_MISMATCH=1 — continuing. Do NOT commit these artifacts."
    exit 0
fi
exit 1
