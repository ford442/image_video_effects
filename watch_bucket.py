#!/usr/bin/env python3
"""
Watch Google Cloud Storage bucket for changes and update manifests.

Usage:
    python watch_bucket.py              # One-time sync
    python watch_bucket.py --watch      # Watch mode (polls every 30s)
    python watch_bucket.py --daemon     # Run as background service

Environment Variables:
    GCS_BUCKET:         GCS bucket name (default: my-sd35-space-images-2025)
    GOOGLE_APPLICATION_CREDENTIALS: Path to service account key file (optional)
"""

import json
import os
import sys
import time
import argparse
import hashlib
from pathlib import Path
from typing import List, Dict, Set, Tuple
from datetime import datetime

# Try to use google-cloud-storage, fallback to public XML API
try:
    from google.cloud import storage
    from google.auth import AnonymousCredentials
    import google.auth
    HAS_GCS_LIBRARY = True
except ImportError:
    HAS_GCS_LIBRARY = False
    import urllib.request
    import xml.etree.ElementTree as ET

# --- CONFIGURATION ---
DEFAULT_BUCKET = os.getenv('GCS_BUCKET', 'my-sd35-space-images-2025')
PROJECT_ID = os.getenv('GCS_PROJECT', 'sanguine-medley-204807')

IMAGE_PREFIX = os.getenv('GCS_IMAGE_PREFIX', 'stablediff')
VIDEO_PREFIX = os.getenv('GCS_VIDEO_PREFIX', 'video')

PUBLIC_DIR = Path('public')
MANIFEST_PATH = PUBLIC_DIR / 'image_manifest.json'
VIDEO_MANIFEST_PATH = PUBLIC_DIR / 'video_manifest.json'

# File extensions
IMAGE_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}
VIDEO_EXTENSIONS = {'.mp4', '.webm', '.mov', '.mkv', '.avi'}

# Polling interval in watch mode
POLL_INTERVAL = int(os.getenv('GCS_POLL_INTERVAL', '30'))

# Cache for detecting changes
_last_manifest_hash: str = ""


def log(message: str):
    """Print with timestamp."""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}")


def get_public_gcs_url(bucket: str, blob_name: str) -> str:
    """Generate public GCS URL for a blob."""
    return f"https://storage.googleapis.com/{bucket}/{blob_name}"


import urllib.request
import xml.etree.ElementTree as ET

def list_blobs_public(bucket: str, prefix: str) -> List[Dict]:
    """List all blobs under prefix using public GCS XML API."""
    results = []
    marker = None
    
    while True:
        url = f"https://storage.googleapis.com/{bucket}?prefix={prefix}"
        if marker:
            url += f"&marker={marker}"
        
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                xml_content = response.read()
        except Exception as e:
            log(f"Error fetching bucket listing: {e}")
            break
        
        root = ET.fromstring(xml_content)
        ns = {'gcs': 'http://doc.s3.amazonaws.com/2006-03-01'}
        
        for content in root.findall('.//gcs:Contents', ns):
            key_elem = content.find('gcs:Key', ns)
            if key_elem is None:
                continue
            
            blob_name = key_elem.text
            if not blob_name.startswith(prefix):
                continue
            
            # Check file extension
            ext = Path(blob_name).suffix.lower()
            if ext in IMAGE_EXTENSIONS | VIDEO_EXTENSIONS:
                results.append({
                    "name": Path(blob_name).name,
                    "url": get_public_gcs_url(bucket, blob_name),
                    "size": int(content.find('gcs:Size', ns).text) if content.find('gcs:Size', ns) is not None else 0,
                    "last_modified": content.find('gcs:LastModified', ns).text if content.find('gcs:LastModified', ns) is not None else ""
                })
        
        # Check for more pages
        next_marker = root.find('.//gcs:NextMarker', ns)
        if next_marker is not None:
            marker = next_marker.text
        else:
            break
    
    return results


def list_blobs_gcs_lib(bucket: str, prefix: str) -> List[Dict]:
    """List blobs using google-cloud-storage library."""
    try:
        # Try default credentials first
        credentials, _ = google.auth.default()
    except Exception:
        log("Using anonymous credentials (for public buckets)")
        credentials = AnonymousCredentials()
    
    try:
        client = storage.Client(project=PROJECT_ID, credentials=credentials)
        blobs = client.list_blobs(bucket, prefix=prefix)
    except Exception as e:
        log(f"Error connecting to GCS: {e}")
        return []
    
    results = []
    for blob in blobs:
        if blob.name.endswith('/'):
            continue
        
        ext = Path(blob.name).suffix.lower()
        if ext not in IMAGE_EXTENSIONS and ext not in VIDEO_EXTENSIONS:
            continue
        
        filename = Path(blob.name).name
        name_no_ext = Path(blob.name).stem
        
        tags = name_no_ext.replace('_', ' ').replace('-', ' ').split()
        tags = [t.lower() for t in tags if len(t) > 2 and not t.isdigit()]
        
        results.append({
            "url": get_public_gcs_url(bucket, blob.name),
            "path": blob.name,
            "tags": list(set(tags))
        })
    
    return results


