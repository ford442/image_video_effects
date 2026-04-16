# AGENTS.md - AI Agent Instructions for Pixelocity

This document provides comprehensive guidance for AI coding agents working on the Pixelocity WebGPU Shader Effects project. Read this first before making any changes.

---

## 🛑 CRITICAL: Your Role as a Shader Author

**YOU ARE A SHADER AUTHOR. YOU ARE NOT AN ENGINE DEVELOPER.**

The TypeScript rendering engine (`Renderer.ts`, `types.ts`, and the BindGroup layout) is **IMMUTABLE INFRASTRUCTURE**.
* **DO NOT** suggest changes to `Renderer.ts`, `types.ts`, or the BindGroups.
* **DO NOT** attempt to add new bindings or uniforms.
* **DO NOT** ask to install new npm packages.

Your SOLE task is to create visual effects by writing **WGSL Compute Shaders** that fit the *existing* interface.

---

## Project Overview

**Pixelocity** is a React-based web application that runs GPU shader effects using WebGPU. It features:

- **709 shader definitions** and **714 WGSL files** across 15 categories (image, generative, interactive-mouse, distortion, simulation, artistic, visual-effects, hybrid, advanced-hybrid, retro-glitch, lighting-effects, geometric, liquid-effects, post-processing)
- **Real-time interactive effects** with mouse-driven ripples and distortions
- **AI-powered depth estimation** using DPT-Hybrid-MIDAS model via Xenova Transformers
- **AI VJ Mode** (Alucinate) that auto-generates visual stacks using WebLLM (Gemma-2-2b-it)
- **Multi-slot shader stacking** — up to 3 effects can be chained together in `chained` or `parallel` mode
- **Multiple input sources** — images, videos, webcam, live streams (HLS), and procedural generation
- **WebGPU compute shaders** for high-performance real-time rendering
- **Remote control mode** via BroadcastChannel API
- **Recording and sharing** — capture 8-second video clips with shareable links
- **Dual renderer architecture** — JavaScript and optional WASM (C++/Emscripten) renderers
- **VPS Storage Manager** — FastAPI backend for shader library, images, and media hosting

### Browser Requirements
- Chrome 113+, Edge 113+, or Firefox Nightly (with `dom.webgpu.enabled` flag)
- WebGPU support is mandatory
- HTTPS or localhost required for WebGPU and camera access

---

## Technology Stack

| Category | Technology |
|----------|------------|
| Framework | React 19 + TypeScript 4.9 |
| Build Tool | Create React App (react-scripts 5.0.1) |
| GPU API | WebGPU |
| Shading Language | WGSL (WebGPU Shading Language) |
| AI/ML | `@xenova/transformers` (depth estimation), `@mlc-ai/web-llm` (Gemma-2-2b) |
| Video Streaming | `hls.js` for HLS stream support |
| WASM | C++ / Emscripten (optional renderer) |
| Testing | Jest + React Testing Library |
| Browser Automation | Playwright |
| Backend Storage | FastAPI (`storage_manager/app.py`) |
| Deployment | Python `deploy.py` (SFTP to DreamHost) |

### Key Dependencies
- `@xenova/transformers` — AI depth estimation (DPT-Hybrid-MIDAS) and image captioning
- `@mlc-ai/web-llm` — In-browser LLM for AI VJ (Gemma-2-2b-it)
- `@webgpu/types` — WebGPU type definitions
- `hls.js` — HLS video streaming support
- `playwright` — Browser automation
- `react` / `react-dom` — React framework v19

---

## Project Structure

