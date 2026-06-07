# WebGPU Shader Effects & Visual Library

A React-based web application that runs a wide variety of GPU shader effects (compute + fragment) — not only fluid simulations. Effects range from particle-based simulations and cellular automata to audio-driven spectrogram displacement, Voronoi tessellations, and fractal warping. Features include real-time interactive effects, AI-powered depth estimation, and dozens of shader modes.

## Features

- **Interactive Fluid Effects**: Click on images to create ripples and fluid-like distortions
- **AI Depth Estimation**: Uses the DPT-Hybrid-MIDAS model for depth map generation
- **680+ Shader Effects**: 678 shaders across 15 categories (fluid, simulation, audio-driven, feedback, sorting, distortion, generative, hybrid, and abstract visuals)
- **Dynamic Shader Loading**: Shaders are loaded from a configuration file for easy extensibility
- **WebGPU Powered**: High-performance compute shaders for real-time rendering

## Prerequisites

- A **WebGPU-compatible browser** (Chrome 113+, Edge 113+, or Firefox Nightly with WebGPU enabled)
- Node.js 16+ and npm

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd image_video_effects

# Install dependencies
npm install

# Start the development server
npm start
```

The application will open at `http://localhost:3000`.

## Usage

1. Open the application in a WebGPU-compatible browser
2. Click **"New Image"** to load a random image
3. Click **"Load AI Model"** to enable depth-based effects
4. Select different effect modes from the dropdown
5. Click and drag on the image to create interactive ripples

## Available Effect Categories

| Category | Count | Description |
|----------|-------|-------------|
| **Image** | 405 | Image processing and filtering effects |
| **Generative** | 97 | Procedural art, fractals, and generative patterns |
| **Interactive** | 38 | Mouse and touch-driven interactions |
| **Distortion** | 32 | Spatial warping and distortion effects |
| **Simulation** | 30 | Physics simulations and cellular automata |
| **Artistic** | 20 | Creative and artistic visual effects |
| **Visual Effects** | 18 | Post-processing and visual enhancements |
| **Hybrid** | 20 | Combined technique shaders (Phase A & B) |
| **Retro/Glitch** | 13 | Retro aesthetics and glitch art |
| **Lighting** | 14 | Volumetric lighting and glow effects |
| **Geometric** | 9 | Geometric patterns and tessellations |
| **Liquid** | 6 | Fluid and liquid simulations |

### Featured Shader Examples

| Shader | Category | Description |
|--------|----------|-------------|
| Neural Raymarcher | Advanced Hybrid | Raymarched neural network visualization |
| Gravitational Lensing | Advanced Hybrid | Black hole light bending simulation |
| Quantum Foam | Simulation | 3-pass quantum field simulation |
| Aurora Rift | Lighting | Volumetric aurora borealis effect |
| Hyper Tensor Fluid | Advanced Hybrid | Tensor field fluid dynamics |
| Audio Spirograph | Generative | Audio-reactive geometric patterns |
| Chromatic Reaction-Diffusion | Artistic | Per-channel Gray-Scott patterns |
| Hybrid Spectral Sorting | Hybrid | Audio-driven pixel sorting |

## Project Structure

```
image_video_effects/
├── public/
│   ├── index.html           # HTML entry point
│   ├── shader-lists/        # Shader configurations (category-based)
│   │   ├── liquid-effects.json       # Liquid shaders (16 entries)
│   │   ├── interactive-mouse.json    # Mouse-driven shaders (49 entries)
│   │   ├── visual-effects.json       # Glitch/CRT effects (26 entries)
│   │   ├── lighting-effects.json     # Plasma/cosmic effects (14 entries)
│   │   ├── distortion.json           # Spatial distortion (11 entries)
│   │   └── artistic.json             # Creative effects (28 entries)
│   └── shaders/             # WGSL compute shaders (680+ total)
│       ├── liquid.wgsl
│       ├── liquid-*.wgsl    # Various liquid effects
│       ├── plasma.wgsl
│       ├── vortex.wgsl
│       └── ...
├── src/
│   ├── App.tsx              # Main React component
│   ├── index.tsx            # React entry point
│   ├── style.css            # Application styles
│   ├── components/
│   │   ├── Controls.tsx     # UI controls component
│   │   └── WebGPUCanvas.tsx # Canvas wrapper component
│   └── renderer/
│       ├── Renderer.ts      # WebGPU rendering engine
│       └── types.ts         # TypeScript type definitions
├── package.json
├── tsconfig.json
└── AGENTS.md                # AI agent instructions
```

## Scripts

```bash
npm start    # Start development server
npm run build   # Build for production
npm test     # Run tests
```

## Shader Categories

- **Fluid & Physics Simulations** — Navier-Stokes dye, Melting Oil, Pixel Sand, Physarum
- **Iterative & Feedback Systems** — Temporal Echo, Reaction-Diffusion, Lenia
- **Distortion & Sorting** — Bitonic Pixel Sort, Julia Warp, Voronoi
- **Data-Driven & Abstract** — Spectrogram Displace, Datamosh, ASCII/Glyph, Neon Edge

## Adding New Shaders

1. Create a new `.wgsl` file in `public/shaders/`
2. Follow the standard shader interface (see `AGENTS.md` for details)
3. Add an entry to the appropriate category file in `public/shader-lists/`:
   - `liquid-effects.json` - for liquid-* shaders
   - `interactive-mouse.json` - for mouse-driven effects
   - `visual-effects.json` - for glitch/CRT/chromatic effects
   - `lighting-effects.json` - for plasma/cosmic/glow effects
   - `distortion.json` - for spatial distortions
   - `artistic.json` - for creative/artistic effects

```json
{
  "id": "my-shader",
  "name": "My Shader",
  "url": "shaders/my-shader.wgsl",
  "category": "image"
}
```

## ⚡️ Hot-Swap Shader Workflow (No Recompile Needed)

This engine uses a "Universal BindGroup" architecture. You can drop in new `.wgsl` files without restarting the dev server or recompiling the TypeScript host.

1.  **Create File:** Add `public/shaders/my-cool-effect.wgsl`.
2.  **Paste Header:** Copy the standard uniform header from `AGENTS.md`.
3.  **Register:** Add one entry to the appropriate category file in `public/shader-lists/`:
    ```json
    { "id": "cool-effect", "name": "My Cool Effect", "url": "shaders/my-cool-effect.wgsl", "category": "image" }
    ```
4.  **Test:** Refresh the browser. The new effect appears in the dropdown immediately.

**Note to AI Copilots:** If asked to create a shader, output *only* the WGSL file and the JSON snippet. Do not modify the rendering engine. Add new shaders to the most appropriate category file to avoid merge conflicts.

## Technical Details

- **Rendering Pipeline**: Uses a ping-pong texture system where compute shaders read previous frame state and write new state
- **Depth Integration**: AI-generated depth maps enable parallax and depth-aware effects
- **Uniform Interface**: All compute shaders share a standardized `Uniforms` structure

## Browser Support

This application requires WebGPU support:
- ✅ Chrome 113+
- ✅ Edge 113+
- ⚠️ Firefox Nightly (with `dom.webgpu.enabled` flag)
- ❌ Safari (WebGPU in development)

## License

MIT License
