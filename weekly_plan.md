# Weekly Plan & Notes

## Storage Manager Updates
- Fixed CORS error causing `xFailed` when selecting shaders by adding `https://test1.1ink.us` to `ALLOWED_ORIGINS` in `storage_manager/app.py`.
- Added new entries for `image` and `video` to the `STORAGE_MAP`, mapping to the `images/` and `videos/` Google Cloud Storage directories respectively.
- Developed new endpoints to allow fetching and managing image (`/api/images`) and video (`/api/videos`) files via streaming directly from GCS to the client, utilizing `run_io` thread pooling, making them non-blocking.
- Implemented corresponding metadata PUT update endpoints for images and videos (`/api/images/{id}` and `/api/videos/{id}`) with caching behavior to clear cache correctly upon update.
- Implemented `sync-images` and `sync-videos` admin endpoints (`/api/admin/sync-...`) to maintain synchronization between GCS contents and the respective index files without manually modifying JSON arrays.
