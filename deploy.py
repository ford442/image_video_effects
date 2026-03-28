#!/usr/bin/env python3
"""
Smart deployment script - only uploads changed files.
Uses a local manifest to track uploaded file hashes.
"""

import os
import paramiko
import getpass
import json
import hashlib
from pathlib import Path

# --- Server Configuration ---
HOSTNAME = "1ink.us"
PORT = 22
USERNAME = "ford442"

# --- Project Configuration ---
LOCAL_DIRECTORY = "build"
REMOTE_DIRECTORY = "test.1ink.us/image_video_effects"
MANIFEST_FILE = ".deploy_manifest.json"

# File patterns to skip (e.g., source maps if not needed)
SKIP_PATTERNS = [
    # '*.map',  # Uncomment to skip source maps
]

# Critical files that should never be removed from remote
PROTECTED_FILES = ['index.html']


def get_file_hash(filepath: str) -> str:
    """Calculate MD5 hash of a file."""
    hash_md5 = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def load_manifest() -> dict:
    """Load the deployment manifest tracking uploaded files."""
    if os.path.exists(MANIFEST_FILE):
        with open(MANIFEST_FILE, 'r') as f:
            return json.load(f)
    return {}


def save_manifest(manifest: dict):
    """Save the deployment manifest."""
    with open(MANIFEST_FILE, 'w') as f:
        json.dump(manifest, f, indent=2)


def should_upload(local_path: str, remote_path: str, sftp_client, manifest: dict) -> bool:
    """
    Determine if a file should be uploaded by checking:
    1. If it's in the skip list
    2. If it exists remotely
    3. If local hash differs from manifest
    """
    # Check skip patterns
    for pattern in SKIP_PATTERNS:
        if local_path.endswith(pattern.replace('*', '')):
            return False

    rel_path = os.path.relpath(local_path, LOCAL_DIRECTORY)
    local_hash = get_file_hash(local_path)
    local_size = os.path.getsize(local_path)

    # Check manifest first (fast local check)
    if rel_path in manifest:
        if manifest[rel_path].get('hash') == local_hash:
            return False  # File unchanged

    # Check remote file
    try:
        remote_stat = sftp_client.stat(remote_path)
        # If sizes match, assume file is same (fast but not 100% accurate)
        if remote_stat.st_size == local_size:
            # Optionally: verify with hash (slower but accurate)
            # For now, size match is good enough for most cases
            return False
    except IOError:
        # File doesn't exist remotely - must upload
        pass

    return True


def upload_file(sftp_client, local_path: str, remote_path: str, manifest: dict):
    """Upload a single file and update manifest."""
    print(f"  📤 Uploading: {os.path.basename(local_path)}")
    sftp_client.put(local_path, remote_path)

    # Update manifest
    rel_path = os.path.relpath(local_path, LOCAL_DIRECTORY)
    manifest[rel_path] = {
        'hash': get_file_hash(local_path),
        'size': os.path.getsize(local_path)
    }


def upload_directory(sftp_client, local_path: str, remote_path: str, manifest: dict, force: bool = False):
    """
    Recursively uploads only changed files.
    """
    # Create remote directory if it doesn't exist
    try:
        sftp_client.mkdir(remote_path)
        print(f"📁 Created directory: {remote_path}")
    except IOError:
        pass  # Directory already exists

    uploaded_count = 0
    skipped_count = 0

    for item in os.listdir(local_path):
        local_item_path = os.path.join(local_path, item)
        remote_item_path = f"{remote_path}/{item}"
        rel_path = os.path.relpath(local_item_path, LOCAL_DIRECTORY)

        if os.path.isfile(local_item_path):
            if force or should_upload(local_item_path, remote_item_path, sftp_client, manifest):
                upload_file(sftp_client, local_item_path, remote_item_path, manifest)
                uploaded_count += 1
            else:
                skipped_count += 1
                print(f"  ⏭️  Skipped: {item}")

        elif os.path.isdir(local_item_path):
            # Recurse into subdirectory
            sub_uploaded, sub_skipped = upload_directory(
                sftp_client, local_item_path, remote_item_path, manifest, force
            )
            uploaded_count += sub_uploaded
            skipped_count += sub_skipped

    return uploaded_count, skipped_count


def clean_remote(sftp_client, remote_path: str, manifest: dict):
    """
    Remove files from remote that no longer exist locally.
    Protected files (like index.html) are never removed.
    """
    removed = []
    local_files = set()

    # Build set of local files
    for root, _, files in os.walk(LOCAL_DIRECTORY):
        for f in files:
            local_files.add(os.path.relpath(os.path.join(root, f), LOCAL_DIRECTORY))

    # Check manifest for files that no longer exist locally
    to_remove = []
    for rel_path in manifest.keys():
        if rel_path not in local_files:
            # Skip protected files
            if rel_path in PROTECTED_FILES:
                print(f"  🛡️  Protected: {rel_path} (skipping removal)")
                continue
            to_remove.append(rel_path)

    for rel_path in to_remove:
        remote_file = f"{REMOTE_DIRECTORY}/{rel_path}"
        try:
            sftp_client.remove(remote_file)
            removed.append(rel_path)
            del manifest[rel_path]
            print(f"  🗑️  Removed: {rel_path}")
        except IOError:
            pass  # File didn't exist anyway

    return removed


def main():
    password = 'GoogleBez12!'  # Consider using environment variable

    # Load manifest
    manifest = load_manifest()
    print(f"📋 Loaded manifest with {len(manifest)} tracked files")

    transport = None
    sftp = None
    try:
        # Establish SSH connection
        transport = paramiko.Transport((HOSTNAME, PORT))
        print(f"🔌 Connecting to {HOSTNAME}...")
        transport.connect(username=USERNAME, password=password)
        print("✅ Connected!")

        sftp = paramiko.SFTPClient.from_transport(transport)
        print(f"🚀 Deploying '{LOCAL_DIRECTORY}' to '{REMOTE_DIRECTORY}'...")
        print("")

        # Upload changed files
        uploaded, skipped = upload_directory(sftp, LOCAL_DIRECTORY, REMOTE_DIRECTORY, manifest)

        # Clean up removed files
        print("")
        print("🧹 Cleaning up removed files...")
        removed = clean_remote(sftp, REMOTE_DIRECTORY, manifest)

        # Save updated manifest
        save_manifest(manifest)

        print("")
        print("=" * 50)
        print(f"✅ Deployment complete!")
        print(f"   📤 Uploaded: {uploaded} files")
        print(f"   ⏭️  Skipped: {skipped} files (unchanged)")
        if removed:
            print(f"   🗑️  Removed: {len(removed)} files")
        print("=" * 50)

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if sftp:
            sftp.close()
        if transport:
            transport.close()
        print("🔒 Connection closed.")


if __name__ == "__main__":
    if not os.path.exists(LOCAL_DIRECTORY):
        print(f"❌ Error: Directory '{LOCAL_DIRECTORY}' not found. Run 'npm run build' first.")
        exit(1)

    # Optional: Force full redeploy
    import sys
    force_redeploy = '--force' in sys.argv

    if force_redeploy:
        print("⚠️  Force redeploy: Will upload ALL files")
        if input("Continue? (yes/no): ").lower() != 'yes':
            exit(0)
        # Clear manifest to force re-upload
        manifest = {}
    else:
        print("💡 Tip: Use --force to redeploy all files")
        print("")

    main()
