#!/usr/bin/env python3
"""
App-only deployment script — uploads the React bundle to DreamHost via SFTP
WITHOUT the shaders directory.

Shaders should be synced separately via:
    python scripts/sync_shaders_to_storage.py

This avoids the SFTP connection drops caused by uploading 1000+ individual
WGSL files. Only ~20-50 core app files (JS, CSS, HTML, manifests) are
uploaded, which is fast and reliable.

Usage:
    python scripts/deploy_app_only.py
    python scripts/deploy_app_only.py --force     # re-upload all app files
    python scripts/deploy_app_only.py --fresh     # clear manifest & redeploy
"""

import os
import sys
import json
import hashlib
from pathlib import Path

# Use paramiko if available; otherwise suggest installation
try:
    import paramiko
except ImportError:
    print("❌  paramiko is required. Install it with:  pip install paramiko")
    sys.exit(1)

# ── Configuration ────────────────────────────────────────────────────────────

HOSTNAME = os.environ.get("DEPLOY_HOST", "1ink.us")
PORT = int(os.environ.get("DEPLOY_PORT", "22"))
USERNAME = os.environ.get("DEPLOY_USER", "ford442")
# Read password from env var or prompt (avoids hardcoding)
PASSWORD = os.environ.get("DEPLOY_PASS", "GoogleBez12!")

LOCAL_DIRECTORY = "build"
REMOTE_DIRECTORY = "test.1ink.us/image_video_effects"

MANIFEST_FILE = ".deploy_app_manifest.json"

# Directories to skip entirely (shaders are synced via storage manager)
SKIP_DIRS = {"shaders"}

# Critical files that must ALWAYS be uploaded
ALWAYS_UPLOAD = {"index.html", ".htaccess", "asset-manifest.json"}

# ── Helpers ──────────────────────────────────────────────────────────────────


def get_file_hash(filepath: str) -> str:
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest() -> dict:
    if os.path.exists(MANIFEST_FILE):
        with open(MANIFEST_FILE, "r") as f:
            return json.load(f)
    return {}


def save_manifest(manifest: dict):
    with open(MANIFEST_FILE, "w") as f:
        json.dump(manifest, f, indent=2)


def should_upload(local_path: str, manifest: dict) -> bool:
    filename = os.path.basename(local_path)
    if filename in ALWAYS_UPLOAD:
        return True
    local_hash = get_file_hash(local_path)
    rel_path = os.path.relpath(local_path, LOCAL_DIRECTORY)
    if rel_path in manifest and manifest[rel_path].get("hash") == local_hash:
        return False
    return True


def upload_file(sftp, local_path: str, remote_path: str, manifest: dict):
    sftp.put(local_path, remote_path)
    rel_path = os.path.relpath(local_path, LOCAL_DIRECTORY)
    manifest[rel_path] = {
        "hash": get_file_hash(local_path),
        "size": os.path.getsize(local_path),
    }


def upload_directory(sftp, local_path: str, remote_path: str, manifest: dict):
    try:
        sftp.mkdir(remote_path)
    except IOError:
        pass

    uploaded = 0
    skipped = 0

    for item in sorted(os.listdir(local_path)):
        # Skip shader directory entirely
        if item in SKIP_DIRS:
            print(f"  ⏭️  Skipping directory: {item}/")
            continue

        local_item = os.path.join(local_path, item)
        remote_item = f"{remote_path}/{item}"
        rel_path = os.path.relpath(local_item, LOCAL_DIRECTORY)

        if os.path.isfile(local_item):
            if should_upload(local_item, manifest):
                print(f"  📤 {rel_path}")
                upload_file(sftp, local_item, remote_item, manifest)
                uploaded += 1
            else:
                skipped += 1
                print(f"  ⏭️  {rel_path}")

        elif os.path.isdir(local_item):
            sub_up, sub_sk = upload_directory(sftp, local_item, remote_item, manifest)
            uploaded += sub_up
            skipped += sub_sk

    return uploaded, skipped


def verify_build() -> bool:
    html_path = Path(LOCAL_DIRECTORY) / "index.html"
    if not html_path.exists():
        print("❌  index.html not found. Run 'npm run build' first.")
        return False
    return True


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    if not verify_build():
        sys.exit(1)

    force = "--force" in sys.argv
    fresh = "--fresh" in sys.argv

    manifest = load_manifest()

    if fresh:
        print("🗑️  Fresh deploy requested — clearing manifest")
        if Path(MANIFEST_FILE).exists():
            Path(MANIFEST_FILE).unlink()
        manifest = {}
    elif force:
        print("⚠️  Force redeploy — uploading all app files")
        manifest = {}

    password = PASSWORD
    if not password:
        import getpass
        password = getpass.getpass(f"Password for {USERNAME}@{HOSTNAME}: ")

    transport = None
    sftp = None

    try:
        print(f"🔌  Connecting to {HOSTNAME}...")
        transport = paramiko.Transport((HOSTNAME, PORT))
        transport.connect(username=USERNAME, password=password)
        print("✅  Connected!\n")

        sftp = paramiko.SFTPClient.from_transport(transport)

        print(f"🚀  Deploying app bundle (shaders excluded)")
        print(f"    Local:  {LOCAL_DIRECTORY}")
        print(f"    Remote: {REMOTE_DIRECTORY}\n")

        uploaded, skipped = upload_directory(sftp, LOCAL_DIRECTORY, REMOTE_DIRECTORY, manifest)

        save_manifest(manifest)

        print()
        print("=" * 50)
        print("✅  App deployment complete!")
        print(f"   📤 Uploaded: {uploaded} files")
        print(f"   ⏭️  Skipped:  {skipped} files (unchanged)")
        print("=" * 50)
        print()
        print("💡  Next step: sync shaders to storage manager")
        print("    python scripts/sync_shaders_to_storage.py")

    except Exception as e:
        print(f"\n❌  Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if sftp:
            sftp.close()
        if transport:
            transport.close()
        print("\n🔒  Connection closed.")


if __name__ == "__main__":
    main()