```
image_video_effects/
├── package.json                 # Dependencies and npm scripts
├── tsconfig.json               # TypeScript configuration
├── webpack.config.js           # Minimal webpack for main.ts bundle
├── .github/workflows/ci.yml    # GitHub Actions CI pipeline
├── deploy.py                   # Smart SFTP deployment script
├── public/
│   ├── index.html              # HTML entry point
│   ├── shaders/                # WGSL shader files (714 files)
│   │   ├── liquid.wgsl         # Base liquid effect
│   │   ├── texture.wgsl        # Final render pass shader
│   │   ├── imageVideo.wgsl     # Image/video display shader
│   │   └── ...                 # 710+ more shader files
│   ├── shader-lists/           # GENERATED — DO NOT EDIT DIRECTLY
│   │   ├── liquid-effects.json
│   │   ├── interactive-mouse.json
│   │   ├── visual-effects.json
│   │   ├── lighting-effects.json
│   │   ├── distortion.json
│   │   ├── artistic.json
│   │   ├── retro-glitch.json
│   │   ├── simulation.json
│   │   ├── geometric.json
│   │   ├── image.json
│   │   ├── generative.json
│   │   ├── post-processing.json
│   │   └── hybrid.json
│   └── wasm/                   # Compiled WASM renderer (optional)
│       ├── pixelocity_wasm.js
│       ├── pixelocity_wasm.wasm
│       └── wasm_bridge.js
├── shader_definitions/         # SOURCE OF TRUTH for shaders
│   ├── liquid-effects/         # Liquid shader definitions
│   ├── interactive-mouse/      # Mouse-driven effects
│   ├── visual-effects/         # Visual/glitch effects
│   ├── lighting-effects/       # Plasma/cosmic/glow
│   ├── distortion/             # Spatial distortions
│   ├── artistic/               # Creative/artistic effects
│   ├── retro-glitch/           # Retro/glitch aesthetics
│   ├── simulation/             # Physics simulations
│   ├── geometric/              # Geometric patterns
│   ├── image/                  # Image processing effects
│   ├── generative/             # Procedural generation shaders
│   ├── hybrid/                 # Combined technique shaders (Phase A)
│   ├── advanced-hybrid/        # Complex multi-technique shaders (Phase B)
│   └── post-processing/        # Post-processing effects
├── scripts/
│   ├── generate_shader_lists.js  # Generates shader-lists from definitions
│   ├── check_duplicates.js       # Utility to check for duplicate shader IDs
│   ├── watch-bucket.js           # Google Cloud Storage bucket watcher
│   ├── watch-bucket-simple.js    # Simplified bucket watcher
│   ├── wgsl-audit-swarm.sh       # Shader audit tool
│   ├── apply-wgsl-fixes.py       # Automated WGSL fixer
│   ├── shader_test_runner.py     # Shader test runner
│   ├── shader-validator.js       # Shader validation
│   └── manage_queue.py           # Shader queue management
├── shader_queue/               # PR queue for shader submissions
│   ├── pr_queue.json
│   ├── process_next_pr.sh
│   └── status.sh
├── storage_manager/            # FastAPI backend for shader/media storage
│   ├── app.py
│   ├── requirements.txt
│   └── seed_shaders.json
├── storage_manager_static/     # Static HTML for storage manager
├── wasm_renderer/              # C++ WASM renderer source
│   ├── CMakeLists.txt
│   ├── build.sh
│   ├── main.cpp
│   ├── renderer.cpp
│   ├── renderer.h
│   └── wasm_bridge.js
└── src/
    ├── index.tsx               # React entry point (switches MainApp/RemoteApp)
    ├── App.tsx                 # Main application component
    ├── RemoteApp.tsx           # Remote control mode (BroadcastChannel sync)
    ├── AutoDJ.ts               # AI VJ (Alucinate) implementation
    ├── syncTypes.ts            # Types for remote sync
    ├── style.css               # Global styles
    ├── config/
    │   └── appConfig.ts        # App constants (URLs, defaults)
    ├── components/
    │   ├── Controls.tsx        # UI controls panel
    │   ├── Controls.test.tsx   # Unit tests for Controls
    │   ├── WebGPUCanvas.tsx    # Canvas wrapper with mouse handling
    │   ├── WebGPUCanvas.test.tsx # Unit tests for WebGPUCanvas
    │   ├── ShaderBrowser.tsx   # Shader browser component
    │   ├── ShaderBrowser.css   # Shader browser styles
    │   ├── ShaderMegaMenu.tsx  # Mega-menu for shader selection
    │   ├── ShaderScanner.tsx   # Shader scanner overlay
    │   ├── ShaderStarRating.tsx # Star rating component
    │   ├── LiveStudioTab.tsx   # Live streaming interface
    │   ├── LiveStreamBridge.tsx# HLS stream handling
    │   ├── StorageBrowser.tsx  # VPS storage browser
    │   ├── StorageControls.tsx # Storage controls
    │   ├── RendererToggle.tsx  # JS/WASM renderer switcher
    │   ├── WASMToggle.tsx      # WASM toggle component
    │   ├── HLSVideoSource.tsx  # HLS video source
    │   ├── PerformanceDashboard.tsx # Performance metrics
    │   ├── BilibiliInput.tsx   # Bilibili live stream input
    │   └── DanmakuOverlay.tsx  # Danmaku/chat overlay
    ├── renderer/
    │   ├── Renderer.ts         # WebGPU rendering engine (IMMUTABLE)
    │   ├── RendererManager.ts  # Renderer manager (JS/WASM switching)
    │   ├── BaseRenderer.ts     # Base renderer interface
    │   ├── JSRenderer.ts       # JavaScript renderer implementation
    │   ├── WASMRenderer.ts     # WASM renderer wrapper
    │   └── types.ts            # TypeScript type definitions
    ├── services/
    │   ├── shaderApi.ts        # Shader API service
    │   ├── StorageService.ts   # VPS storage service
    │   └── contentLoader.ts    # Content manifest loader
    │   └── contentLoader.test.ts # Unit tests for contentLoader
    ├── hooks/
    │   ├── useWASM.ts          # WASM loading hook
    │   ├── useAudioAnalyzer.ts # Audio analysis hook
    │   ├── useStorage.ts       # Storage hook
    │   └── usePerformanceMonitor.ts # Performance monitoring
    ├── contexts/
    │   └── CurrentShaderContext.tsx # Shader context provider
    ├── utils/
    │   └── slotState.ts        # Slot state utilities
    └── __tests__/
        └── StorageIntegration.test.tsx # Storage integration tests
```

---

## Build, Test, and Development Commands

```bash
# Install dependencies
npm install

# Start development server (localhost:3000)
# Automatically runs generate_shader_lists.js before starting
npm start

# Build for production
# Automatically runs generate_shader_lists.js before building
npm run build

# Run tests
npm test

# Eject from Create React App (DANGEROUS — one way)
npm run eject

# WASM renderer commands
npm run wasm:build      # Build WASM renderer (requires Emscripten)
npm run wasm:clean      # Clean WASM build artifacts

# Bucket sync commands (for Google Cloud Storage)
npm run bucket:sync        # Sync bucket contents
npm run bucket:watch       # Watch bucket for changes
npm run bucket:sync-full   # Full sync with processing
npm run bucket:watch-full  # Full watch with processing

# Shader audit commands
npm run audit:shaders         # Run WGSL audit swarm
npm run audit:shaders:sample  # Run audit on sample shaders

# Deployment
npm run deploy          # Deploy using deploy.py
```

