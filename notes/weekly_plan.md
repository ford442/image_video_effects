# Weekly Plan & Notes

## Known Issues / Recent Fixes

### Remote Control — Connection Loss (Fixed 2026-04-18)
The remote control mode (`?mode=remote`) was repeatedly showing **"LOST CONNECTION"** even when both tabs were open on the same origin.

**Root causes:**
1. **Heartbeat timeout mismatch**: Main app sent `HEARTBEAT` every **5s**, but the remote tab timed out after only **3s**.
2. **BroadcastChannel effect re-runs**: `App.tsx` closed and recreated the `BroadcastChannel` on almost every state change because the effect depended on `buildFullState` (which changes whenever any syncable state changes). Each re-run cleared the heartbeat interval, so the remote often missed heartbeats.
3. **Stagnant reconnection**: The remote stopped sending `HELLO` retries after 3 attempts, so if the main app missed that window, the remote never reconnected.

**Fixes applied:**
- `RemoteApp.tsx`: increased heartbeat timeout to **8s** (longer than the 5s heartbeat interval).
- `RemoteApp.tsx`: any message from the main app now resets the heartbeat timer, not just explicit `HEARTBEAT` messages.
- `RemoteApp.tsx`: `HELLO` retries continue indefinitely while disconnected.
- `App.tsx`: wrapped `buildFullState` in a ref so the `BroadcastChannel` effect only runs **once** on mount.
- `App.tsx`: sends an immediate `HEARTBEAT` when `HELLO` is received, before the interval starts.

## Storage Manager Updates
- Fixed CORS error causing `xFailed` when selecting shaders by adding `https://test1.1ink.us` to `ALLOWED_ORIGINS` in `storage_manager/app.py`.
- Added new entries for `image` and `video` to the `STORAGE_MAP`, mapping to the `images/` and `videos/` Google Cloud Storage directories respectively.
- Developed new endpoints to allow fetching and managing image (`/api/images`) and video (`/api/videos`) files via streaming directly from GCS to the client, utilizing `run_io` thread pooling, making them non-blocking.
- Implemented corresponding metadata PUT update endpoints for images and videos (`/api/images/{id}` and `/api/videos/{id}`) with caching behavior to clear cache correctly upon update.
- Implemented `sync-images` and `sync-videos` admin endpoints (`/api/admin/sync-...`) to maintain synchronization between GCS contents and the respective index files without manually modifying JSON arrays.
