import json
import os
from google.cloud import storage

# --- CONFIGURATION ---
# Replace with the output from 'gcloud config get-value project'
PROJECT_ID = 'sanguine-medley-204807'

# Replace with your actual bucket name
BUCKET_NAME = 'my-sd35-space-images-2025'

# Folders to scan
IMAGE_PREFIX = 'stablediff' # Images folder
VIDEO_PREFIX = 'video'      # New video folder

# Path to your manifest file
MANIFEST_PATH = 'public/image_manifest.json'
# ---------------------

def list_blobs(bucket_name, prefix, extensions):
    """Lists blobs in a bucket with specific extensions."""
    storage_client = storage.Client(project=PROJECT_ID)
    blobs = storage_client.list_blobs(bucket_name, prefix=prefix)

    results = []
    for blob in blobs:
        if blob.name.endswith('/'): continue # Skip folders

        # Check extension
        ext = os.path.splitext(blob.name)[1].lower()
        if ext in extensions:
            # Generate tags from filename
            filename = os.path.basename(blob.name)
            name_no_ext = os.path.splitext(filename)[0]
            # Split by underscores, dashes, or spaces
            tags = name_no_ext.replace('_', ' ').replace('-', ' ').split()
            # Clean tags
            tags = [t for t in tags if len(t) > 2 and not t.isdigit()]

            results.append({
                "url": blob.name, # Store relative path (e.g. video/myvid.mp4)
                "tags": tags
            })

    return results

def main():
    print(f"Scanning bucket: {BUCKET_NAME}...")

    # 1. Fetch Images (png, jpg, jpeg, webp)
    images = list_blobs(BUCKET_NAME, IMAGE_PREFIX, ['.png', '.jpg', '.jpeg', '.webp'])
    print(f"Found {len(images)} images in '{IMAGE_PREFIX}/'")

    # 2. Fetch Videos (mp4, webm, mov)
    videos = list_blobs(BUCKET_NAME, VIDEO_PREFIX, ['.mp4', '.webm', '.mov'])
    print(f"Found {len(videos)} videos in '{VIDEO_PREFIX}/'")

    # 3. Build Manifest
    manifest = {
        "images": images,
        "videos": videos
    }

    # 4. Save to JSON
    try:
        with open(MANIFEST_PATH, 'w') as f:
            json.dump(manifest, f, indent=2)
        print(f"Successfully saved manifest to {MANIFEST_PATH}")
    except Exception as e:
        print(f"Error saving manifest: {e}")

if __name__ == '__main__':
    main()