### Pre-build Script
The `prestart` and `prebuild` scripts automatically run `scripts/generate_shader_lists.js`, which:
1. Reads all JSON files from `shader_definitions/` subdirectories
2. Validates shader IDs (no duplicates)
3. Verifies WGSL files exist
4. Validates WGSL content for common errors (missing `@compute`, missing `fn main`, empty files)
5. Generates combined JSON files in `public/shader-lists/`

---

## CI/CD Pipeline

The project uses **GitHub Actions** (`.github/workflows/ci.yml`) with two jobs:

### `test` job
- Checkout code
- Setup Node.js 20 with npm caching
- `npm ci`
- Run `node scripts/generate_shader_lists.js`
- Run `node audit_mouse_shaders.js` (shader metadata audit)
- Run `node scripts/check_duplicates.js`
- Run `npm test -- --watchAll=false --coverage`
- Run `npm run build`
- Upload coverage to Codecov (on pull requests only)

### `lint` job
- Checkout code
- Setup Node.js 20
- `npm ci`
- Run ESLint: `npx eslint src --ext .ts,.tsx --max-warnings=0`
- Generate shader lists
- Validate all JSON manifests in `public/shader-lists/`

---

## Rendering Architecture

### Ping-Pong Texture System
The renderer uses a **multi-pass compute shader chain**:

1. **Input Source** → `readTexture` (image, video, webcam, or generative)
2. **Compute Pass 1** (Slot 0 shader) → `pingPongTexture1`
3. **Compute Pass 2** (Slot 1 shader) → `pingPongTexture2`
4. **Compute Pass 3** (Slot 2 shader) → `writeTexture`
5. **Render Pass** → Screen (using `texture.wgsl`)

### Slot Modes
Each slot can run in one of two modes:
- **`chained`** (default): Sequential — output of slot N feeds into slot N+1
- **`parallel`**: Concurrent — runs independently, all read from the same input

### Fixed Internal Resolution
The canvas uses a fixed internal resolution of **2048x2048** for all rendering operations. The display size is tracked separately for aspect ratio calculations.

### Input Sources
- `image` — Static images from URL, upload, or manifest
- `video` — Video files from URL or upload
- `webcam` — Live webcam feed via getUserMedia
- `live` — HLS live streams (via hls.js)
- `generative` — Procedural shaders that generate output without input

### Shader Bindings (IMMUTABLE)
Every compute shader MUST declare exactly these bindings:

```wgsl
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
```

### Uniform Structure
```wgsl
struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};
```

### Workgroup Size
All compute shaders MUST use:
```wgsl
@compute @workgroup_size(8, 8, 1)
```

This matches the dispatch: `dispatchWorkgroups(Math.ceil(width/8), Math.ceil(height/8), 1)`

---

## Code Organization & Module Divisions

### Frontend (`src/`)
- **`components/`** — React UI components. Controls, canvas wrapper, shader browsers, live studio, overlays.
- **`renderer/`** — WebGPU rendering abstraction. `Renderer.ts` is the JS WebGPU engine. `RendererManager.ts` switches between JS and WASM. `types.ts` defines shared interfaces.
- **`services/`** — Data fetching and external APIs. `shaderApi.ts` talks to the VPS storage manager. `contentLoader.ts` loads manifests. `StorageService.ts` handles uploads and operations.
- **`hooks/`** — Custom React hooks for WASM, audio analysis, performance monitoring, and storage.
- **`contexts/`** — React context providers (current shader state).
- **`utils/`** — Small utilities like `slotState.ts`.
- **`config/`** — `appConfig.ts` holds all API URLs, fallback content, and feature flags.

### Shader Assets (`public/shaders/` & `shader_definitions/`)
- **`shader_definitions/`** is the **source of truth**. Every shader has a JSON definition here.
- **`public/shaders/`** contains the actual `.wgsl` source files.
- **`public/shader-lists/`** is **auto-generated** by `scripts/generate_shader_lists.js` — never edit directly.

### Backend (`storage_manager/`)
- **`app.py`** — FastAPI application providing shader library, image/video hosting, ratings, and GCS integration.
- **`requirements.txt`** — Python dependencies (fastapi, uvicorn, google-cloud-storage, aiocache, etc.).
- Runs on the VPS (`storage.noahcohn.com`) and proxies through nginx.

### WASM (`wasm_renderer/`)
- C++ WebGPU renderer using Emscripten and Dawn/emdawnwebgpu.
- Optional performance-oriented alternative to the JS renderer.
- Build with `npm run wasm:build` (requires Emscripten SDK).

### Scripts & Automation
- Root-level Python/Node scripts for batch shader fixes, parameter extraction, duplicate checking, deployment, and validation.
- `scripts/` contains build-time and audit tools.
- `shader_queue/` contains PR processing shell scripts for shader submissions.

---

## Shader Categories

| Category | Description | Count (approx.) |
|----------|-------------|-----------------|
| `image` | Image processing effects | 405 |
| `generative` | Procedural generation (no input needed) | 97 |
| `interactive-mouse` | Mouse-driven interactive effects | 38 |
| `distortion` | Spatial distortions, warps | 32 |
| `simulation` | Physics, cellular automata | 30 |
| `artistic` | Creative/artistic effects | 20 |
| `visual-effects` | Visual/glitch/chromatic effects | 18 |
| `hybrid` | Combined technique shaders (Phase A) | 10 |
| `advanced-hybrid` | Complex multi-technique shaders (Phase B) | 10 |
| `retro-glitch` | Retro aesthetics, VHS, CRT | 13 |
| `lighting-effects` | Plasma, glow, lens flares | 14 |
| `geometric` | Geometric patterns, tessellations | 9 |
| `liquid-effects` | Fluid simulations, ripples, viscosity | 6 |
| `post-processing` | Post-processing effects | 6 |

