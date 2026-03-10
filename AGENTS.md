# AGENTS.md - AI Agent Instructions for Pixelocity

This document provides comprehensive guidance for AI coding agents working on the Pixelocity WebGPU Shader Effects project.

---

## 🛑 CRITICAL: Your Role as a Shader Author

**YOU ARE A SHADER AUTHOR. YOU ARE NOT AN ENGINE DEVELOPER.**

The TypeScript rendering engine (`Renderer.ts`, `types.ts`) is **IMMUTABLE INFRASTRUCTURE**.
* **DO NOT** suggest changes to `Renderer.ts`, `types.ts`, or the BindGroups.
* **DO NOT** attempt to add new bindings or uniforms.
* **DO NOT** ask to install new npm packages.

Your SOLE task is to create visual effects by writing **WGSL Compute Shaders** that fit the *existing* interface.

---

## Project Overview

**Pixelocity** is a React-based web application that runs GPU shader effects using WebGPU. It features:

- **587+ shader effects** across 11 categories (liquid, distortion, artistic, generative, etc.)
- **Real-time interactive effects** with mouse-driven ripples and distortions
- **AI-powered depth estimation** using DPT-Hybrid-MIDAS model via Xenova Transformers
- **AI VJ Mode** (Alucinate) that auto-generates visual stacks using WebLLM (Gemma-2-2b-it)
- **Multi-slot shader stacking** - up to 3 effects can be chained together
- **Multiple input sources** - images, videos, webcam, live streams (HLS), and procedural generation
- **WebGPU compute shaders** for high-performance real-time rendering
- **Remote control mode** via BroadcastChannel API
- **Recording and sharing** - capture 8-second video clips with shareable links
- **Dual renderer architecture** - JavaScript and optional WASM (C++/Emscripten) renderers

### Browser Requirements
- Chrome 113+, Edge 113+, or Firefox Nightly (with `dom.webgpu.enabled` flag)
- WebGPU support is mandatory
- HTTPS or localhost required for WebGPU and camera access

---

## Project Structure

```
image_video_effects/
├── package.json                 # Dependencies and npm scripts
├── tsconfig.json               # TypeScript configuration
├── webpack.config.js           # Build configuration (minimal, for main.ts bundle)
├── public/
│   ├── index.html              # HTML entry point
│   ├── shaders/                # WGSL shader files (587+ files)
│   │   ├── liquid.wgsl         # Base liquid effect
│   │   ├── liquid-*.wgsl       # Various liquid effects
│   │   ├── texture.wgsl        # Final render pass shader
│   │   ├── imageVideo.wgsl     # Image/video display shader
│   │   ├── galaxy.wgsl         # Procedural galaxy shader
│   │   └── ...                 # 580+ more shader files
│   ├── shader-lists/           # GENERATED - DO NOT EDIT DIRECTLY
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
│   │   └── generative.json
│   └── wasm/                   # Compiled WASM renderer (optional)
│       ├── pixelocity_wasm.js
│       ├── pixelocity_wasm.wasm
│       └── wasm_bridge.js
├── shader_definitions/         # SOURCE OF TRUTH for shaders
│   ├── liquid-effects/         # 20+ liquid shader definitions
│   ├── interactive-mouse/      # 170+ mouse-driven effects
│   ├── visual-effects/         # Visual/glitch effects
│   ├── lighting-effects/       # Plasma/cosmic/glow
│   ├── distortion/             # Spatial distortions
│   ├── artistic/               # Creative/artistic effects
│   ├── retro-glitch/           # Retro/glitch aesthetics
│   ├── simulation/             # Physics simulations
│   ├── geometric/              # Geometric patterns
│   ├── image/                  # Image processing effects
│   └── generative/             # Procedural generation shaders
├── scripts/
│   ├── generate_shader_lists.js  # Generates shader-lists from definitions
│   ├── check_duplicates.js       # Utility to check for duplicate shader IDs
│   ├── watch-bucket.js           # Google Cloud Storage bucket watcher
│   ├── watch-bucket-simple.js    # Simplified bucket watcher
│   ├── wgsl-audit-swarm.sh       # Shader audit tool
│   ├── apply-wgsl-fixes.py       # Automated WGSL fixer
│   └── manage_queue.py           # Shader queue management
├── wasm_renderer/              # C++ WASM renderer source
│   ├── CMakeLists.txt
│   ├── build.sh
│   ├── main.cpp
│   ├── renderer.cpp
│   ├── renderer.h
│   └── wasm_bridge.js
└── src/
    ├── index.tsx               # React entry point (switches MainApp/RemoteApp)
    ├── App.tsx                 # Main application component (~1000 lines)
    ├── RemoteApp.tsx           # Remote control mode (BroadcastChannel sync)
    ├── AutoDJ.ts               # AI VJ (Alucinate) implementation
    ├── syncTypes.ts            # Types for remote sync
    ├── style.css               # Global styles
    ├── config/
    │   └── appConfig.ts        # App constants (URLs, defaults)
    ├── components/
    │   ├── Controls.tsx        # UI controls panel
    │   ├── Controls.test.tsx   # Test file
    │   ├── WebGPUCanvas.tsx    # Canvas wrapper with mouse handling
    │   ├── ShaderBrowser.tsx   # Shader browser component
    │   ├── ShaderBrowser.css   # Shader browser styles
    │   ├── LiveStudioTab.tsx   # Live streaming interface
    │   ├── LiveStreamBridge.tsx# HLS stream handling
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
    │   └── contentLoader.ts    # Content manifest loader
    ├── hooks/
    │   ├── useWASM.ts          # WASM loading hook
    │   ├── useAudioAnalyzer.ts # Audio analysis hook
    │   └── usePerformanceMonitor.ts # Performance monitoring
    ├── contexts/
    │   └── CurrentShaderContext.tsx # Shader context provider
    └── utils/
        └── slotState.ts        # Slot state utilities
```

