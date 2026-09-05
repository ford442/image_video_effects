#!/bin/bash
# TypeScript WASM bridge source of truth is src/wasm/bridge/*.ts
# (webpack compiles src/wasm/wasm_bridge.ts).
# This script emits ESM copies to wasm_renderer/ and public/wasm/.
# Editing wasm_renderer/bridge/*.js or public/wasm/bridge/*.js is a no-op —
# the next wasm:build overwrites them from src/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

node "$REPO_ROOT/scripts/emit-wasm-bridge.mjs"
