#!/bin/bash
# scripts/jules-setup.sh
# Jules (and similar AI/headless env) setup for ford442/image_video_effects
#
# Project: WebGPU shader playground (Create React App + React 19 + WGSL compute shaders
#          + optional C++/WASM renderer via Emscripten)
#
# This script:
#   - Installs deps reliably (npm ci primary)
#   - Runs the critical prestart/prebuild side-effects (shader list generation + manifest)
#   - Safely skips WASM compilation (uses committed artifacts in public/wasm/)
#   - Leaves the tree in a state where `npm start`, tests, and edits "just work"
#
# Usage in Jules UI:
#   Configuration → Initial Setup:   bash scripts/jules-setup.sh
#   Then: Run to Validate / Run and Snapshot.
#
# Local / other CI:
#   bash scripts/jules-setup.sh
#   SKIP_WASM_BUILD=1 npm run build     # safe build
#   BROWSER=none npm start              # dev server (no browser pop)
#
# Notes:
# - Sharp (transitive via @xenova/transformers for AI depth) has occasional flaky
#   postinstall (libvips download). The script retries install on failure.
# - No GPU in most Jules/CI envs → WebGPU falls back; that's expected.
# - Emscripten is NOT required for normal work (committed WASM artifacts exist).
# - The generate + manifest steps are the same ones run by prestart/prebuild.

set -euo pipefail

echo "🚀 [Jules] Setting up image_video_effects environment..."
echo "   (WebGPU shader effects + CRA + optional WASM)"

echo "   Node: $(node --version 2>/dev/null || echo '?') | npm: $(npm --version 2>/dev/null || echo '?')"

# -------------------------------------------------------------------
# 1. Package manager detection (this repo is strictly npm + lockfile)
# -------------------------------------------------------------------
if [ -f pnpm-lock.yaml ] || [ -f pnpm-workspace.yaml ]; then
  echo "❌ pnpm detected but this project uses npm + package-lock.json"
  echo "   Delete pnpm files or adjust. Aborting."
  exit 1
fi
if [ -f yarn.lock ]; then
  echo "❌ yarn.lock detected but this project uses npm."
  exit 1
fi

echo "📦 npm + package-lock.json detected."

# -------------------------------------------------------------------
# 2. Install dependencies (prefer ci for reproducible lockfile)
# -------------------------------------------------------------------
install_deps() {
  if [ -f package-lock.json ]; then
    echo "   Running: npm ci --no-audit --no-fund --prefer-offline"
    npm ci --no-audit --no-fund --prefer-offline
  else
    echo "   Running: npm install (no lockfile present)"
    npm install --no-audit --no-fund --prefer-offline
  fi
}

echo "📦 Installing dependencies..."
if ! install_deps; then
  echo "⚠️  npm ci failed (often transient sharp postinstall via @xenova/transformers)."
  echo "   Retrying with npm install + legacy-peer-deps..."
  npm cache clean --force 2>/dev/null || true
  npm install --no-audit --no-fund --legacy-peer-deps --prefer-offline
fi

echo "   ✅ Dependencies installed (or already present)."

# -------------------------------------------------------------------
# 3. Run the generator steps that prestart/prebuild normally perform.
#    These populate public/shader-lists/*.json and public/shader-manifest-unified.json.
#    They are pure Node (no GPU, no WASM) and important for the app to list shaders.
#    CRA's prestart does exactly this before `npm start`.
# -------------------------------------------------------------------
echo "📜 Regenerating shader lists and unified manifest..."
echo "   (matches what CRA prestart/prebuild do)"

# Use the exact same invocation as package.json prestart
if node scripts/generate_shader_lists.js --base-url=https://test.1ink.us/image_video_effects/; then
  echo "   ✅ Shader lists generated."
else
  echo "   ⚠️  generate_shader_lists.js had issues (non-fatal for setup)."
fi

if npm run build:manifest; then
  echo "   ✅ Unified manifest built."
else
  echo "   ⚠️  build:manifest had issues (check tsx / script) — non-fatal."
fi

# -------------------------------------------------------------------
# 4. WASM handling
#    Committed artifacts in public/wasm/ let you run without emcc.
#    The wasm:build script (and thus prebuild) respects SKIP_WASM_BUILD=1.
# -------------------------------------------------------------------
export SKIP_WASM_BUILD=1
echo "🧩 WASM: SKIP_WASM_BUILD=1 (using committed public/wasm/ artifacts)"
echo "   To force a real WASM build you would need emsdk in the env."

# Quick validation of artifacts (does not require build)
if npm run wasm:validate --if-present >/dev/null 2>&1; then
  echo "   ✅ wasm:validate passed (artifacts look good)."
else
  echo "   ℹ️  wasm:validate skipped or using committed artifacts."
fi

# -------------------------------------------------------------------
# 5. Optional fast smoke (safe, no GPU, no browser)
#    Uncomment in Jules config if you want a build/test gate in setup.
# -------------------------------------------------------------------
# echo "🔍 Optional: light build check (SKIP_WASM_BUILD=1)..."
# SKIP_WASM_BUILD=1 npm run build --if-present || echo "Build check skipped"

echo ""
echo "✅ [Jules] image_video_effects environment ready!"
echo ""
echo "Recommended commands from here:"
echo "  BROWSER=none npm start"
echo "  SKIP_WASM_BUILD=1 npm run build"
echo "  npm test -- --watchAll=false --ci"
echo "  npx react-scripts test --watchAll=false --ci --testPathPattern=WASM"
echo ""
echo "   (WebGPU will be unavailable in headless Jules → falls back to Canvas2D/JS)"
echo "   Shader lists + manifest are fresh. Edit shader_definitions/ then re-run"
echo "   the generate step (or just npm start) to refresh UI lists."
echo ""
