# Storage API Contract

Typed client: `src/services/storage/` (`StorageClient`)  
Backend: `storage_manager/app.py` (FastAPI on VPS, GCS-backed)

## Base URLs

| Env var | Purpose |
|---------|---------|
| `REACT_APP_API_BASE_URL` | REST API root (default `https://storage.noahcohn.com`) |
| `REACT_APP_STORAGE_VPS_URL` | HMAC webhook root (default `https://storage.noahcohn.com/webhook`) |
| `REACT_APP_STATIC_NGINX_URL` | Static file reads for saved metadata/outputs |
| `REACT_APP_SHADER_FILES_BASE_URL` | WGSL CDN fallback (default `https://test.1ink.us/image_video_effects/`) |

Configure in `src/config/appConfig.ts`.

---

## Health

### `GET /api/health`

**Response 200**

```json
{ "status": "ok", "service": "contabo-storage-manager" }
```

Client: `StorageClient.checkHealth()`

---

## Shaders

### `GET /api/shaders`

Query: `category`, `min_stars` (0–5), `sort_by` (`rating` \| `date` \| `name` \| `coordinate` \| `last_played`)

**Response 200:** `ShaderItem[]`

Client: `StorageClient.listShaders(query?)`

### `GET /api/shaders/{shader_id}`

Path segment URL-encoded by client (`encodeResourcePath`).

**Response 200:** `ShaderItem` metadata (includes `stars`, `rating_count`, `play_count`)

Client: `getShaderMeta()` / `getShaderRating()` (derived)

### `GET /api/shaders/{shader_id}/wgsl`

**Response 200:** `text/plain` WGSL source

Client: `loadShaderWgsl()`

### `POST /api/shaders/{shader_id}/rate`

**Body:** `multipart/form-data` — field `stars` (1–5)

**Response 200**

```json
{
  "id": "liquid",
  "stars": 4.5,
  "rating_count": 12,
  "your_rating": 5
}
```

Client: `StorageClient.rateShader(id, stars)`

### `POST /api/shaders/{shader_id}/play`

Increments `play_count`. Client: `recordShaderPlay()`

### `POST /api/shaders/upload`

Multipart `.wgsl` upload (admin/authoring). Not used by the React webhook path.

---

## Assets (images, video, audio)

There is **no** `GET /api/images` list endpoint. Use the unified library:

### `GET /api/songs?type={type}`

`type`: `image` \| `video` \| `audio` \| `song` \| … (see `STORAGE_MAP` in app.py)

**Response 200:** `MetaData[]`

| Client method | Endpoint |
|---------------|----------|
| `listImages()` | `GET /api/songs?type=image` |
| `listVideos()` | `GET /api/songs?type=video` |
| `listAudio()` | `GET /api/songs?type=audio` |
| `listLibrary()` | `GET /api/songs` |

### `GET /api/images/{image_id}`

Streams image bytes (302 to signed GCS URL or proxy). Client builds URL as `{apiUrl}/api/images/{id}`.

### `GET /api/songs/{item_id}`

Streams song/video/audio media.

---

## Webhook writes (HMAC)

### `POST {webhookUrl}/image-effects`

**Headers:** `Content-Type: application/json`, `X-Hub-Signature-256: sha256={hex}`

**Body**

```json
{
  "action": "save_shader | save_metadata | save_output | save_video_config | upload_texture | upload_audio",
  "name": "my-preset",
  "data": { "...": "..." },
  "timestamp": "2026-07-12T00:00:00.000Z"
}
```

**Response 200**

```json
{
  "status": "success",
  "message": "...",
  "files": ["image-effects/shaders/my-preset.wgsl"]
}
```

Client adds `url` from `STATIC_NGINX_URL` + first file path.

| Client method | `action` |
|---------------|----------|
| `saveShader()` | `save_shader` |
| `saveEffectConfig()` | `save_metadata` (`data.type = effect_config`) |
| `saveOutput()` | `save_output` |
| `saveVideoConfig()` | `save_video_config` |
| `uploadTexture()` / image file upload | `upload_texture` |

---

## Error mapping

Failed REST responses become `StorageHttpError`:

```
HTTP {status} {statusText}: {response body}
```

Path segments are encoded with `encodeResourcePath()` before insertion into URLs.

---

## React integration

| Layer | Module |
|-------|--------|
| Typed client | `src/services/storage/client.ts` |
| Hook (single surface) | `src/hooks/useStorage.ts` |
| UI entry | `src/components/storage/StoragePanel.tsx` |
| Compact controls | `src/components/storage/StorageControlsPanel.tsx` |

Legacy imports from `StorageService.ts` and `StorageBrowser.tsx` re-export the new modules. Use `src/components/storage/` paths for UI components.
