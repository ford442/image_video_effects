# WebGPU Shader Effects & Visual Library

A React + WebGPU app for real-time GPU shader effects — fluids, generative art, audio-reactive visuals, AI depth estimation, and a catalog of **1,291** compute shaders across 14 categories.

## Documentation map

| Doc | Purpose |
|-----|---------|
| [**Add a shader (5 min)**](#quick-start-add-a-shader-5-minutes) | Below — WGSL + JSON + manifest |
| [`WASM_BACKEND_POLICY.md`](WASM_BACKEND_POLICY.md) | **Dual-renderer policy** — TS Tier A vs WASM Tier B |
| [`docs/SHADER_TEMPLATES.md`](docs/SHADER_TEMPLATES.md) | JSON/WGSL conventions, multipass, `-sg` variants |
| [`agents/WGSL_BUILTINS_GENERATIVE.md`](agents/WGSL_BUILTINS_GENERATIVE.md) | Agent preamble — bindings, naga-safe builtins |
| [`notes/CREATIVE_VISION.md`](notes/CREATIVE_VISION.md) | Artistic direction (psychedelic / beautiful / strange) |
| [`docs/APP_STRUCTURE.md`](docs/APP_STRUCTURE.md) | App, Controls panels, hook map |
| [`docs/STORAGE_API.md`](docs/STORAGE_API.md) | VPS storage client contract |
| [`AGENTS.md`](AGENTS.md) | AI agent workspace rules + canonical WGSL header |

## Renderers: TypeScript (Tier A) vs WASM (Tier B)

| Tier | Backend | Default? | Notes |
|------|---------|----------|-------|
| **A — Production** | TypeScript `WebGPURenderer` | ✅ Yes | Full Controls parity; recommended for all work |
| **B — Experimental** | C++ WASM (`?renderer=wasm`) | Opt-in only | Labeled **Experimental** in UI; must not crash app |
| Fallback | Canvas2D `JSRenderer` | Auto when no WebGPU | No GPU shaders |

WASM is **never** an automatic fallback. See [`WASM_BACKEND_POLICY.md`](WASM_BACKEND_POLICY.md) for promotion gates, CI expectations, and engineering rules.

## Quick start: add a shader (5 minutes)

1. **Create WGSL** — `public/shaders/my-effect.wgsl`  
   Copy the 13-binding compute header from [`AGENTS.md`](AGENTS.md) (or [`agents/WGSL_BUILTINS_GENERATIVE.md`](agents/WGSL_BUILTINS_GENERATIVE.md) for generative shaders).

2. **Register JSON** — `shader_definitions/<category>/my-effect.json`:

```json
{
  "id": "my-effect",
  "name": "My Effect",
  "url": "shaders/my-effect.wgsl",
  "category": "image"
}
```

Canonical categories: `advanced-hybrid`, `artistic`, `distortion`, `generative`, `geometric`, `hybrid`, `image`, `interactive-mouse`, `lighting-effects`, `liquid-effects`, `post-processing`, `retro-glitch`, `simulation`, `visual-effects`.

3. **Regenerate lists + manifest**:

```bash
node scripts/generate_shader_lists.js && npm run build:manifest
```

4. **Refresh** — `npm start` (or hard-refresh if already running). The shader appears in the picker. No TypeScript recompile needed (Universal BindGroup hot-swap).

More detail: [`docs/SHADER_TEMPLATES.md`](docs/SHADER_TEMPLATES.md) · [`scripts/new_shader.py`](scripts/new_shader.py) scaffolds JSON + WGSL pairs.

## Features

- **1,291 shader effects** — counts from `public/shader-manifest-unified.json` (regenerate: `npm run build:manifest`)
- **Dual renderer** — TypeScript WebGPU (default) + experimental C++/WASM backend
- **Multipass & slot stacks** — chained/parallel layers, ping-pong feedback (`docs/PARALLEL_SLOTS.md`)
- **AI depth estimation** — DPT-Hybrid-MIDAS via `@xenova/transformers`
- **VPS storage** — save/load shaders, configs, assets via typed `StorageClient`
- **Audio/MIDI reactivity** — generative param mapping, live control bindings

## Prerequisites

- **WebGPU browser** — Chrome 113+, Edge 113+, or Firefox Nightly with WebGPU enabled
- **Node.js 16+** and npm
- **Optional:** Emscripten (`emcc`) for WASM rebuilds; headless VMs can use `SKIP_WASM_BUILD=1`

## Installation

```bash
git clone <repository-url>
cd image_video_effects
npm install
npm start          # prestart regenerates shader lists + manifest
```

Opens at `http://localhost:3000`. Use `BROWSER=none npm start` in headless environments.

### Headless / Cloud VM contributors

Cursor Cloud and similar VMs **lack a GPU adapter** — WebGPU init fails and the canvas falls back to Canvas2D (black canvas, debug overlay still updates). Validate shader/renderer work via **Jest** (`npm test`) and **build** (`SKIP_WASM_BUILD=1 npm run build`), not by eyeballing the canvas.

Outbound requests to `storage.noahcohn.com`, `storage.googleapis.com`, and Unsplash may be **network-blocked** — use local `public/` assets. See [`AGENTS.md`](AGENTS.md) Cloud VM section.

**Thumbnail batch capture** (`npm run thumbs:generate`) requires a real WebGPU GPU — cannot run in this VM. Use `npm run thumbs:status` to check coverage; run generation on a discrete-GPU workstation ([`docs/THUMBNAIL_PIPELINE.md`](docs/THUMBNAIL_PIPELINE.md)).

Setup script for agent environments: `bash scripts/jules-setup.sh` (uses committed WASM artifacts, `SKIP_WASM_BUILD=1`).

## Storage: Local vs VPS

| Mode | When | Source |
|------|------|--------|
| **Local (default dev)** | `npm start` without VPS env overrides | `public/shaders/`, unified manifest |
| **VPS storage** | `REACT_APP_API_BASE_URL` → storage manager | REST + HMAC webhook writes |

- Client: `src/services/storage/` (`StorageClient`)
- Hook: `useStorage()` · UI: `StoragePanel`

Env vars in `src/config/appConfig.ts` · Contract: [`docs/STORAGE_API.md`](docs/STORAGE_API.md)

## Usage

1. Open in a WebGPU-compatible browser
2. **New Image** — load random image (or pick from storage)
3. **Load AI Model** — enable depth-based effects
4. Select effect modes from the shader picker / slot stack
5. Click/drag for interactive ripples; toggle audio/MIDI in Controls

## Shader catalog

Counts from `npm run build:manifest` → `public/shader-manifest-unified.json`:

| Category | Count | Description |
|----------|------:|-------------|
| **generative** | 393 | Procedural art, fractals, generative patterns |
| **interactive-mouse** | 239 | Mouse and touch-driven interactions |
| **advanced-hybrid** | 166 | Multi-technique / advanced hybrid stacks |
| **artistic** | 99 | Creative and artistic visual effects |
| **image** | 93 | Image processing and filtering |
| **distortion** | 63 | Spatial warping and distortion |
| **simulation** | 47 | Physics simulations, cellular automata |
| **visual-effects** | 46 | Post-processing and visual enhancements |
| **retro-glitch** | 35 | Retro aesthetics and glitch art |
| **liquid-effects** | 31 | Fluid and liquid simulations |
| **post-processing** | 28 | Color grading, bloom, composite passes |
| **hybrid** | 18 | Combined technique shaders |
| **lighting-effects** | 17 | Volumetric lighting and glow |
| **geometric** | 16 | Geometric patterns and tessellations |
| **Total** | **1,291** | 14 canonical categories |

Legacy list files (`interactive.json`, `liquid.json`) were removed — use `interactive-mouse.json` and `liquid-effects.json`.

## Project structure

```
image_video_effects/
├── public/
│   ├── shaders/                    # WGSL compute shaders (1,291 registered)
│   ├── shader-lists/               # Generated category JSON (14 files)
│   ├── shader-manifest-unified.json
│   └── wasm/                       # Committed WASM artifacts (emcc output)
├── shader_definitions/             # Source of truth — one JSON per shader
├── src/
│   ├── App.tsx                     # Main app shell
│   ├── components/
│   │   ├── controls/               # ControlsContainer + panels
│   │   ├── storage/                # StoragePanel, useStorage UI
│   │   └── WebGPUCanvas.tsx
│   ├── hooks/                      # useStorage, useDepthEstimation, useShareChain, …
│   ├── renderer/
│   │   ├── WebGPURenderer.ts       # Tier A — default production renderer
│   │   ├── WASMRenderer.ts         # Tier B — experimental C++ bridge
│   │   ├── JSRenderer.ts           # Canvas2D fallback
│   │   ├── RendererManager.ts      # Backend switcher
│   │   ├── multipass/              # Multipass chain resolver
│   │   └── webgpuDevicePolicy.ts   # Adapter/limits ladder
│   └── services/
│       ├── storage/                # StorageClient (shaders, ratings, assets)
│       └── shaderCatalog.ts        # Search + catalog helpers
├── wasm_renderer/                  # C++ WebGPU → Emscripten (Tier B)
│   ├── renderer.cpp                # Lifecycle facade
│   ├── device.cpp, frame.cpp, …    # Split modules
│   └── STATUS.md                   # Current WASM state (not *_ANALYSIS.md)
├── storage_manager/                # FastAPI VPS backend (Python)
├── agents/                         # WGSL agent docs, swarm prompts
├── scripts/                        # Manifest, deploy, audit, sync tools
├── docs/                           # Architecture, templates, plans
├── tests/                          # Playwright smoke / parity / bench
├── AGENTS.md
└── WASM_BACKEND_POLICY.md          # Dual-renderer one-pager
```

See [`docs/APP_STRUCTURE.md`](docs/APP_STRUCTURE.md) for panel/hook detail.

## Scripts

### Dev & build

| Command | Purpose |
|---------|---------|
| `npm start` | Dev server (prestart: shader lists + manifest) |
| `npm run build` | Production build (`prebuild`: wasm → lists → manifest → craco) |
| `npm run build:manifest` | Regenerate `shader-manifest-unified.json` from category lists |
| `npm run verify:toolchain-foundation` | Enforce the main-bundle budget, lazy AI chunks, and dependency boundaries |
| `npm test` | Jest unit tests (~250) |
| `bash scripts/jules-setup.sh` | Agent/headless setup (`npm ci`, skip WASM compile) |

Production path: `wasm:build` runs **once** in `prebuild`, not again in `build`. No emcc: `SKIP_WASM_BUILD=1 npm run build`. Details: [`WASM_BUILD_CI_GUIDE.md`](WASM_BUILD_CI_GUIDE.md).

The production `main.js` budget is **320 KiB gzip**. `npm run verify:bundle-size` reads CRA's
`build/asset-manifest.json`, measures only the main entry chunk, and separately asserts that
`auto-dj`, `transformers`, and `web-llm` remain lazy chunks. The current baseline is about
**252 KiB gzip**; AI chunks are deliberately excluded from that budget. Run the production
build before this check.

TypeScript **5.4.5** is the locked compiler and CI runs a full `tsc --noEmit` plus the CRA/craco
production build. CRA 5's unmaintained peer metadata still declares TypeScript support only
through 4.x; this repository tests the working TS 5 combination directly, but removing that
metadata mismatch is one reason the optional Vite migration remains a separate follow-up.

### WASM (Tier B)

| Command | Purpose |
|---------|---------|
| `npm run wasm:build` | Compile C++ → `public/wasm/` |
| `npm run wasm:validate` | Check committed artifacts |
| `npm run wasm:clean` | Remove build + public wasm |
| `npm run test:wasm:unit` | Jest WASM bridge tests |
| `npm run test:wasm:e2e` | Playwright smoke (layer chain) |
| `npm run test:wasm:parity` | Renderer parity (needs GPU) |
| `npm run test:wasm:bench` | WASM benchmark (needs GPU) |
| `npm run test:wasm` | Unit + e2e smoke |
| `npm run test:wasm:full` | Unit + e2e + GPU parity/bench |

`public/wasm/` is the **only deployable WASM artifact source of truth**. C++ sources and the
canonical bridge fragments live under `wasm_renderer/`; `npm run wasm:build` compiles and copies
`pixelocity_wasm.{js,wasm}` into `public/wasm/`, while `wasm_renderer/concat_bridge.sh` assembles
`wasm_renderer/bridge/*.js` and synchronizes the generated compatibility copies. Do not hand-edit
`build/wasm/`, `src/wasm/wasm_bridge.js`, or the concatenated bridge outputs.

### Thumbnails (GPU workstation)

| Command | Purpose |
|---------|---------|
| `npm run thumbs:status` | Coverage vs catalog (+ eligible % excl. skip list) |
| `npm run thumbs:generate -- --missing` | Batch capture via production renderer (needs GPU + build) |
| `npm run thumbs:generate:minimal` | Fast generative-only inline WebGPU path |
| `bash scripts/run-thumbnail-waves.sh` | W1→W3 category waves (after `npm run build`) |
| `python3 scripts/audit_thumbnail_integrity.py` | Flag near-black/magenta committed PNGs |

See [`docs/THUMBNAIL_PIPELINE.md`](docs/THUMBNAIL_PIPELINE.md). CI: **Generate Thumbnails** (manual smoke) + **Thumbnail Coverage Status** (weekly issue comment).

### Storage, deploy, swarm

| Command | Purpose |
|---------|---------|
| `npm run bucket:sync` | Sync GCS bucket (simple watcher) |
| `npm run bucket:watch` | Watch mode |
| `npm run sync:shaders` | Push shaders to VPS storage |
| `npm run deploy` / `deploy:app` / `deploy:full` | Deploy scripts |
| `npm run audit:shaders` | WGSL audit swarm |
| `npm run swarm:upgrade` | Shader upgrade swarm runner |

## Technical details

- **Rendering Pipeline**: Uses a ping-pong texture system where compute shaders read previous frame state and write new state
- **Depth Integration**: AI-generated depth maps enable parallax and depth-aware effects
- **Uniform Interface**: All compute shaders share a standardized `Uniforms` structure
- **Default renderer**: TypeScript WebGPU (Tier A production path)

## Experimental C++ WASM Renderer (Tier B)

An optional **C++ Emscripten** backend can be enabled for performance experiments. It is **not** the production default and is labeled **Experimental** in the UI.

```
http://localhost:3000/?renderer=wasm
```

Or use the **Renderer** switcher in Controls.

| Topic | Document |
|-------|----------|
| Policy & promotion gates | [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md) |
| Promotion checklist + evidence | [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md) |
| Gap analysis | [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) |
| How to test | [`WASM_TESTING.md`](./WASM_TESTING.md), [`WASM_TEST_SUITE.md`](./WASM_TEST_SUITE.md) |
| Implementation status | [`wasm_renderer/STATUS.md`](./wasm_renderer/STATUS.md) |

**Limitations while Tier B:** best-effort parity with TS WebGPU; WASM GPU timings are wall-clock only; Playwright GPU tests require a real WebGPU adapter (`WASM_GPU_TESTS=1`). See policy doc before treating WASM as production-ready.

**Build WASM locally:** `npm run wasm:build` (requires [Emscripten](https://emscripten.org/)). In CI/headless VMs without emsdk: `SKIP_WASM_BUILD=1 npm run build` uses committed artifacts in `public/wasm/`.
- **Pipeline:** Ping-pong textures; compute shaders read prior frame, write next
- **Uniforms:** Shared 13-binding compute contract (see `AGENTS.md`)
- **Depth:** AI depth maps drive parallax and depth-aware effects
- **Multipass:** Linear chains today; graph runner planned — [`docs/plans/PLAN-ADVANCED-EFFECTS.md`](docs/plans/PLAN-ADVANCED-EFFECTS.md)

## Browser support

- ✅ Chrome 113+
- ✅ Edge 113+
- ⚠️ Firefox Nightly (`dom.webgpu.enabled`)
- ❌ Safari (WebGPU in development)

## License

MIT License
