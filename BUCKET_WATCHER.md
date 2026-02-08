# GCS Bucket Watcher

Automatically sync image and video manifests from Google Cloud Storage bucket.

## Features

- **No authentication required** - Works with public GCS buckets using the public XML API
- **Watch mode** - Continuously polls for changes
- **Change detection** - Only updates manifests when content actually changes
- **Lightweight** - No heavy Google Cloud dependencies required

## Usage

### One-time Sync

```bash
npm run bucket:sync
```

### Watch Mode (Recommended for Development)

```bash
npm run bucket:watch
```

This will poll the bucket every 30 seconds and update manifests when changes are detected.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GCS_BUCKET` | `my-sd35-space-images-2025` | GCS bucket name |
| `GCS_IMAGE_PREFIX` | `stablediff` | Folder prefix for images |
| `GCS_VIDEO_PREFIX` | `videos` | Folder prefix for videos |
| `GCS_POLL_INTERVAL` | `30000` | Polling interval in milliseconds |

### Examples

```bash
# Use a different bucket
GCS_BUCKET=my-other-bucket npm run bucket:sync

# Faster polling (5 seconds)
GCS_POLL_INTERVAL=5000 npm run bucket:watch

# Different folder structure
GCS_IMAGE_PREFIX=photos GCS_VIDEO_PREFIX=movies npm run bucket:sync
```

## Making Your Bucket Public

If your bucket is not public, the script will fail with a 403 error. To make your bucket publicly readable:

```bash
# Make the entire bucket public (read-only)
gsutil iam ch allUsers:objectViewer gs://your-bucket-name

# Or make specific folders public
gsutil iam ch allUsers:objectViewer gs://your-bucket-name/images
gsutil iam ch allUsers:objectViewer gs://your-bucket-name/videos
```

**Security Note**: Only grant `objectViewer` (read) permission, never write access.

## Generated Manifests

The script generates two files in `public/`:

1. **image_manifest.json** - Contains both images and videos
   ```json
   {
     "images": [
       {
         "url": "https://storage.googleapis.com/bucket/path/image.jpg",
         "path": "folder/image.jpg",
         "tags": ["nature", "forest", "green"]
       }
     ],
     "videos": [...],
     "updated_at": "2025-01-15T10:30:00.000Z"
   }
   ```

2. **video_manifest.json** - Contains only videos (backward compatibility)

## Integrating with Development Workflow

### Option 1: Run alongside dev server

```bash
# Terminal 1: Start the dev server
npm start

# Terminal 2: Watch for bucket changes
npm run bucket:watch
```

### Option 2: Pre-build sync

```bash
# Sync before building
npm run bucket:sync && npm run build
```

### Option 3: CI/CD Integration

Add to your deployment pipeline:

```yaml
# Example GitHub Actions step
- name: Sync bucket contents
  run: npm run bucket:sync
  env:
    GCS_BUCKET: ${{ secrets.GCS_BUCKET }}
```

## Troubleshooting

### 403 Forbidden Error

Your bucket is not public. Run:
```bash
gsutil iam ch allUsers:objectViewer gs://your-bucket-name
```

### Empty manifest

Check that:
1. The folder prefixes match your bucket structure
2. Files have valid extensions (jpg, png, mp4, webm, etc.)
3. Files are in the root of the prefix folder (not nested too deep)

### Slow updates

The default polling interval is 30 seconds. For faster updates during development:
```bash
GCS_POLL_INTERVAL=5000 npm run bucket:watch  # 5 seconds
```

Note: GCS has eventual consistency, so very frequent polling may not show immediate changes.

## Alternative: Python Version

A Python version is also available at `watch_bucket.py`:

```bash
# One-time sync
python watch_bucket.py

# Watch mode
python watch_bucket.py --watch

# Daemon mode (background)
python watch_bucket.py --daemon
```

The Python version has fewer dependencies but requires Python 3.7+.