---

## Development Conventions

### TypeScript
- Use strict typing — avoid `any`
- Use functional React components with hooks
- camelCase for variables/functions, PascalCase for components
- Interface names should be descriptive

### WGSL Shaders
- Use consistent 2-space indentation
- Comment complex algorithms
- Group related operations with blank lines
- Use descriptive variable names
- Include header comments with description, category, features, and chunk attribution

### JSON (Shader Definitions)
- Use 2-space indentation
- Always include `id`, `name`, `url`, `category`
- Use kebab-case for IDs (e.g., `liquid-metal`)
- Tag shaders appropriately for AI VJ matching

### Shader Definition JSON Schema

```typescript
interface ShaderEntry {
  id: string;           // Unique identifier (kebab-case)
  name: string;         // Display name
  url: string;          // Path to WGSL file relative to public/
  category: ShaderCategory;
  description?: string; // Optional description
  tags?: string[];      // For AI VJ matching (e.g., ["neon", "glitch", "liquid"])
  features?: string[];  // Feature flags (e.g., ["mouse-driven", "multi-pass"])
  params?: ShaderParam[]; // Up to 4 slider parameters
  advanced_params?: ShaderParam[]; // Advanced parameters
}

interface ShaderParam {
  id: string;           // Parameter identifier
  name: string;         // Display name
  default: number;      // Default value
  min: number;          // Minimum value
  max: number;          // Maximum value
  step?: number;        // Step size (default: 0.01)
  labels?: string[];    // Optional labels for discrete values
}
```

### Feature Flags
- `mouse-driven` — Shader responds to mouse position in `zoom_config.yz`
- `multi-pass-1`, `multi-pass-2` — For multi-pass shader pairs
- `raymarched` — Single-pass but uses raymarching
- `depth-aware` — Uses depth texture for effects
- `splat` — Splat-based interaction
- `audio-reactive` — Responds to audio input
- `temporal` — Uses feedback/history

### Chunk Attribution
Always attribute borrowed code chunks:
```wgsl
// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    // ... implementation
}
```

### Standard Hybrid Header
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {Shader Name}
//  Category: {category}
//  Features: {feature-list}
//  Complexity: {Low|Medium|High|Very High}
//  Chunks From: {source shaders}
//  Created: {date}
//  By: {agent}
// ═══════════════════════════════════════════════════════════════════
```

---

## Testing Strategy

### Automated Tests
The project uses **Jest** and **React Testing Library**.

Existing test files:
- `src/components/Controls.test.tsx` — Controls rendering, parameter labels, mega-menu filtering
- `src/components/WebGPUCanvas.test.tsx` — Canvas component tests
- `src/__tests__/StorageIntegration.test.tsx` — Storage browser, `useStorage` hook, connection status
- `src/services/contentLoader.test.ts` — Content loader service tests

Run tests with:
```bash
npm test
```

### Manual Testing Checklist
When adding a new shader:
- [ ] Shader loads without compilation errors
- [ ] Shader appears in correct category dropdown
- [ ] Effect renders correctly
- [ ] Parameters (if any) respond to slider changes
- [ ] Mouse interaction works (if `mouse-driven` feature flag)
- [ ] Depth-aware features work (if depth model loaded)
- [ ] CI pipeline passes (`generate_shader_lists.js`, `check_duplicates.js`, build)

---

## Deployment Process

### Production Build
```bash
npm run build
```
This creates a `build/` directory with static files ready for hosting.

### Deployment via `deploy.py`
The project includes a Python deployment script (`deploy.py`) that:
- Uses **SFTP** to upload to a DreamHost server (`1ink.us`, user `ford442`)
- Tracks uploaded file hashes in `.deploy_manifest.json` to avoid redundant uploads
- Automatically generates `.htaccess` for Apache cache control and gzip compression
- Handles client-side routing (React Router) via rewrite rules
- Protects critical files (`index.html`, `.htaccess`, `asset-manifest.json`)

Run via npm:
```bash
npm run deploy
```

### VPS Storage Manager
A **FastAPI** backend (`storage_manager/app.py`) runs on a Contabo VPS (`storage.noahcohn.com`):
- Hosts shader library with ratings and hot-loading
- Serves image/video/audio manifests
- Integrates with Google Cloud Storage for file persistence
- Proxied through nginx (HTTPS on 443 → backend on 8000)

---

## Security Considerations

- The app uses `crossOrigin="Anonymous"` for images — remote images must support CORS
- Video sources must support CORS
- No sensitive user data is stored locally
- AI models are loaded from HuggingFace/CDN
- File uploads are handled via File API and Blob URLs
- Remote control uses BroadcastChannel (same-origin only)
- The VPS webhook uses HMAC SHA256 signatures; the secret should be set via environment variable (`REACT_APP_WEBHOOK_SECRET`)
- HTTPS is required for WebGPU and camera access

---

## Common Shader Patterns

### Reading Mouse Position
```wgsl
let mousePos = u.zoom_config.yz;  // Normalized 0-1
let isMouseDown = u.zoom_config.w > 0.5;
```

### Reading Parameters
```wgsl
let param1 = u.zoom_params.x;
let param2 = u.zoom_params.y;
let param3 = u.zoom_params.z;
let param4 = u.zoom_params.w;
```

### Reading Depth
```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
// depth: 0.0 = far (background), 1.0 = near (foreground)
```

### Ripple Data Access
```wgsl
let rippleCount = u32(u.config.y);
for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let pos = ripple.xy;
    let startTime = ripple.z;
    let elapsed = currentTime - startTime;
}
```

### UV Displacement
```wgsl
let displacement = vec2<f32>(sin(uv.y * 10.0 + time), cos(uv.x * 10.0 + time)) * 0.01;
let displacedUV = uv + displacement;
let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
```

---

## Multi-Pass Shader Architecture

Some effects require multiple passes. These are implemented as shader pairs:

**Pass 1** (e.g., `rainbow-vector-field.wgsl`):
- Generates intermediate data
- Outputs to `writeTexture` (color) and `writeDepthTexture` (data)

**Pass 2** (e.g., `prismatic-feedback-loop.wgsl`):
- Reads from `readTexture` and `readDepthTexture` (Pass 1 output)
- Applies final compositing

Mark with metadata:
```json
{
  "id": "rainbow-vector-field",
  "multipass": { "pass": 1, "totalPasses": 2, "nextShader": "prismatic-feedback-loop" },
  "features": ["multi-pass-1"]
}
```

### Data Texture Convention
For complex multi-pass shaders, use the data texture binding convention:
```wgsl
// Pass 1: Write to dataTextureA
@group(0) @binding(13) var dataTextureA: texture_storage_2d<rgba32float, write>;

