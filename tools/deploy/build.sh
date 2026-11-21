#!/bin/bash
set -euo pipefail
# Deploy build wrapper: production build + DreamHost .htaccess. Run from anywhere.
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "=== Building image_video_effects ==="

# Run the full app build (shader lists, manifest; committed WASM unless BUILD_WASM=1)
npm run build

# build/.htaccess (COOP/COEP, caching, SPA fallback) comes from public/.htaccess,
# which Vite copies on every build, so deploy:full / deploy:preview get it too.
test -f build/.htaccess || { echo "❌ build/.htaccess missing (public/.htaccess not copied)"; exit 1; }
echo "=== Build complete! Run 'python3 tools/deploy/deploy.py' to deploy ==="
