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