// Pass 2: Read from dataTextureC (fed with dataTextureA content)
// Write to dataTextureB
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;  // Previous pass output
```

See `quantum-foam-pass*.wgsl` and `sim-fluid-feedback-field-pass*.wgsl` for examples.

---

## Optimization Patterns

### 1. Distance-Based LOD
Reduce noise octaves for distant pixels:
```wgsl
let dist = length(uv - 0.5);
let octaves = i32(mix(6.0, 2.0, dist * 1.5));  // Fewer octaves at edges
```

### 2. Early Exit
Skip calculations for minimal effect regions:
```wgsl
if (effectStrength < 0.01) {
    textureStore(writeTexture, global_id.xy, originalColor);
    return;
}
```

### 3. Branchless Code
Use `select()` instead of if-statements where possible:
```wgsl
let result = select(b, a, condition);
```

---

## Audio Reactivity Patterns

### Reading Audio Input
```wgsl
let bass = plasmaBuffer[0].x;      // Low frequencies
let mids = plasmaBuffer[0].y;      // Mid frequencies
let treble = plasmaBuffer[0].z;    // High frequencies
```

### Common Audio Patterns
```wgsl
let pulse = 1.0 + bass * 0.5;
let hueShift = fract(time * 0.1 + bass * 0.2);
let beat = step(0.7, bass);
```

---

## AI VJ (Alucinate) System

The AI VJ mode uses LLM to automatically create visual stacks:

1. **Image Captioning** — Uses `Xenova/vit-gpt2-image-captioning` to describe current image
2. **Shader Selection** — Uses Gemma-2-2b via WebLLM to select 3 compatible shaders
3. **Image Selection** — LLM suggests next image theme based on current scene

### Tagging for AI VJ
When creating shaders, include relevant tags:
```json
{
  "tags": ["neon", "colorful", "geometric", "glitch", "liquid", "abstract"]
}
```

Common tags: `neon`, `glitch`, `liquid`, `geometric`, `abstract`, `colorful`, `monochrome`, `retro`, `futuristic`, `organic`, `particles`, `warp`, `distortion`

---

## Remote Control Mode

The app supports remote control via `BroadcastChannel`:
- Main app URL: `http://localhost:3000`
- Remote control URL: `http://localhost:3000?mode=remote`

Remote mode mirrors the controls UI and syncs state to the main app.

### Sync Protocol
The sync system uses a `BroadcastChannel` named `webgpu_remote_control_channel` with message types:
- `HELLO` — Remote connects, requests full state
- `HEARTBEAT` — Keepalive from main app
- `STATE_FULL` — Full state dump from main app
- `CMD_*` — Command messages from remote to main

---

## Recording and Sharing

The app supports recording 8-second video clips:
- Uses `canvas.captureStream(60)` for 60fps capture
- Encodes to WebM format (VP9/VP8)
- Auto-downloads the recording
- Generates shareable URL with current state encoded in hash

### Shareable URL Format
```
http://localhost:3000#shader=liquid&slot=0&p1=0.50&p2=0.50&source=image&img=...
```

---

## WASM Renderer (Optional)

The project includes an optional C++/Emscripten WASM renderer for better performance:

### Building WASM Renderer
```bash
# Requires Emscripten SDK installed
npm run wasm:build
```

### Files
- `wasm_renderer/` — C++ source code
- `wasm_renderer/build.sh` — Build script
- `public/wasm/` — Compiled output

The renderer can be switched at runtime between JS and WASM implementations.

---

## UI/UX Design System: Gold & Dark Tinted Glass

This section defines the **official design system** for Pixelocity's user interface. All UI components must follow these specifications to maintain visual consistency.

### Overview

The **Gold & Dark Tinted Glass** theme combines luxurious gold accents with deep dark backgrounds and modern glassmorphism effects. This creates an elegant, premium aesthetic suitable for a creative visual effects application.

