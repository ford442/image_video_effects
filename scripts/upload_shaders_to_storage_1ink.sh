#!/usr/bin/env bash
# =============================================================================
# Upload all WGSL shaders from this repo to storage.1ink.us via lftp (SFTP).
#
# This is the RECOMMENDED method for bulk shader sync (much faster + more
# reliable than the Python paramiko version for 1000+ small files).
#
# It uses the exact same lftp + mirror pattern that successfully populates
# https://storage.1ink.us/models/ and https://storage.1ink.us/mods/
#
# Target public URL after upload:
#   https://storage.1ink.us/image-effects/shaders/*.wgsl
#
# Usage:
#   1. Get the correct SFTP credentials for storage.1ink.us (user usually storage_manager)
#   2. export SFTP_PASS='your-real-password-here'
#   3. bash scripts/upload_shaders_to_storage_1ink.sh
#
#   You can override with env vars:
#     SFTP_USER=storage_manager
#     SFTP_HOST=storage.1ink.us
#     SFTP_PORT=22
#     REMOTE_DIR=storage.1ink.us/image-effects/shaders
#
# After success, run the verification curls printed at the end.
# =============================================================================

set -euo pipefail

# --- Configuration (override via environment if needed) ---
SFTP_USER="${SFTP_USER:-storage_manager}"
SFTP_HOST="${SFTP_HOST:-storage.1ink.us}"
SFTP_PORT="${SFTP_PORT:-22}"

# This remote dir + the web server config on storage.1ink.us => public /image-effects/shaders/
REMOTE_DIR="${REMOTE_DIR:-storage.1ink.us/image-effects/shaders}"

# Local source of truth (the 1000+ .wgsl files)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_DIR="${LOCAL_DIR:-$REPO_ROOT/public/shaders}"

# Optional: set to 1 to force re-upload of every file (ignore newer check)
FORCE="${FORCE:-0}"

# --- Sanity checks ---
if [[ -z "${SFTP_PASS:-}" ]]; then
  echo "ERROR: SFTP_PASS environment variable is not set."
  echo ""
  echo "Please run:"
  echo "  export SFTP_PASS='the-password-you-were-given'"
  echo "  bash $0"
  echo ""
  echo "If you have a different username, also set:"
  echo "  export SFTP_USER=the-username"
  exit 1
fi

if ! command -v lftp >/dev/null 2>&1; then
  echo "ERROR: lftp is not installed. Install with:"
  echo "  apt-get update && apt-get install -y lftp"
  exit 1
fi

if [[ ! -d "$LOCAL_DIR" ]]; then
  echo "ERROR: Local shaders directory not found: $LOCAL_DIR"
  echo "Are you running this from inside the image_video_effects checkout?"
  exit 1
fi

count=$(find "$LOCAL_DIR" -maxdepth 1 -name '*.wgsl' | wc -l)
if [[ "$count" -lt 100 ]]; then
  echo "WARNING: Only found $count .wgsl files in $LOCAL_DIR (expected ~1050+)."
  echo "Continuing anyway..."
fi

echo "=============================================================="
echo "🚀  Shader bulk upload to storage.1ink.us (via lftp SFTP)"
echo "=============================================================="
echo "User     : $SFTP_USER"
echo "Host     : $SFTP_HOST:$SFTP_PORT"
echo "Remote   : $REMOTE_DIR"
echo "Local    : $LOCAL_DIR  ($count files)"
echo "Force    : $([[ "$FORCE" == "1" ]] && echo "YES (re-upload everything)" || echo "no (only newer/changed)")"
echo "=============================================================="
echo ""

# Build the lftp script (piped to lftp because -c conflicts with -u in lftp 4.9.x)
lftp_script=$(cat <<LFTPEOF
set sftp:auto-confirm yes
set net:timeout 45
set net:max-retries 6
set net:reconnect-interval-base 5
set cmd:parallel 4
set mirror:parallel-directories 1

open -u "$SFTP_USER,$SFTP_PASS" "sftp://$SFTP_HOST:$SFTP_PORT"

echo "Connected. Creating remote directory if needed..."
mkdir -p "$REMOTE_DIR"

echo "Starting mirror upload (this may take a minute for 1053 files)..."
LFTPEOF
)

if [[ "$FORCE" == "1" ]]; then
  lftp_script+=$'\n'"mirror --reverse --verbose --delete-first $LOCAL_DIR/ $REMOTE_DIR/"
else
  lftp_script+=$'\n'"mirror --reverse --only-newer --verbose $LOCAL_DIR/ $REMOTE_DIR/"
fi

lftp_script+=$'\n'"echo Upload complete."
lftp_script+=$'\n'"quit"

echo "=== Running lftp mirror ==="
echo ""

# Execute via pipe (avoids -c / -u conflict in lftp 4.9.x)
echo "$lftp_script" | lftp 2>&1

echo ""
echo "=============================================================="
echo "✅  Done"
echo "=============================================================="
echo ""
echo "Verify the files are now publicly reachable:"
echo "  curl -I https://storage.1ink.us/image-effects/shaders/liquid.wgsl"
echo "  curl -I https://storage.1ink.us/image-effects/shaders/neon-pulse.wgsl"
echo "  curl -I https://storage.1ink.us/image-effects/shaders/_hash_library.wgsl"
echo ""
echo "If you used a different REMOTE_DIR, adjust the verification URLs above."
echo "=============================================================="
