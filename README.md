# WebGPU Shader Effects & Visual Library

A React-based web application that runs a wide variety of GPU shader effects (compute + fragment) — not only fluid simulations. Effects range from particle-based simulations and cellular automata to audio-driven spectrogram displacement, Voronoi tessellations, and fractal warping. Features include real-time interactive effects, AI-powered depth estimation, and dozens of shader modes.

## Features

- **Interactive Fluid Effects**: Click on images to create ripples and fluid-like distortions
- **AI Depth Estimation**: Uses the DPT-Hybrid-MIDAS model for depth map generation
- **Multiple Shader Effects**: Dozens of shader modes across multiple categories (fluid, simulation, audio-driven, feedback, sorting, distortion, and abstract visuals)
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

## Available Effect Modes (Selected)

| Mode | Description |
|------|-------------|
| Liquid (Interactive) | Basic fluid simulation with mouse-driven ripples |
| Liquid (Ambient) | Continuous ambient fluid motion |
| Liquid Zoom | Zoom-based parallax effect |
| Liquid Perspective | 3D perspective distortion |
| Liquid Viscous | Slower, more viscous fluid behavior |
| Clean Vortex | Swirling vortex effect |
| Liquid Fast | Quick, responsive ripples |
| Liquid RGB | RGB color channel separation |
| Liquid Metal | Metallic reflection simulation |
| Liquid Jelly | Bouncy, jelly-like distortion |
| Liquid Rainbow | Rainbow color shift effects |
| Liquid Oil | Oil-on-water iridescence |
| Liquid Glitch | Digital glitch artifacts |
| Plasma Ball | Animated plasma ball effect |
| Melting Oil | Sobel gradient-driven oil painting flow |
| Physarum Slime Mold | Agent-based slime mold texture feeder |
| Pixel Sand | Falling granular cellular automata |
| Navier-Stokes Dye | Velocity advection and dye injection |
| Temporal Echo | Feedback buffer time-slicing and history |
| Reaction-Diffusion | Grey-Scott multi-channel color bleed |
| Lenia CA | Continuous Lenia-style cellular automata |
| Bitonic Pixel Sort | Workgroup-enabled pixel sorting |
| Julia Warp | Complex fractal warp with orbit traps |
| Voronoi | Animated tessellation and feature-driven cells |
| Spectrogram Displace | Audio FFT-driven displacement |
| Datamosh | Optical-flow datamosh and smear accumulation |
| ASCII Glyphs | Atlas-based glyph morphing and SDF render |
| Neon Edge Diffusion | Edge detection with neon diffusion |
| Boids | Flocking masks to reveal textures |

## Project Structure

```
image_video_effects/
├── public/
│   ├── index.html           # HTML entry point
│   ├── shader-list.json     # Shader configuration
│   └── shaders/             # WGSL compute shaders (dozens)
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
3. Add an entry to `public/shader-list.json`:

```json
{
  "id": "my-shader",
  "name": "My Shader",
  "url": "shaders/my-shader.wgsl"
}
```

## ⚡️ Hot-Swap Shader Workflow (No Recompile Needed)

This engine uses a "Universal BindGroup" architecture. You can drop in new `.wgsl` files without restarting the dev server or recompiling the TypeScript host.

1.  **Create File:** Add `public/shaders/my-cool-effect.wgsl`.
2.  **Paste Header:** Copy the standard uniform header from `AGENTS.md`.
3.  **Register:** Add one line to `public/shader-list.json`:
    ```json
    { "id": "cool-effect", "name": "My Cool Effect", "url": "shaders/my-cool-effect.wgsl" }
    ```
4.  **Test:** Refresh the browser. The new effect appears in the dropdown immediately.

**Note to AI Copilots:** If asked to create a shader, output *only* the WGSL file and the JSON snippet. Do not modify the rendering engine.

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