**Design Philosophy:**
- **Luxury**: Rich gold tones convey premium quality
- **Depth**: Layered glassmorphism creates visual hierarchy
- **Clarity**: High contrast text ensures readability
- **Atmosphere**: Dark backgrounds make visual effects pop

---

### Design Tokens

#### Color Palette

| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-primary-gold` | `#FFD700` | Primary accent, icons, highlights |
| `--color-gold-light` | `#D4AF37` | Gradient stops, secondary accents |
| `--color-gold-dark` | `#B8860B` | Gradient stops, pressed states |
| `--color-gold-dim` | `#DAA520` | Subtle gold elements |
| `--color-bg-dark` | `#0a0a0f` | Main background |
| `--color-bg-dark-elevated` | `#141418` | Elevated surfaces |
| `--color-glass-bg` | `rgba(20, 20, 30, 0.6)` | Glass card backgrounds |
| `--color-glass-bg-hover` | `rgba(30, 30, 45, 0.7)` | Glass hover state |
| `--color-glass-border` | `rgba(255, 215, 0, 0.2)` | Glass borders |
| `--color-glass-border-subtle` | `rgba(255, 215, 0, 0.1)` | Subtle borders |
| `--color-text-primary` | `#FFFFFF` | Primary text |
| `--color-text-secondary` | `rgba(255, 255, 255, 0.7)` | Secondary text |
| `--color-text-muted` | `rgba(255, 255, 255, 0.5)` | Muted/disabled text |
| `--color-accent-glow` | `rgba(255, 215, 0, 0.3)` | Gold glow effects |
| `--color-shadow-dark` | `rgba(0, 0, 0, 0.4)` | Drop shadows |
| `--color-highlight` | `rgba(255, 255, 255, 0.1)` | Inner highlights |

#### Gradients

```css
/* Primary Gold Gradient - Buttons, accents */
--gradient-gold: linear-gradient(135deg, #FFD700 0%, #D4AF37 50%, #B8860B 100%);

/* Subtle Gold Gradient - Cards, headers */
--gradient-gold-subtle: linear-gradient(180deg, rgba(255, 215, 0, 0.1) 0%, rgba(255, 215, 0, 0.02) 100%);

/* Dark Gradient - Background overlays */
--gradient-dark: linear-gradient(180deg, rgba(10, 10, 15, 0.95) 0%, rgba(10, 10, 15, 0.8) 100%);

/* Glass Gradient - Card backgrounds */
--gradient-glass: linear-gradient(135deg, rgba(255, 255, 255, 0.1) 0%, rgba(255, 255, 255, 0.02) 100%);
```

#### Typography

| Token | Value | Usage |
|-------|-------|-------|
| `--font-family` | `'Inter', system-ui, -apple-system, sans-serif` | Primary font |
| `--font-family-mono` | `'JetBrains Mono', 'Fira Code', monospace` | Code, technical text |
| `--font-weight-regular` | `400` | Body text |
| `--font-weight-medium` | `500` | Emphasized text |
| `--font-weight-semibold` | `600` | Headers, buttons |
| `--font-weight-bold` | `700` | Titles, strong emphasis |
| `--letter-spacing-header` | `0.5px` | Headers, labels |
| `--letter-spacing-wide` | `1px` | Uppercase labels |
| `--line-height-tight` | `1.25` | Headlines |
| `--line-height-normal` | `1.5` | Body text |
| `--line-height-relaxed` | `1.75` | Large paragraphs |

#### Font Sizes

```css
--font-size-xs: 0.75rem;      /* 12px - Captions, badges */
--font-size-sm: 0.875rem;     /* 14px - Secondary text */
--font-size-base: 1rem;       /* 16px - Body text */
--font-size-md: 1.125rem;     /* 18px - Lead text */
--font-size-lg: 1.25rem;      /* 20px - Section headers */
--font-size-xl: 1.5rem;       /* 24px - Card titles */
--font-size-2xl: 2rem;        /* 32px - Page titles */
--font-size-3xl: 2.5rem;      /* 40px - Hero titles */
```

#### Spacing Scale

| Token | Value | Pixels | Usage |
|-------|-------|--------|-------|
| `--space-0` | `0` | 0px | No space |
| `--space-1` | `0.25rem` | 4px | Inline elements |
| `--space-2` | `0.5rem` | 8px | Base unit, tight spacing |
| `--space-3` | `0.75rem` | 12px | Small gaps |
| `--space-4` | `1rem` | 16px | Standard gaps |
| `--space-5` | `1.25rem` | 20px | Medium padding |
| `--space-6` | `1.5rem` | 24px | Card padding |
| `--space-8` | `2rem` | 32px | Large gaps |
| `--space-10` | `2.5rem` | 40px | Section padding |
| `--space-12` | `3rem` | 48px | Major sections |

#### Border Radius

```css
--radius-none: 0;             /* Sharp corners */
--radius-sm: 4px;             /* Small elements */
--radius-md: 8px;             /* Buttons, inputs */
--radius-lg: 12px;            /* Cards, panels */
--radius-xl: 16px;            /* Large cards */
--radius-2xl: 24px;           /* Modals, containers */
--radius-full: 9999px;        /* Pills, circles */
```

---

### Glassmorphism Effects

#### Standard Glass Card

