# Storage API Contract

Typed client: `src/services/storage/` (`StorageClient`)  
Backend: `storage_manager/app.py` (FastAPI on VPS, GCS-backed)

## Base URLs

| Env var | Purpose |
|---------|---------|
| `REACT_APP_API_BASE_URL` | REST API root (default `https://storage.noahcohn.com`) |
| `REACT_APP_STORAGE_VPS_URL` | Webhook root (default `https://storage.noahcohn.com/webhook`) |
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

## Webhook writes (server-issued upload tokens)

The browser never holds a signing secret. `REACT_APP_WEBHOOK_SECRET` used to be
inlined into the bundle and used for `X-Hub-Signature-256`, so anyone could read
it from the JS and forge uploads. Vite now refuses to expose secret-looking
`REACT_APP_*` vars, and CI fails if the marker or the secret value appears in
`build/` (`npm run verify:no-client-secrets`). **The old secret must be rotated**
on the storage_manager side; treat it as public.

### `POST {webhookUrl}/upload-token`

storage_manager issues a short-lived token scoped to one write. It keeps the
HMAC secret (or any other key) server-side and decides who may write (origin
check, rate limit, session).

**Body** `{ "action": "save_shader", "name": "my-preset" }`

**Response 200** `{ "token": "<opaque>", "expires_at": "2026-10-27T12:00:00Z", "expires_in": 60 }` — the
token lives 60 s and is accepted once, for that exact `action` + `name`.

`action` must be one of `save_shader`, `save_metadata`, `save_output`, `save_video_config`,
`upload_texture`, `upload_audio`; `name` is 1–256 characters, no control characters.

| Status | `error` | Meaning |
|--------|---------|---------|
| 400 | `unsupported_action`, `invalid_name`, `invalid_request` | Bad body |
| 403 | `origin_not_allowed` | `Origin` missing or not in the explicit `ALLOWED_ORIGINS` list (the CORS `*` entry does **not** count) or `WEBHOOK_ALLOWED_ORIGINS` |
| 429 | – | Webhook rate-limit bucket exceeded (`WEBHOOK_RATE_LIMIT_REQUESTS`, default 30 per window per IP and method) |
| 503 | `webhook_unavailable` | `WEBHOOK_SIGNING_SECRET` unset or shorter than 32 characters |

A token is `v1.<expiry>.<nonce>.<sig>`, `sig = HMAC-SHA256(WEBHOOK_SIGNING_SECRET, "action|name|expiry|nonce")`.
Treat it as opaque. **A token is not proof of who the caller is**: anyone who can send an
allowed `Origin` can request one. It limits blast radius (one write, 60 s, once); abuse control is
the rate limit, the action allow-list, name sanitising and the body cap (`WEBHOOK_MAX_BODY_BYTES`, 25 MiB).

### `POST {webhookUrl}/image-effects`

**Headers:** `Content-Type: application/json`, `Authorization: Bearer <token>`

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

**Errors** (all JSON `{ "status": "error", "error": "<code>", "message": "..." }`)

| Status | `error` | Meaning |
|--------|---------|---------|
| 400 | `invalid_request`, `unsupported_action`, `invalid_name`, `invalid_payload` | Bad body, or `data` lacks what the action needs |
| 401 | `missing_token`, `invalid_token` | No/malformed `Authorization: Bearer` header |
| 401 | `token_expired` | Older than 60 s |
| 401 | `token_already_used` | Replay; the token is single use |
| 403 | `token_mismatch` | Signature does not verify for this `action` + `name` (tampered, another secret, or issued for a different write). The token is **not** consumed |
| 403 | `origin_not_allowed` | As above |
| 413 | `payload_too_large` | Body over `WEBHOOK_MAX_BODY_BYTES` |
| 503 | `webhook_unavailable`, `token_store_unavailable`, `storage_unavailable` | Secret unset; Redis configured but unreachable (fails closed); no GCS bucket |

A write that fails after the token is accepted (500 `write_failed`) still consumes the token; request a new one.

**Where files go.** `storage_manager` writes to its GCS bucket under `image-effects/`
(`shaders/<id>.wgsl`, `metadata/<id>.json`, `video-configs/<id>.json`, `outputs/<id>.png`,
`textures/<id>.<ext>`, `audio/<id>.<ext>`); `<id>` is `name` reduced to `[A-Za-z0-9._-]`, last path
segment only. `save_shader` also registers the shader in the existing library
(`shaders/<id>.wgsl` + `shaders/_shaders.json`, so it shows in `GET /api/shaders`) and keeps its
ratings/play count when re-saved. Whether `STATIC_NGINX_URL` serves those objects is a deployment
matter outside this repo.

The routes are served both bare (`/upload-token`, `/image-effects`) and under `/webhook/*`, because
`STORAGE_VPS_URL` defaults to `https://<host>/webhook`.

### Operating it

| Env var | Default | Purpose |
|---------|---------|---------|
| `WEBHOOK_SIGNING_SECRET` | – (routes 503) | Server-only HMAC key, ≥ 32 chars. `openssl rand -hex 32` |
| `WEBHOOK_ALLOWED_ORIGINS` | – | Extra comma-separated origins besides the explicit `ALLOWED_ORIGINS` |
| `WEBHOOK_RATE_LIMIT_REQUESTS` | `30` | Per `RATE_LIMIT_WINDOW`, per IP, per method, both routes |
| `WEBHOOK_MAX_BODY_BYTES` | `26214400` | Request body cap |
| `REDIS_URL` or `REDIS_HOST`/`PORT`/`DB`/`PASSWORD` | – | Single-use nonce store. **Required with more than one worker**; without it each worker keeps its own in-process store and a token can be replayed once per worker. If Redis is configured but unreachable, writes fail closed with 503 |
| `WEBHOOK_REDIS_DB` | `REDIS_DB + 1` | Logical Redis DB for nonces. **Must differ from the response cache's DB**: every shader save ends in aiocache `clear()`, which is `FLUSHDB`, and would erase the nonces (replay window re-opens). The route returns 503 `token_store_unavailable` if they collide |

**Rotating the secret** (do this now for the leaked one): generate a new value, set
`WEBHOOK_SIGNING_SECRET`, restart storage_manager. Tokens issued under the old secret (≤ 60 s) fail with
`token_mismatch`; the client just requests a new one. There is no dual-secret window by design.
**`REACT_APP_WEBHOOK_SECRET` shipped in earlier bundles and must be treated as public: rotate it
wherever the old receiver verified it, and remove it from any `.env`, CI secret and hosting config.**

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
