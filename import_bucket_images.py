import json
import os
from google.cloud import storage

# --- CONFIGURATION ---
# Replace with the output from 'gcloud config get-value project'
PROJECT_ID = 'sanguine-medley-204807'

# Replace with your actual bucket name
BUCKET_NAME = 'my-sd35-space-images-2025'

# Optional: If your images are in a subfolder, specify it here (e.g., 'portfolio/').
# Leave empty '' if they are at the root of the bucket.
PREFIX = 'stablediff'

# Path to your manifest file
MANIFEST_PATH = 'public/image_manifest.json'
# ---------------------

def list_blobs(bucket_name, prefix):
    """Lists all the blobs in the bucket that begin with the prefix."""
    try:
        # Explicitly pass the project ID to fix the environment error
        storage_client = storage.Client(project=PROJECT_ID)
        blobs = storage_client.list_blobs(bucket_name, prefix=prefix)
        return blobs
    except Exception as e:
        print(f"Error accessing bucket '{bucket_name}': {e}")
        return []

def update_manifest():
    # 1. Load existing manifest to prevent duplicates
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                print("Error reading JSON, starting with empty list.")
                data = {"images": []}
    else:
        print(f"{MANIFEST_PATH} not found, creating new.")
        data = {"images": []}

    # Ensure "images" key exists
    if "images" not in data:
        data["images"] = []

    # Create a set of existing URLs for fast lookup
    existing_urls = {img['url'] for img in data['images']}

    print(f"Scanning bucket: {BUCKET_NAME} (Project: {PROJECT_ID}) prefix: '{PREFIX}'...")
    blobs = list_blobs(BUCKET_NAME, PREFIX)

    new_count = 0

    # Check if blobs is iterable (it might be an empty list if error occurred)
    if blobs:
        for blob in blobs:
            # Filter for image extensions
            if blob.name.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.gif')):

                # Construct the identifier used in the app.
                url_entry = f"{BUCKET_NAME}/{blob.name}"

                if url_entry in existing_urls:
                    continue

                # Generate simple tags from the filename
                filename = os.path.basename(blob.name)
                name_without_ext = os.path.splitext(filename)[0]
                tags = name_without_ext.replace('_', ' ').replace('-', ' ').split()

                new_image = {
                    "url": url_entry,
                    "tags": tags
                }

                data['images'].append(new_image)
                existing_urls.add(url_entry)
                new_count += 1
                print(f"Queueing: {filename}")

    # 2. Save the updated manifest
    if new_count > 0:
        with open(MANIFEST_PATH, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"\nSuccess! Added {new_count} new images to {MANIFEST_PATH}.")
    else:
        print("\nNo new images found.")

if __name__ == "__main__":
    if PROJECT_ID == 'your-google-cloud-project-id':
        print("ERROR: Please update the PROJECT_ID variable in the script with your actual Google Cloud Project ID.")
    else:
        update_manifest()