```css
.glass-card {
  /* Background */
  background: rgba(20, 20, 30, 0.6);

  /* Backdrop blur for the frosted glass effect */
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);

  /* Border */
  border: 1px solid rgba(255, 215, 0, 0.15);
  border-radius: 12px;

  /* Shadow */
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.1);

  /* Padding */
  padding: 24px;
}
```

#### Elevated Glass Card (Hover/Active State)

```css
.glass-card-elevated {
  background: rgba(30, 30, 45, 0.7);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  border-color: rgba(255, 215, 0, 0.25);
  box-shadow:
    0 12px 48px rgba(0, 0, 0, 0.5),
    0 0 20px rgba(255, 215, 0, 0.1),
    inset 0 1px 0 rgba(255, 255, 255, 0.15);
}
```

#### Glass Button (Primary)

```css
.glass-button-primary {
  background: linear-gradient(135deg, #FFD700 0%, #D4AF37 50%, #B8860B 100%);
  border: none;
  border-radius: 8px;
  color: #0a0a0f;
  font-weight: 600;
  padding: 12px 24px;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow:
    0 4px 16px rgba(255, 215, 0, 0.3),
    inset 0 1px 0 rgba(255, 255, 255, 0.3);
}

.glass-button-primary:hover {
  transform: translateY(-1px);
  box-shadow:
    0 6px 24px rgba(255, 215, 0, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.4);
}

.glass-button-primary:active {
  transform: translateY(1px);
  box-shadow:
    0 2px 8px rgba(255, 215, 0, 0.2),
    inset 0 2px 4px rgba(0, 0, 0, 0.2);
}
```

#### Glass Button (Secondary)

```css
.glass-button-secondary {
  background: rgba(20, 20, 30, 0.6);
  backdrop-filter: blur(8px);
  border: 1px solid rgba(255, 215, 0, 0.2);
  border-radius: 8px;
  color: #FFD700;
  font-weight: 500;
  padding: 12px 24px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.glass-button-secondary:hover {
  background: rgba(30, 30, 45, 0.8);
  border-color: rgba(255, 215, 0, 0.4);
  box-shadow: 0 0 16px rgba(255, 215, 0, 0.2);
}
```

#### Glass Input Field

```css
.glass-input {
  background: rgba(10, 10, 15, 0.6);
  backdrop-filter: blur(8px);
  border: 1px solid rgba(255, 215, 0, 0.15);
  border-radius: 8px;
  color: #FFFFFF;
  padding: 12px 16px;
  font-size: 0.875rem;
  transition: all 0.2s ease;
}

.glass-input::placeholder {
  color: rgba(255, 255, 255, 0.4);
}

.glass-input:focus {
  outline: none;
  border-color: rgba(255, 215, 0, 0.4);
  box-shadow: 0 0 0 3px rgba(255, 215, 0, 0.1);
}
```

---

### CSS Variables (Root Declaration)

```css
:root {
  /* Primary Colors */
  --color-primary-gold: #FFD700;
  --color-gold-light: #D4AF37;
  --color-gold-dark: #B8860B;
  --color-gold-dim: #DAA520;

  /* Background Colors */
  --color-bg-dark: #0a0a0f;
  --color-bg-dark-elevated: #141418;
  --color-glass-bg: rgba(20, 20, 30, 0.6);
  --color-glass-bg-hover: rgba(30, 30, 45, 0.7);

  /* Border Colors */
  --color-glass-border: rgba(255, 215, 0, 0.2);
  --color-glass-border-subtle: rgba(255, 215, 0, 0.1);
  --color-glass-border-strong: rgba(255, 215, 0, 0.3);

  /* Text Colors */
  --color-text-primary: #FFFFFF;
  --color-text-secondary: rgba(255, 255, 255, 0.7);
  --color-text-muted: rgba(255, 255, 255, 0.5);

  /* Effect Colors */
  --color-accent-glow: rgba(255, 215, 0, 0.3);
  --color-shadow-dark: rgba(0, 0, 0, 0.4);
  --color-highlight: rgba(255, 255, 255, 0.1);

  /* Gradients */
  --gradient-gold: linear-gradient(135deg, #FFD700 0%, #D4AF37 50%, #B8860B 100%);
  --gradient-gold-subtle: linear-gradient(180deg, rgba(255, 215, 0, 0.1) 0%, rgba(255, 215, 0, 0.02) 100%);
  --gradient-dark: linear-gradient(180deg, rgba(10, 10, 15, 0.95) 0%, rgba(10, 10, 15, 0.8) 100%);
  --gradient-glass: linear-gradient(135deg, rgba(255, 255, 255, 0.1) 0%, rgba(255, 255, 255, 0.02) 100%);

  /* Typography */
  --font-family: 'Inter', system-ui, -apple-system, sans-serif;
  --font-family-mono: 'JetBrains Mono', 'Fira Code', monospace;
  --font-weight-regular: 400;
  --font-weight-medium: 500;
  --font-weight-semibold: 600;
  --font-weight-bold: 700;
  --letter-spacing-header: 0.5px;
  --letter-spacing-wide: 1px;
  --line-height-tight: 1.25;
  --line-height-normal: 1.5;
  --line-height-relaxed: 1.75;

  /* Font Sizes */
  --font-size-xs: 0.75rem;
  --font-size-sm: 0.875rem;
  --font-size-base: 1rem;
  --font-size-md: 1.125rem;
  --font-size-lg: 1.25rem;
  --font-size-xl: 1.5rem;
  --font-size-2xl: 2rem;
  --font-size-3xl: 2.5rem;

  /* Spacing */
  --space-0: 0;
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-5: 1.25rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --space-10: 2.5rem;
  --space-12: 3rem;

  /* Border Radius */
  --radius-none: 0;
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 12px;
  --radius-xl: 16px;
  --radius-2xl: 24px;
  --radius-full: 9999px;

  /* Glassmorphism */
  --glass-blur: blur(12px);
  --glass-blur-heavy: blur(16px);
  --glass-blur-light: blur(8px);
  --glass-shadow: 0 8px 32px rgba(0, 0, 0, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.1);
  --glass-shadow-elevated: 0 12px 48px rgba(0, 0, 0, 0.5), 0 0 20px rgba(255, 215, 0, 0.1), inset 0 1px 0 rgba(255, 255, 255, 0.15);
  --glass-border: 1px solid rgba(255, 215, 0, 0.15);

  /* Transitions */
  --transition-fast: 0.15s ease;
  --transition-normal: 0.2s ease;
  --transition-slow: 0.3s ease;
}
```

