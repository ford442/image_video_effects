#!/bin/bash
set -euo pipefail

echo "=== Building image_video_effects ==="

# Run the full React/WASM build (includes wasm:build, shader lists, manifest)
npm run build

# Generate .htaccess for Apache cache control (required for DreamHost deployment)
HTACCESS="build/.htaccess"
cat > "$HTACCESS" << 'HTACCESS_EOF'
# Cross-origin isolation (#1314): lets the page share memory (SharedArrayBuffer)
# with the render worker. credentialless (not require-corp) keeps no-cors
# cross-origin images (gallery thumbnails on other hosts) loading. Applied to
# every response, so the worker script carries it too. Safari ignores
# credentialless: it stays non-isolated and the worker falls back to postMessage.
<IfModule mod_headers.c>
    Header always set Cross-Origin-Opener-Policy "same-origin"
    Header always set Cross-Origin-Embedder-Policy "credentialless"
</IfModule>

# Cache busting for React/Vue bundles
<IfModule mod_headers.c>
    # Never cache HTML (contains bundle references)
    <FilesMatch "\.(html)$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>

    # Cache hashed assets (JS/CSS with content hash) for 1 year
    <FilesMatch "\.[0-9a-f]{8,}\.(js|css)$">
        Header set Cache-Control "public, max-age=31536000, immutable"
    </FilesMatch>

    # Cache media files for 30 days
    <FilesMatch "\.(png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|wasm)$">
        Header set Cache-Control "public, max-age=2592000"
    </FilesMatch>
</IfModule>

# Enable gzip compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/css application/javascript application/json application/wasm
</IfModule>

# Handle client-side routing (React Router)
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    RewriteRule ^index\.html$ - [L]
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule . /index.html [L]
</IfModule>
HTACCESS_EOF

echo "✅ Generated $HTACCESS"
echo "=== Build complete! Run 'python3 tools/deploy/deploy.py' to deploy ==="
