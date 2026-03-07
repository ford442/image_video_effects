# WASM Renderer + HLS Live Video + Physarum 3.0 Agent Swarming Pipeline

## Overview
This plan implements a complete C++ WASM WebGPU renderer with HLS live video input support and native Physarum 3.0 agent swarming. The system allows real-time agent-based simulations that react to live video streams, audio pulses, and mouse interactions.

## Features
- **C++ WASM WebGPU Renderer**: Native-speed WebGPU compute shaders via emdawnwebgpu
- **HLS Live Video Source**: Stream live video into the renderer as agent food source
- **Physarum 3.0 Agent Swarm**: Native C++ agent simulation with 100,000+ agents
- **Audio-Reactive Swarming**: Agents respond to audio frequency data
- **Mouse Interaction**: Cursor controls swarm attraction/repulsion
- **JS/WASM Toggle**: Instant switching between JavaScript and C++ renderers

## Technical Implementation

### Core Pipeline
```
HLS Stream → Video Element → WASM External Texture → Agent Food Map
                                                   ↓
Audio FFT → Frequency Data → Agent Pulse Multiplier
                                                   ↓
Mouse Position → Swarm Attraction Point
                                                   ↓
         [C++ Physarum 3.0 Compute Shader]
         - Agent position/decay/update (parallel)
         - Trail deposition + diffusion
         - Sensor sampling from food map
                                                   ↓
         Render Target → Canvas Display
```

### Proposed Code Structure

```
wasm_renderer/
├── CMakeLists.txt          # Final emdawnwebgpu configuration
├── main.cpp                # Video texture + Physarum 3.0 implementation
├── physarum_compute.wgsl   # Native compute shader (embedded)
└── build.sh               # Build script

src/
├── components/
│   ├── HLSVideoSource.tsx  # HLS player with WASM bridge
│   ├── WASMToggle.tsx      # JS/WASM renderer switch
│   └── ShaderCanvas.tsx    # Unified render canvas
├── renderer/
│   ├── Renderer.ts         # Base renderer interface
│   ├── JSRenderer.ts       # JavaScript WebGPU implementation
│   └── WASMRenderer.ts     # C++ WASM wrapper
├── hooks/
│   ├── useHLS.ts           # HLS.js integration
│   ├── useAudioAnalyzer.ts # FFT data for agents
│   └── useWASM.ts          # WASM module loader
└── shaders/
    └── physarum3.wgsl      # Agent shader (JS fallback)
```

### Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| agentCount | 1000-100000 | 50000 | Number of agents |
| sensorAngle | 0-PI/2 | PI/4 | Agent sensor angle |
| sensorDist | 1-50 | 9 | Sensor offset distance |
| turnSpeed | 0-0.5 | 0.1 | Steering response |
| decayRate | 0.8-0.99 | 0.95 | Trail decay |
| depositAmount | 0.1-10 | 0.5 | Agent deposit |
| videoFoodStrength | 0-1 | 0.3 | Video brightness as food |
| audioPulseStrength | 0-1 | 0.5 | Audio reactivity |
| mouseAttraction | -1-1 | 0.5 | Mouse influence (-1 = repel) |

## Integration Steps

### 1. wasm_renderer/CMakeLists.txt (final emdawnwebgpu version)
- Use `--use-port=emdawnwebgpu`
- Enable memory growth
- Export required functions

### 2. wasm_renderer/main.cpp (full implementation)
- CreateInstance/RequestAdapter/RequestDevice with callbacks
- importExternalTexture for video element
- Native Physarum 3.0 compute pipeline:
  - Double-buffered agent buffers
  - Trail map texture (RG32Float)
  - Compute: sense → steer → move → deposit
  - Render: trail diffusion → display
- External food map from video brightness
- Audio pulse uniform buffer
- Mouse position uniform

### 3. src/components/HLSVideoSource.tsx
- HLS.js player integration
- Hidden video element
- Callback to WASM on frame update
- Quality selection (auto/manual)

### 4. src/renderer/Renderer.ts
- Base interface: init(), render(), destroy()
- Shared uniform buffer format
- Frame sync (requestAnimationFrame)

### 5. src/renderer/WASMRenderer.ts
- Load pixelocity_wasm.js
- Pass video element reference
- Update audio/mouse uniforms
- Toggle method

### 6. src/renderer/JSRenderer.ts
- Fallback JS WebGPU implementation
- Same shaders as WASM

### 7. src/hooks/useAudioAnalyzer.ts
- AnalyserNode setup
- FFT data extraction
- Frequency bands (bass/mid/treble)

### 8. Integration in App.tsx
- HLSVideoSource component
- WASMToggle component
- ShaderCanvas with renderer prop
- Audio context provider

### 9. Build & Test
```bash
cd wasm_renderer && ./build.sh
npm run build
```

### 10. Queue Update
```bash
python scripts/manage_queue.py complete "2026-03-07_wasm-hls-physarum-swarm.md"
```

## Success Criteria
- [ ] WASM builds without warnings
- [ ] HLS video displays in canvas
- [ ] Agents swarm from video food
- [ ] Mouse attracts/repels agents
- [ ] Audio pulses trigger swarm bursts
- [ ] Toggle JS↔WASM < 100ms
- [ ] 60fps at 50,000 agents