---

### Component Patterns

#### Card Component

```tsx
// Example: Control Panel Card
<div className="glass-card">
  <h3 className="card-title">Shader Controls</h3>
  <div className="card-content">
    {/* Control content */}
  </div>
</div>

/* CSS */
.card-title {
  font-size: var(--font-size-lg);
  font-weight: var(--font-weight-semibold);
  color: var(--color-primary-gold);
  letter-spacing: var(--letter-spacing-header);
  margin-bottom: var(--space-4);
}

.card-content {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}
```

#### Slider Component

```css
.glass-slider {
  -webkit-appearance: none;
  appearance: none;
  width: 100%;
  height: 4px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: var(--radius-full);
  outline: none;
}

.glass-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 16px;
  height: 16px;
  background: var(--gradient-gold);
  border-radius: 50%;
  cursor: pointer;
  box-shadow: 0 2px 8px rgba(255, 215, 0, 0.4);
  transition: transform var(--transition-fast);
}

.glass-slider::-webkit-slider-thumb:hover {
  transform: scale(1.1);
}
```

#### Dropdown/Select Component

```css
.glass-select {
  background: var(--color-glass-bg);
  backdrop-filter: var(--glass-blur);
  border: var(--glass-border);
  border-radius: var(--radius-md);
  color: var(--color-text-primary);
  padding: var(--space-3) var(--space-4);
  font-size: var(--font-size-sm);
  cursor: pointer;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23FFD700' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
  padding-right: 36px;
}

.glass-select:hover {
  background-color: var(--color-glass-bg-hover);
  border-color: var(--color-glass-border);
}
```

---

### Accessibility Guidelines

1. **Contrast Ratios**
   - Primary text (#FFFFFF) on dark backgrounds: 16:1 ✓
   - Secondary text (70% white) on dark backgrounds: 10:1 ✓
   - Gold text (#FFD700) on dark backgrounds: 12:1 ✓

2. **Focus States**
   - All interactive elements must have visible focus indicators
   - Use gold glow (`box-shadow: 0 0 0 3px rgba(255, 215, 0, 0.3)`) for focus rings

3. **Touch Targets**
   - Minimum 44x44px for buttons
   - Minimum 24px height for inputs

4. **Reduced Motion**
   - Respect `prefers-reduced-motion` media query
   - Provide instant state changes when motion is disabled

---

### Responsive Considerations

```css
/* Mobile adjustments */
@media (max-width: 768px) {
  .glass-card {
    padding: var(--space-4);
    border-radius: var(--radius-md);
  }

  :root {
    --font-size-2xl: 1.75rem;
    --font-size-xl: 1.25rem;
  }
}

/* Reduced glass effect on devices that struggle with blur */
@media (prefers-reduced-transparency: reduce) {
  .glass-card {
    background: var(--color-bg-dark-elevated);
    backdrop-filter: none;
  }
}
```

---

## Troubleshooting

### Shader Compilation Errors
Check browser DevTools console for WGSL errors. Common issues:
- Missing semicolons
- Type mismatches (f32 vs i32)
- Incorrect binding numbers
- Missing `textureStore` call

### WebGPU Not Available
Ensure browser supports WebGPU and you're using HTTPS or localhost.

### Shader Not Appearing in Dropdown
- Check `shader_definitions/{category}/` has your JSON file
- Verify `id` is unique across all categories
- Run `npm start` to regenerate shader lists
- Check browser console for generation errors

### Texture Size Mismatch
All textures must match the canvas size (2048x2048 internal resolution). The renderer handles this automatically.

---

## Quick Reference

| Task | Files to Modify |
|------|-----------------|
| Add new shader | `public/shaders/*.wgsl`, `shader_definitions/{category}/*.json` |
| Fix shader bug | `public/shaders/{shader}.wgsl` |
| Add UI controls | `src/components/Controls.tsx` |
| Change styles | `src/style.css` or `src/styles/gold-glass-theme.css` |
| Modify renderer | **DON'T** — It's immutable |
| Add shader category | `scripts/generate_shader_lists.js`, `src/renderer/types.ts` |
| Update API URLs | `src/config/appConfig.ts` |
| Run tests | `npm test` |
| Deploy | `npm run build` then `npm run deploy` |

---

## Resources

- [WebGPU Specification](https://www.w3.org/TR/webgpu/)
- [WGSL Specification](https://www.w3.org/TR/WGSL/)
- [WebGPU Fundamentals](https://webgpu.github.io/webgpu-samples/)
- [React Documentation](https://react.dev/)
