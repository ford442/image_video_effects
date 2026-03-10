#!/bin/bash
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

# Source Emscripten
CANDIDATES=(
    "/content/build_space/emsdk/emsdk_env.sh"
    "$REPO_ROOT/emsdk/emsdk_env.sh"
    "$HOME/emsdk/emsdk_env.sh"
    "/usr/local/emsdk/emsdk_env.sh"
)
for f in "${CANDIDATES[@]}"; do
    if [ -f "$f" ]; then source "$f"; break; fi
done

# Change to script directory
cd "$(dirname "$0")"

# Set writable cache location for TOT emscripten
export EM_CACHE=/tmp/emscripten_cache

# Pre-install the emdawnwebgpu port so CMake can find its headers.
# --use-port at link time won't populate the include dir until after cmake
# configure, so we prime it here using embuilder.
echo "=== Pre-building emdawnwebgpu port ==="
embuilder build emdawnwebgpu 2>&1 | tail -3

# Clean previous build
rm -rf build

# Configure with the modern emdawnwebgpu port
emcmake cmake -B build -S . \
  -DCMAKE_BUILD_TYPE=Release

# Build
emmake make -C build -j$(nproc)

# Copy output to public folder
mkdir -p ../../public/wasm
cp build/pixelocity_wasm.js build/pixelocity_wasm.wasm ../../public/wasm/
cp wasm_bridge.js ../../public/wasm/

echo "✅ WASM build complete! Files in public/wasm/"
echo "   → pixelocity_wasm.js"
echo "   → pixelocity_wasm.wasm"
echo "   → wasm_bridge.js"