def list_blobs(bucket: str, prefix: str) -> List[Dict]:
    """List blobs using best available method."""
    if HAS_GCS_LIBRARY:
        return list_blobs_gcs_lib(bucket, prefix)
    else:
        log("google-cloud-storage not installed, using public API")
        return list_blobs_public(bucket, prefix)


def compute_manifest_hash(manifest: Dict) -> str:
    """Compute hash of manifest for change detection."""
    content = json.dumps(manifest, sort_keys=True)
    return hashlib.md5(content.encode()).hexdigest()


def save_manifest(images: List[Dict], video: List[Dict]) -> bool:
    """Save manifests and return True if changes were detected."""
    global _last_manifest_hash
    
    # Build combined manifest
    manifest = {
        "images": images,
        "video": video,
        "updated_at": datetime.now().isoformat()
    }
    
    # Check for changes
    current_hash = compute_manifest_hash(manifest)
    if current_hash == _last_manifest_hash:
        return False  # No changes
    
    _last_manifest_hash = current_hash
    
    # Ensure public directory exists
    PUBLIC_DIR.mkdir(exist_ok=True)
    
    # Save combined manifest
    with open(MANIFEST_PATH, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    # Save video-only manifest for backward compatibility
    video_manifest = {
        "video": video,
        "updated_at": datetime.now().isoformat()
    }
    with open(VIDEO_MANIFEST_PATH, 'w') as f:
        json.dump(video_manifest, f, indent=2)
    
    return True


def sync_bucket(bucket: str) -> Tuple[int, int]:
    """Sync bucket contents to manifests. Returns (image_count, video_count)."""
    log(f"Scanning bucket: {bucket}")
    
    images = list_blobs(bucket, IMAGE_PREFIX)
    video = list_blobs(bucket, VIDEO_PREFIX)
    
    log(f"Found {len(images)} images in '{IMAGE_PREFIX}/'")
    log(f"Found {len(video)} video in '{VIDEO_PREFIX}/'")
    
    if save_manifest(images, video):
        log(f"Updated {MANIFEST_PATH} ({len(images)} images, {len(video)} video)")
    else:
        log("No changes detected")
    
    return len(images), len(video)


def watch_mode(bucket: str):
    """Run in watch mode, polling for changes."""
    log(f"Starting watch mode (polling every {POLL_INTERVAL}s)...")
    log("Press Ctrl+C to stop")
    
    try:
        while True:
            sync_bucket(bucket)
            time.sleep(POLL_INTERVAL)
    except KeyboardInterrupt:
        log("Watch mode stopped")


def main():
    global POLL_INTERVAL
    parser = argparse.ArgumentParser(
        description='Watch GCS bucket and update image/video manifests'
    )
    parser.add_argument('--bucket', '-b', default=DEFAULT_BUCKET,
                        help=f'GCS bucket name (default: {DEFAULT_BUCKET})')
    parser.add_argument('--watch', '-w', action='store_true',
                        help=f'Watch mode: poll every {POLL_INTERVAL}s')
    parser.add_argument('--interval', '-i', type=int, default=POLL_INTERVAL,
                        help=f'Polling interval in seconds (default: {POLL_INTERVAL})')
    parser.add_argument('--daemon', '-d', action='store_true',
                        help='Run as daemon (background process)')
    
    args = parser.parse_args()
    
    POLL_INTERVAL = args.interval
    
    if args.daemon:
        # Detach from terminal
        try:
            pid = os.fork()
            if pid > 0:
                log(f"Started daemon (PID: {pid})")
                sys.exit(0)
        except OSError as e:
            log(f"Fork failed: {e}")
            sys.exit(1)
        
        # Redirect stdout/stderr
        sys.stdout.flush()
        sys.stderr.flush()
        
        with open('/dev/null', 'r') as f:
            os.dup2(f.fileno(), sys.stdin.fileno())
        with open('bucket_watcher.log', 'a+') as f:
            os.dup2(f.fileno(), sys.stdout.fileno())
            os.dup2(f.fileno(), sys.stderr.fileno())
    
    if args.watch or args.daemon:
        watch_mode(args.bucket)
    else:
        sync_bucket(args.bucket)


if __name__ == '__main__':
    main()
