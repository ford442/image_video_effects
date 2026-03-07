#!/bin/bash
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

# Change to script directory
cd "$(dirname "$0")"

# Set writable cache location for TOT emscripten
export EM_CACHE=/tmp/emscripten_cache

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

# Clean previous build
rm -rf build

# Configure with the modern emdawnwebgpu port
emcmake cmake -B build -S . \
  -DDAWN_ENABLE_WGPU=ON \
  -DEMSCRIPTEN_USE_PORTS=emdawnwebgpu \
  -DCMAKE_BUILD_TYPE=Release

# Build
emmake make -C build -j$(nproc)

# Copy output to public folder
mkdir -p ../../public/wasm
cp build/pixelocity_wasm.* ../../public/wasm/

echo "✅ WASM build complete! Files in public/wasm/"
echo "   → pixelocity_wasm.js"
echo "   → pixelocity_wasm.wasm"