---

## Technology Stack

| Category | Technology |
|----------|------------|
| Framework | React 19 + TypeScript 4.9 |
| Build Tool | Create React App (react-scripts 5.0.1) |
| GPU API | WebGPU |
| Shading Language | WGSL (WebGPU Shading Language) |
| AI/ML | @xenova/transformers (depth estimation), @mlc-ai/web-llm (Gemma-2-2b) |
| Video Streaming | HLS.js for HLS stream support |
| WASM | C++ / Emscripten (optional renderer) |
| Testing | Jest + React Testing Library |

### Key Dependencies
- `@xenova/transformers` - AI depth estimation (DPT-Hybrid-MIDAS) and image captioning
- `@mlc-ai/web-llm` - In-browser LLM for AI VJ (Gemma-2-2b-it)
- `@webgpu/types` - WebGPU type definitions
- `hls.js` - HLS video streaming support
- `playwright` - Browser automation
- `react` / `react-dom` - React framework v19

---

## Build and Development Commands

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

# Eject from Create React App (DANGEROUS - one way)
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
4. Validates WGSL content for common errors
5. Generates combined JSON files in `public/shader-lists/`

---

## Rendering Architecture

### Ping-Pong Texture System
The renderer uses a **multi-pass compute shader chain**:

1. **Input Source** → readTexture (image, video, webcam, or generative)
2. **Compute Pass 1** (Slot 0 shader) → pingPongTexture1
3. **Compute Pass 2** (Slot 1 shader) → pingPongTexture2
4. **Compute Pass 3** (Slot 2 shader) → writeTexture
5. **Render Pass** → Screen (using `texture.wgsl`)

### Fixed Internal Resolution
The canvas uses a fixed internal resolution of **2048x2048** for all rendering operations. The display size is tracked separately for aspect ratio calculations.

### Input Sources
- `image` - Static images from URL, upload, or manifest
- `video` - Video files from URL or upload
- `webcam` - Live webcam feed via getUserMedia
- `live` - HLS live streams (via hls.js)
- `generative` - Procedural shaders that generate output without input

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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Param
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

## Shader Categories

| Category | Description | Count |
|----------|-------------|-------|
| `liquid-effects` | Fluid simulations, ripples, viscosity | 20+ |
| `interactive-mouse` | Mouse-driven interactive effects | 170+ |
| `visual-effects` | Visual/glitch/chromatic effects | 30+ |
| `lighting-effects` | Plasma, glow, lens flares | 14+ |
| `distortion` | Spatial distortions, warps | 60+ |
| `artistic` | Creative/artistic effects | 90+ |
| `retro-glitch` | Retro aesthetics, VHS, CRT | 26+ |
| `simulation` | Physics, cellular automata | 16+ |
| `geometric` | Geometric patterns, tessellations | 10+ |
| `image` | Image processing effects | 50+ |
| `generative` | Procedural generation (no input needed) | 30+ |

---

## Adding a New Shader

### Step 1: Create the WGSL Shader File

Create `public/shaders/my-effect.wgsl`:

