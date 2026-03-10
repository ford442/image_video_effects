# Raptor Mini 	6 Fast Predatory Agent Swarm Shader

## Overview
A miniature, high-speed agent swarm inspired by Physarum but reimagined as a pack of tiny raptor-like creatures. Each agent is designed to move aggressively, chase the mouse cursor, and perform ``claw strike`` maneuvers. Scale textures give visual character, and audio input triggers a rage mode that amps up speed and attack intensity.

This shader must run flawlessly in both JavaScript WebGPU and native C++ WASM implementations while consuming minimal CPU (<5ms per frame) even with 8,192 agents.

## Features
- **8,192 Raptor Agents**: Fast, lightweight, and numbered for performance.
- **Raptor Personality**: Quick turns, rapid acceleration, and claw attack animation.
- **Scale Pattern Visuals**: Procedural or texture-based scales on each agent's body.
- **Mouse as Prey**: Cursor position acts as a moving target; agents chase and strike.
- **Audio Rage Mode**: Audio amplitude drives a temporary boost in speed and attack frequency.
- **Multi-platform**: JavaScript WebGPU shader with a C++ WASM counterpart.
- **Ultra Low CPU Overhead**: Optimized compute so the demo runs under 5ms per frame.

## Technical Implementation

### Core Pipeline
```
Mouse Position → Attraction Field → Agent Steering
Audio FFT → Rage Multiplier → Speed/Attack Intensity

[Compute Shader / WASM Simulation]
- Agent state (pos, dir, rageTimer)
- Sense prey field and neighbors
- Steering: high turn speed, aggressive alignment
- Movement: fast velocity, occasional claw attack
- Scale pattern generation (UV or noise)

Render pass: draw agents with scale shading and claw highlights
```

### Proposed Code Structure

```
wasm_renderer/
├── CMakeLists.txt          # emdawnwebgpu build config
├── main.cpp                # Raptor Mini simulation + WebGPU setup
├── raptor_mini_compute.wgsl
└── build.sh

src/
├── components/
│   ├── ShaderCanvas.tsx    # unified render surface
│   └── RageAudioVisualizer.tsx # optional UI element
├── renderer/
│   ├── Renderer.ts         # base interface
│   ├── JSRenderer.ts       # JS compute shaders
│   └── WASMRenderer.ts     # C++ loader
├── hooks/
│   ├── useAudioAnalyzer.ts # rage detection
│   └── useMouseTracker.ts  # cursor poller
└── shaders/
    └── raptorMini.wgsl    # identical to raptor_mini_compute.wgsl
```

### Parameters

| Parameter           | Range    | Default | Description                                 |
|---------------------|----------|---------|---------------------------------------------|
| agentCount          | 1024-16384 | 8192   | Total number of raptor agents               |
| turnSpeed           | 0.2-1.0  | 0.8     | High agility for quick direction changes    |
| maxSpeed            | 1-5      | 3       | Base velocity (in world units)              |
| rageDuration        | 0.5-5    | 1.2     | How long audio rage lasts                   |
| rageSpeedBoost      | 1-3      | 2       | Multiplier applied during rage              |
| clawProb            | 0-0.1    | 0.02    | Chance of performing claw strike per frame  |
| scalePatternSize    | 1-10     | 4       | Scale texture tiling factor                 |
| preyAttractionCoeff | 0-2      | 1.5     | Strength of mouse attraction                 |
| neighborCohesion    | 0-1      | 0.3     | Tendency to align with nearby rappies       |

## Integration Steps

1. **wasm_renderer/CMakeLists.txt**
   - Standard emdawnwebgpu setup.
   - Export functions to update mouse/audio uniforms.

2. **wasm_renderer/main.cpp**
   - Create device/queue
   - Allocate buffers for agent state
   - Upload uniforms (mouse, rageMultiplier)
   - Compile and dispatch compute shader `raptor_mini_compute.wgsl`.
   - Draw agents through a render pipeline applying scale shading.

3. **raptor_mini_compute.wgsl**
   - Agent struct: vec2 pos; vec2 dir; float rageTimer;
   - Compute kernel: sense, steer, move, maybe claw attack.
   - Use ping-pong buffers for state.
   - Update rageTimer based on audio uniform.
   - Generate scale UV and claw highlight info for rendering.

4. **src/components/ShaderCanvas.tsx**
   - Manage WebGPU context and coordinate JS vs WASM renderer.
   - Reactivity to parameter controls (agent count, etc.).

5. **src/renderer/WASMRenderer.ts**
   - Load `raptor_mini_wasm.js` and provide init(), render().
   - Pass mouse coords and audio rage multiplier each frame.

6. **src/renderer/JSRenderer.ts**
   - Mirror compute shader logic in WGSL executed from JS.
   - Shared shader file (`raptorMini.wgsl`) for consistency.

7. **hooks/useAudioAnalyzer.ts**
   - Compute rageMultiplier based on audio amplitude.
   - Provide event when rage begins/ends (optional UI flash).

8. **hooks/useMouseTracker.ts**
   - Return normalized cursor position for shader.

9. **Application Integration**
   - Import hooks in App.tsx.
   - Provide UI for toggling JS/WASM and adjusting parameters.
   - Optionally display rage indicator and agent count slider.

10. **Build & Test**
    ```bash
    cd wasm_renderer && ./build.sh
    npm run build
    ```

11. **Queue Update**
    ```bash
    python scripts/manage_queue.py complete "2026-03-08_raptor-mini.md"
    ```

## Success Criteria
- [ ] Shader runs at 60fps with 8,192 agents and <5ms CPU frame time
- [ ] Agents chase mouse cursor and perform claw strikes occasionally
- [ ] Scale patterns visible on agents; appear natural and varied
- [ ] Audio input triggers rage mode with noticeable speed/attack boost
- [ ] Switch between JS and WASM renderer works seamlessly
- [ ] Code compiles in WASM with no warnings; JS fallback matches visual output

---
