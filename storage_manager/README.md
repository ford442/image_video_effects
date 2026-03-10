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
```

## Running Locally

```bash
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 7860 --reload
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

### Admin
- `POST /api/admin/sync` - Rebuild indexes from GCS
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