```wgsl
// ═══════════════════════════════════════════════════════════════
//  My Effect - Brief description of what this shader does
//  Category: artistic
//  Features: mouse-driven, depth-aware
// ═══════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;
    
    // Sample input color
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // YOUR EFFECT LOGIC HERE
    let outputColor = color; // Modify this
    
    // Write output
    textureStore(writeTexture, global_id.xy, outputColor);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

### Step 2: Create the Shader Definition

Create `shader_definitions/{category}/my-effect.json`:

```json
{
  "id": "my-effect",
  "name": "My Effect",
  "url": "shaders/my-effect.wgsl",
  "category": "image",
  "description": "Brief description of the effect",
  "tags": ["artistic", "interactive", "color"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Effect Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ]
}
```

### Step 3: Test

1. Run `npm start` (or let the dev server auto-reload)
2. Refresh the browser
3. Select your new effect from the dropdown

**No TypeScript recompilation needed!** The shader is loaded dynamically at runtime.

---

## Shader Definition JSON Schema

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
- `mouse-driven` - Shader responds to mouse position in `zoom_config.yz`
- `multi-pass-1`, `multi-pass-2` - For multi-pass shader pairs
- `raymarched` - Single-pass but uses raymarching
- `depth-aware` - Uses depth texture for effects
- `splat` - Splat-based interaction

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

---

## Code Style Guidelines

### TypeScript
- Use strict typing - avoid `any`
- Use functional React components with hooks
- camelCase for variables/functions, PascalCase for components
- Interface names should be descriptive

### WGSL Shaders
- Use consistent 2-space indentation
- Comment complex algorithms
- Group related operations with blank lines
- Use descriptive variable names
- Include header comments with description and category

### JSON
- Use 2-space indentation
- Always include `id`, `name`, `url`, `category`
- Use kebab-case for IDs (e.g., `liquid-metal`)
- Tag shaders appropriately for AI VJ matching

---

## Testing

### Running Tests
```bash
npm test
```

Tests use Jest and React Testing Library. Currently minimal test coverage exists.

### Manual Testing Checklist
When adding a new shader:
- [ ] Shader loads without compilation errors
- [ ] Shader appears in correct category dropdown
- [ ] Effect renders correctly
- [ ] Parameters (if any) respond to slider changes
- [ ] Mouse interaction works (if `mouse-driven` feature flag)
- [ ] Depth-aware features work (if depth model loaded)

---

## AI VJ (Alucinate) System

The AI VJ mode uses LLM to automatically create visual stacks:

1. **Image Captioning** - Uses `Xenova/vit-gpt2-image-captioning` to describe current image
2. **Shader Selection** - Uses Gemma-2-2b via WebLLM to select 3 compatible shaders
3. **Image Selection** - LLM suggests next image theme based on current scene

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
- `HELLO` - Remote connects, requests full state
- `HEARTBEAT` - Keepalive from main app
- `STATE_FULL` - Full state dump from main app
- `CMD_*` - Command messages from remote to main

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
- `wasm_renderer/` - C++ source code
- `wasm_renderer/build.sh` - Build script
- `public/wasm/` - Compiled output

The renderer can be switched at runtime between JS and WASM implementations.

---

## Troubleshooting

### Shader Compilation Errors
Check browser DevTools console for WGSL errors. Common issues:
- Missing semicolons
- Type mismatches (f32 vs i32)
- Incorrect binding numbers
- Missing textureStore call

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

## Security Considerations

- The app uses `crossOrigin="Anonymous"` for images
- Video sources must support CORS
- No sensitive data is stored locally
- AI models are loaded from HuggingFace/CDN
- File uploads are handled via File API and Blob URLs
- Remote control uses BroadcastChannel (same-origin only)

---

## Deployment

Production builds are created with:
```bash
npm run build
```

This creates a `build/` directory with static files ready for hosting.

### Deployment Requirements
- HTTPS (for WebGPU and camera access)
- CORS-enabled hosting for images/videos
- Modern browser support (Chrome 113+, Edge 113+)

---

## Quick Reference

| Task | Files to Modify |
|------|-----------------|
| Add new shader | `public/shaders/*.wgsl`, `shader_definitions/{category}/*.json` |
| Fix shader bug | `public/shaders/{shader}.wgsl` |
| Add UI controls | `src/components/Controls.tsx` |
| Change styles | `src/style.css` |
| Modify renderer | **DON'T** - It's immutable |
| Add shader category | `scripts/generate_shader_lists.js`, `src/renderer/types.ts` |

---

## Resources

- [WebGPU Specification](https://www.w3.org/TR/webgpu/)
- [WGSL Specification](https://www.w3.org/TR/WGSL/)
- [WebGPU Fundamentals](https://webgpu.github.io/webgpu-samples/)
- [React Documentation](https://react.dev/)
