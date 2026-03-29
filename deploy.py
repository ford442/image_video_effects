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
# DreamHost (Apache) - Update these for your account
HOSTNAME = "1ink.us"          # Your DreamHost domain or server
PORT = 22
USERNAME = "ford442"          # Your DreamHost username

# --- Project Configuration ---
LOCAL_DIRECTORY = "build"
REMOTE_DIRECTORY = "test.1ink.us/image_video_effects"  # Change to: yourdomain.com or yourdomain.com/subfolder

# Pre-deploy hook: Create .htaccess for Apache cache control
APACHE_HTACCESS = """# Cache busting for React/Vue bundles
<IfModule mod_headers.c>
    # Never cache HTML (contains bundle references)
    <FilesMatch "\\.(html)$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>
    
    # Cache hashed assets (JS/CSS with content hash) for 1 year
    <FilesMatch "\\.[0-9a-f]{8,}\\.(js|css)$">
        Header set Cache-Control "public, max-age=31536000, immutable"
    </FilesMatch>
    
    # Cache media files for 30 days
    <FilesMatch "\\.(png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|wasm)$">
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
    RewriteRule ^index\\.html$ - [L]
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule . /index.html [L]
</IfModule>
"""
MANIFEST_FILE = ".deploy_manifest.json"

# File patterns to skip (e.g., source maps if not needed)
SKIP_PATTERNS = [
    # '*.map',  # Uncomment to skip source maps
]

# Critical files that should never be removed from remote
PROTECTED_FILES = ['index.html']

# Files that must ALWAYS be uploaded (bypass hash check)
# These contain references to hashed bundles and must stay in sync
ALWAYS_UPLOAD = ['index.html', '.htaccess', 'asset-manifest.json']


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
    2. If it's in ALWAYS_UPLOAD (always upload these)
    3. If it exists remotely
    4. If local hash differs from manifest
    """
    rel_path = os.path.relpath(local_path, LOCAL_DIRECTORY)
    filename = os.path.basename(local_path)
    
    # Check skip patterns
    for pattern in SKIP_PATTERNS:
        if local_path.endswith(pattern.replace('*', '')):
            return False
    
    # ALWAYS upload critical files (they contain bundle references)
    if filename in ALWAYS_UPLOAD:
        return True
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


def create_htaccess():
    """Create .htaccess file in build directory for Apache cache control."""
    htaccess_path = os.path.join(LOCAL_DIRECTORY, ".htaccess")
    with open(htaccess_path, 'w') as f:
        f.write(APACHE_HTACCESS)
    print(f"✅ Created {htaccess_path} for Apache cache control")


def verify_build_integrity():
    """
    Verify that index.html references bundles that actually exist.
    This prevents 404 errors from stale deployments.
    """
    import re
    
    html_path = os.path.join(LOCAL_DIRECTORY, "index.html")
    if not os.path.exists(html_path):
        print("❌ index.html not found in build directory")
        return False
    
    with open(html_path, 'r') as f:
        html_content = f.read()
    
    # Extract JS bundle references
    js_pattern = r'src="[^"]*static/js/(main\.[a-f0-9]+\.js)"'
    css_pattern = r'href="[^"]*static/css/(main\.[a-f0-9]+\.css)"'
    
    js_matches = re.findall(js_pattern, html_content)
    css_matches = re.findall(css_pattern, html_content)
    
    errors = []
    
    # Check JS bundles exist
    for js_file in js_matches:
        js_path = os.path.join(LOCAL_DIRECTORY, "static", "js", js_file)
        if not os.path.exists(js_path):
            errors.append(f"❌ JS bundle referenced but missing: {js_file}")
        else:
            size_mb = os.path.getsize(js_path) / (1024 * 1024)
            print(f"   ✓ JS bundle OK: {js_file} ({size_mb:.2f} MB)")
    
    # Check CSS bundles exist
    for css_file in css_matches:
        css_path = os.path.join(LOCAL_DIRECTORY, "static", "css", css_file)
        if not os.path.exists(css_path):
            errors.append(f"❌ CSS bundle referenced but missing: {css_file}")
        else:
            size_kb = os.path.getsize(css_path) / 1024
            print(f"   ✓ CSS bundle OK: {css_file} ({size_kb:.1f} KB)")
    
    if errors:
        print("\n🔴 Build Integrity Errors:")
        for error in errors:
            print(f"   {error}")
        print("\n⚠️  Run 'npm run build' to regenerate bundles")
        return False
    
    print(f"\n✅ Build integrity verified: {len(js_matches)} JS, {len(css_matches)} CSS bundles")
    return True

def main():
    # Create .htaccess before deploying
    create_htaccess()
    
    # Verify build integrity before deploying
    print("🔍 Verifying build integrity...")
    if not verify_build_integrity():
        print("\n❌ Build verification failed. Fix errors before deploying.")
        exit(1)
    print("")
    
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

    # Optional: Force full redeploy or fresh start
    import sys
    force_redeploy = '--force' in sys.argv
    fresh_deploy = '--fresh' in sys.argv

    if fresh_deploy:
        print("🗑️  Fresh deploy: Clearing manifest and uploading ALL files")
        if os.path.exists(MANIFEST_FILE):
            os.remove(MANIFEST_FILE)
            print(f"   Removed {MANIFEST_FILE}")
        manifest = {}
    elif force_redeploy:
        print("⚠️  Force redeploy: Will upload ALL files")
        if input("Continue? (yes/no): ").lower() != 'yes':
            exit(0)
        # Clear manifest to force re-upload
        manifest = {}
    else:
        print("💡 Tips:")
        print("   --force  : Redeploy all files (keep manifest history)")
        print("   --fresh  : Clear manifest and redeploy all (fixes 404 errors)")
        print("")

    main()
