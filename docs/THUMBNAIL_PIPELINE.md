# Thumbnail Pipeline

Automated batch rendering of shader preview thumbnails for the gallery / mega-menu UX.

## Hardware requirements

Thumbnail generation **requires a real WebGPU GPU**. The script drives Chromium via Playwright and renders through the production WebGPU renderer.

| Environment | Works? |
|-------------|--------|
| Linux/macOS/Windows with Vulkan, D3D12, or Metal | Yes |
| Chrome / Chromium 121+ | Yes |
| GitHub `ubuntu-latest` (no GPU adapter) | No — smoke-only |
| Cursor Cloud VM (headless, no ICD) | No |
| `xvfb-run` alone | No — provides a display, not a GPU |

`xvfb-run` can help on headless Linux **when a GPU is present** but no display server is running.

## Prerequisites

```bash
npm ci
SKIP_WASM_BUILD=1 npm run build
npx playwright install chromium
```

The `app` engine (default) serves the production build from `build/`. The `minimal` engine skips the build and uses a fast inline WebGPU path (generative shaders only).

## Commands

```bash
# Generate all missing thumbnails (resume-safe)
npm run thumbs:generate -- --missing

# Check coverage vs catalog
npm run thumbs:status

# Category batch
npm run thumbs:generate -- --missing --category=generative

# Limit smoke run
npm run thumbs:generate -- --limit=5 --category=generative

# Parallel shards across machines
npm run thumbs:generate -- --missing --shard=0/4
npm run thumbs:generate -- --missing --shard=1/4
# ...

# Force regenerate existing
npm run thumbs:generate -- --force --ids=plasma-storm,cyber-ripples

# Fast inline engine (no production build)
npm run thumbs:generate:minimal -- --category=generative --limit=20
```

## CLI flags

| Flag | Default | Description |
|------|---------|-------------|
| `--engine=app\|minimal` | `app` | Production renderer vs inline WebGPU |
| `--missing` | off | Skip shaders that already have PNG + manifest entry |
| `--force` | off | Regenerate even when thumbnail exists |
| `--category=NAME` | `all-catalog` | Shader list category or `all-catalog` |
| `--limit=N` | none | Max shaders to process |
| `--shard=I/N` | none | Process every Nth shader where `index % N === I` |
| `--frames=60` | `60` | Animation frames to wait before capture (`app` engine) |
| `--size=256` | `256` | Output PNG dimension (square) |
| `--quality=battery` | `battery` | Render quality preset (OOM guard) |
| `--time=1.5` | `1.5` | Shader time uniform at capture |
| `--report=PATH` | `reports/thumbnail-failures.json` | Failure report output |

## Output

- PNG files: `public/thumbnails/<shader-id>.png`
- Manifest: `public/thumbnails/manifest.json` (consumed by `ShaderGallery` and `CommunityGallery`)
- Failures: `reports/thumbnail-failures.json`

### Failure report schema

```json
{
  "generated_at": "2026-07-19T12:00:00.000Z",
  "engine": "app",
  "summary": {
    "success": 120,
    "failed": 3,
    "skipped": 1,
    "black_frame": 2,
    "compile": 1
  },
  "failures": [
    {
      "id": "some-shader",
      "reason": "black_frame",
      "detail": "meanLuminance=0.0020 activePixelRatio=0.0010",
      "stats": { "meanLuminance": 0.002, "activePixelRatio": 0.001, "width": 1024, "height": 1024 }
    }
  ]
}
```

Failure reasons: `black_frame`, `compile`, `pipeline`, `no_wgsl`, `gpu_unavailable`, `load_failed`, `capture_failed`.

## Coverage strategy (target ≥80%)

Current catalog is ~1,300 shaders. Run in waves on a GPU workstation:

| Wave | Categories | Notes |
|------|------------|-------|
| W1 | `generative`, `visual-effects` | Highest UX impact |
| W2 | `simulation`, `distortion`, `liquid-effects` | Multipass / history shaders |
| W3 | `image`, `post-processing`, remainder | Image shaders use `public/fixtures/thumbnail-sample.png` |

Example W1:

```bash
SKIP_WASM_BUILD=1 npm run build
npm run thumbs:generate -- --missing --category=generative
npm run thumbs:status
git add public/thumbnails/
```

Commit PNGs + `manifest.json` in category-sized PRs to keep diffs reviewable.

## CI

Manual workflow: **Actions → Generate Thumbnails → Run workflow**

The default GitHub runner has no GPU; the job runs a `--limit=5` smoke capture and uploads artifacts. For full batch runs, use a self-hosted runner with the `webgpu` label (see `.github/workflows/generate-thumbnails.yml`).

## Related

- Generator: [`scripts/generate-shader-thumbnails.js`](../scripts/generate-shader-thumbnails.js)
- Harness: [`scripts/lib/thumbnailHarness.mjs`](../scripts/lib/thumbnailHarness.mjs)
- Test API: [`src/hooks/useTestHarness.ts`](../src/hooks/useTestHarness.ts)
- Parent issue: #965 / #921
