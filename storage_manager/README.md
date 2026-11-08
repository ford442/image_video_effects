# Storage Manager API

FastAPI-based storage manager for Google Cloud Storage with shader library support.

## Features

- **Multi-type storage**: songs, patterns, banks, samples, music, notes, shaders
- **Shader library**: Upload, rate, manage, and hot-load WGSL shader files
- **Category filtering**: generative, reactive, transition, filter, distortion
- **GCS integration**: Stores files and metadata in Google Cloud Storage
- **Caching**: In-memory caching with aiocache
- **CORS**: Configured for cross-origin requests

## Environment Variables

```bash
GCP_BUCKET_NAME=your-bucket-name
GCP_CREDENTIALS={"type": "service_account", ...}  # JSON string
WEBHOOK_SIGNING_SECRET=...   # server-only, >= 32 chars: openssl rand -hex 32
```

`WEBHOOK_SIGNING_SECRET` enables the browser write path (`POST /upload-token`, `POST /image-effects`).
Unset or too short: the server logs a warning at startup and both routes return 503. Other
optional knobs (`WEBHOOK_ALLOWED_ORIGINS`, `WEBHOOK_RATE_LIMIT_REQUESTS`, `WEBHOOK_MAX_BODY_BYTES`,
`REDIS_URL`) are in [docs/STORAGE_API.md](../docs/STORAGE_API.md#operating-it).

### Upload tokens: rotation

1. `openssl rand -hex 32`
2. Set it as `WEBHOOK_SIGNING_SECRET` on the host that runs storage_manager and restart it. Tokens
   already issued (60 s lifetime) stop working; clients simply ask for a new one.
3. **The old `REACT_APP_WEBHOOK_SECRET` was inlined into previously deployed JS bundles. Treat it as
   public and rotate it everywhere it was accepted; delete it from `.env` files, CI secrets and hosting config.**
4. Run more than one worker only with `REDIS_URL` set (single-use tokens are tracked there, in `WEBHOOK_REDIS_DB`,
   default `REDIS_DB + 1`: never the response cache's DB, which is flushed on every shader save).

## Rate limiting and `TRUSTED_PROXIES`

`/api/*` is limited to `RATE_LIMIT_REQUESTS` (120) per `RATE_LIMIT_WINDOW` (60 s) per client IP and method; the webhook
routes have their own, stricter bucket (`WEBHOOK_RATE_LIMIT_REQUESTS`, 30). The client IP is only as trustworthy as
the thing that reports it, and `X-Forwarded-For` is just a request header: anyone who can reach the app directly
can send any value and get a fresh bucket per request.

So the header (`RATE_LIMIT_IP_HEADER`, default `X-Forwarded-For`) is honoured **only when the TCP peer
(`request.client.host`) is listed in `TRUSTED_PROXIES`**; from any other peer it is ignored and the bucket is the peer's own IP.

| Setting | Default | Meaning |
|---------|---------|---------|
| `TRUSTED_PROXIES` | `127.0.0.1,::1` | Comma-separated IPs or CIDRs of reverse proxies you run (`10.0.0.0/8,192.0.2.7`). `""` trusts nobody. Invalid entries are logged and skipped. |
| `RATE_LIMIT_IP_HEADER` | `X-Forwarded-For` | Header the proxy sets. Several header lines count as one chain. |

When the peer is trusted, the chain is read **right to left, skipping addresses that are themselves trusted proxies, and the
first untrusted address is the client**. Each proxy appends the address it received the connection from, so entries to the
left of that were written by the client and are never used. Examples with `TRUSTED_PROXIES=10.0.0.0/8`:

| Peer | `X-Forwarded-For` | Bucket |
|------|-------------------|--------|
| `203.0.113.9` (direct, untrusted) | `1.2.3.4` | `203.0.113.9` (header ignored) |
| `10.0.0.9` | `198.51.100.4` | `198.51.100.4` |
| `10.0.0.9` | `6.6.6.6, 198.51.100.4, 10.0.0.5` | `198.51.100.4` (`10.0.0.5` skipped, `6.6.6.6` ignored) |
| `10.0.0.9` | `garbage` | `10.0.0.9` (an unparseable value is never used as a key) |

Deployment notes:

* **nginx/caddy on the same host** (the common case): nothing to set, loopback is trusted by default. Make sure the proxy
  *appends* (`proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`) or overwrites (`$remote_addr`); both are safe here.
* **Proxy in another container or host** (Docker bridge, load balancer): add its address or network, e.g.
  `TRUSTED_PROXIES=127.0.0.1,::1,172.18.0.0/16`. Until you do, every request arrives from the proxy's IP and **all users share one bucket**.
* **No proxy at all** (e.g. a Hugging Face Space or a bare `uvicorn --host 0.0.0.0`): set `TRUSTED_PROXIES=""`. Do not run `uvicorn --proxy-headers --forwarded-allow-ips '*'`, which would let any client rewrite the peer address before this check.
* **Behind two proxies**: list both; the walk skips every trusted hop.

## Running Locally

```bash
pip install -r requirements.txt
# from the repository root (the package imports itself as `storage_manager`)
uvicorn storage_manager.app:app --host 0.0.0.0 --port 7860 --reload
# tests (either directory works)
cd storage_manager && python -m pytest -q
```

## Deploy to Hugging Face Spaces

1. Create a new Space with Docker or Gradio template
2. Add environment variables in Space Settings:
   - `GCP_BUCKET_NAME`
   - `GCP_CREDENTIALS` (full JSON service account key)
3. Push this code to the Space repository

## API Endpoints

### Health
- `GET /api/health` - Check storage status and counts

### Shaders
- `GET /api/shaders` - List all shaders (with filters)
  - Query params: `category`, `min_stars`, `sort_by`
  - Categories: `generative`, `reactive`, `transition`, `filter`, `distortion`
- `GET /api/shaders/{shader_id}` - Get shader metadata
- `GET /api/shaders/{shader_id}/code` - Get actual WGSL code (for hot-loading)
- `POST /api/shaders/upload` - Upload a new .wgsl shader
- `POST /api/shaders/{shader_id}/rate` - Rate a shader (1-5 stars)
- `POST /api/shaders/{shader_id}/update` - Update shader description/tags

### Unified Library
- `GET /api/songs?type=shader` - Shaders appear in unified library search

### Songs & Samples
- `GET /api/songs` - List library items (includes shaders)
- `POST /api/songs` - Upload JSON item
- `PUT /api/songs/{item_id}` - Update item
- `PATCH /api/songs/{item_id}` - Patch metadata
- `POST /api/samples` - Upload sample file
- `GET /api/samples/{sample_id}` - Stream sample file

### Webhook writes (token-gated)
- `POST /upload-token` (also `/webhook/upload-token`) - `{action, name}` -> 60 s single-use token
- `POST /image-effects` (also `/webhook/image-effects`) - `Authorization: Bearer <token>`, performs the write

### Admin
- `POST /api/admin/sync` - Rebuild indexes from GCS
- `POST /api/admin/rescan-shaders` - Pull latest repo + regenerate `shader-lists/*.json` + upload lists to storage
- `GET /api/storage/files?folder=shaders` - List files in folder

## Shader Upload Example

```bash
# Upload a shader
curl -X POST "https://your-space.hf.space/api/shaders/upload" \
  -F "file=@my_shader.wgsl" \
  -F "name=Cool Effect" \
  -F "description=A really cool shader" \
  -F "tags=generative,organic"

# Get shader code for hot-loading
curl "https://your-space.hf.space/api/shaders/{id}/code"

# Rate a shader
curl -X POST "https://your-space.hf.space/api/shaders/{id}/rate" \
  -F "stars=4.5"

# List by category
curl "https://your-space.hf.space/api/shaders?category=generative&sort_by=rating"
```

## Python Test Script

```bash
# Test with production API
python test_shaders.py

# Test with local API
python test_shaders.py --local

# Skip upload tests
python test_shaders.py --skip-upload
```

## Storage Structure in GCS

```
bucket/
├── songs/
│   ├── _songs.json          # Index file
│   ├── {uuid}.json          # Song data
│   └── ...
├── shaders/
│   ├── _shaders.json        # Index file
│   ├── {uuid}.wgsl          # Shader files
│   └── {uuid}/
│       └── metadata.json    # Per-shader metadata
└── ...
```

## Frontend Integration

See `src/components/ShaderBrowser.tsx` and `src/services/shaderApi.ts` for React integration:

- Browse shaders with category filtering
- Upload .wgsl files from browser
- Inline editing for description/tags
- Star rating system
- Hot-load shader code into renderer

Example usage:
```tsx
import { ShaderBrowser } from './components/ShaderBrowser';

<ShaderBrowser 
  onSelect={(shader, code) => loadShaderToRenderer(code, shader.name)}
  selectedId={currentShaderId}
/>
```
