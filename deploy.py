#!/usr/bin/env python3
"""
Smart deployment script — completely skips the shaders folder.
Only uploads changed files from the rest of the build.
"""

import os
import paramiko
import json
import hashlib
from pathlib import Path

# --- Server Configuration ---
HOSTNAME = "1ink.us"
PORT = 22
USERNAME = "ford442"
PASSWORD = 'GoogleBez12!'   # ← Change to env var later if you want

# --- Project Configuration ---
LOCAL_DIRECTORY = "build"
REMOTE_DIRECTORY = "test.1ink.us/image_video_effects"
MANIFEST_FILE = ".deploy_manifest.json"

# Folders we NEVER upload (big time saver)
IGNORE_DIRS = ["shaders"]

def get_file_hash(filepath: str) -> str:
    hash_md5 = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()

def load_manifest() -> dict:
    if os.path.exists(MANIFEST_FILE):
        with open(MANIFEST_FILE) as f:
            return json.load(f)
    return {}

def save_manifest(manifest: dict):
    with open(MANIFEST_FILE, 'w') as f:
        json.dump(manifest, f, indent=2)

def should_skip(path: str) -> bool:
    return any(ignore in path for ignore in IGNORE_DIRS)

def upload_file(sftp, local_path: str, remote_path: str, manifest: dict):
    print(f"  📤 Uploading: {os.path.basename(local_path)}")
    sftp.put(local_path, remote_path)
    rel_path = os.path.relpath(local_path, LOCAL_DIRECTORY)
    manifest[rel_path] = {'hash': get_file_hash(local_path), 'size': os.path.getsize(local_path)}

def upload_directory(sftp, local_path: str, remote_path: str, manifest: dict, force: bool = False):
    try:
        sftp.mkdir(remote_path)
    except:
        pass

    uploaded = 0
    for item in os.listdir(local_path):
        local_item = os.path.join(local_path, item)
        remote_item = f"{remote_path}/{item}"

        if should_skip(local_item):
            print(f"  ⏭️  Skipping folder: {item}")
            continue

        if os.path.isfile(local_item):
            rel_path = os.path.relpath(local_item, LOCAL_DIRECTORY)
            if not force and rel_path in manifest and manifest[rel_path].get('hash') == get_file_hash(local_item):
                print(f"  ⏭️  Skipped (unchanged): {item}")
                continue
            upload_file(sftp, local_item, remote_item, manifest)
            uploaded += 1

        elif os.path.isdir(local_item):
            uploaded += upload_directory(sftp, local_item, remote_item, manifest, force)

    return uploaded

def main():
    manifest = load_manifest()
    force = '--force' in os.sys.argv

    transport = paramiko.Transport((HOSTNAME, PORT))
    transport.connect(username=USERNAME, password=PASSWORD)
    sftp = paramiko.SFTPClient.from_transport(transport)

    print(f"🚀 Deploying to {REMOTE_DIRECTORY} (skipping shaders folder)...")
    uploaded = upload_directory(sftp, LOCAL_DIRECTORY, REMOTE_DIRECTORY, manifest, force)

    save_manifest(manifest)
    sftp.close()
    transport.close()

    print(f"✅ Deployment complete! Uploaded {uploaded} files.")

if __name__ == "__main__":
    if not os.path.exists(LOCAL_DIRECTORY):
        print("❌ Run 'npm run build' first!")
        exit(1)
    main()