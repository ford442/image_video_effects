#!/bin/bash
echo "=== Building Pixelocity WASM Renderer (2026 version) ==="

# Set writable cache location for TOT emscripten
export EM_CACHE=/tmp/emscripten_cache

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
