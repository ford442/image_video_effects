# Renderer module map

TypeScript WebGPU renderer split mirrors the C++ WASM layout (#965).

## TS ↔ C++ parity

| TypeScript | C++ | Responsibility |
|------------|-----|----------------|
| [`webgpu/device.ts`](webgpu/device.ts) | `wasm_renderer/device.cpp` | Adapter/device init, device-lost |
| [`webgpu/resources.ts`](webgpu/resources.ts) | `wasm_renderer/resources.cpp` | Textures, buffers, samplers, resize |
| [`webgpu/pipeline.ts`](webgpu/pipeline.ts) | `wasm_renderer/pipeline.cpp` | Bind groups, blit/compute pipelines, shader cache |
| [`webgpu/frame.ts`](webgpu/frame.ts) | `wasm_renderer/frame.cpp` | RAF loop, slot dispatch, present |
| [`webgpu/audioDepth.ts`](webgpu/audioDepth.ts) | `wasm_renderer/audio_depth.cpp` | FFT bins, depth upload, extraBuffer |
| [`WebGPURenderer.ts`](WebGPURenderer.ts) | `wasm_renderer/renderer.cpp` | Thin `IRenderer` facade |

## Supporting modules

| Module | Role |
|--------|------|
| [`webgpu/WebGPUTiming.ts`](webgpu/WebGPUTiming.ts) | GPU timestamp queries (`timing.cpp`) |
| [`webgpu/WebGPUMediaInput.ts`](webgpu/WebGPUMediaInput.ts) | Image/video upload |
| [`webgpu/webgpuConstants.ts`](webgpu/webgpuConstants.ts) | Shared constants and slot types |
| [`webgpuDevicePolicy.ts`](webgpuDevicePolicy.ts) | Adapter contract (shared with C++) |

## Pure dependencies (unchanged)

- [`slotOrchestrator.ts`](slotOrchestrator.ts)
- [`UniformBuffer.ts`](UniformBuffer.ts)
- [`ShaderCompilation.ts`](ShaderCompilation.ts)
- [`GraphRunner.ts`](GraphRunner.ts) — Tier-C multipass graphs ([`docs/MULTIPASS_GRAPH.md`](../docs/MULTIPASS_GRAPH.md), wired from `frame.ts`)

## Tests

```bash
npx react-scripts test --watchAll=false --ci src/renderer/webgpu/
```
