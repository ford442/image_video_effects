# Internal Texture Format Tiers (#1008)

## Problem

Internal sim/display textures are **`rgba32float`** at up to **2048²** with multiple ping-pong targets (`write`, `dataA/B/C`, `history`, `read`, `source`). That is quality-correct for HDR sims and multi-pass feedback, but roughly **4×** the bandwidth of `rgba16float` for pure visual effects.

Memory sketch (order of magnitude, 2048²):

| Target count | rgba32float | rgba16float |
|--------------|-------------|-------------|
| 1× | ~64 MiB | ~32 MiB |
| ~6 storage/sampled rgba targets | ~384 MiB | ~192 MiB |

Adaptive resolution scaling alone cannot save integrated GPUs when format bandwidth dominates.

## Design decision: storage demotion, not present-only

**Present is already cheap.** The canvas blit targets `bgra8unorm` (browser preferred format). Demoting only the present path saves ~0 MiB.

**Storage demotion is where the savings are.** All internal rgba targets in [`src/renderer/webgpu/resources.ts`](../src/renderer/webgpu/resources.ts) share one tier-selected format. Depth textures remain **`r32float`** (wave height, RD concentrations in depth channel).

WGSL sources in `public/shaders/` stay authored as **`rgba32float`** canonical. The host rewrites storage declarations at pipeline compile time for non-ultra tiers (see [`src/renderer/wgslFormatRewrite.ts`](../src/renderer/wgslFormatRewrite.ts)).

## Quality tiers

| Tier | `colorFormat` | Typical scale | Use |
|------|---------------|---------------|-----|
| `ultra` | `rgba32float` | 1.0× | Desktop discrete, physics sims — **bit-compatible with pre-tiering sims** |
| `balanced` | `rgba16float` | 0.75× | Default laptop / modern iGPU |
| `battery` | `rgba16float` | 0.5× | Mobile / thermal |
| `auto` | probe-driven | adaptive | FP16 on integrated/mobile; FP32 on discrete |

**`compat` (`rgba8unorm`) — Phase 2.** Many shaders use HDR, negative intermediates, and alpha > 1. Not enabled in the initial rollout.

## Physics / precision guard

Shaders that need full FP32 storage (reaction-diffusion concentrations, fluid state, wave sims) may declare:

```json
"requiresRgba32Float": true
```

When the active quality tier is not `ultra`, loading such a shader **auto-bumps render quality to ultra** (with a console warning). Category `simulation` and tags `physics` / `reaction-diffusion` / `fluid` are inferred as FP32-required when the flag is omitted.

Do **not** silently run physics sims at FP16.

## Host rewrite contract

Bindings rewritten (storage write only):

| Binding | WGSL name | Ultra | Balanced / Battery |
|---------|-----------|-------|-------------------|
| 2 | `writeTexture` | `rgba32float` | `rgba16float` |
| 7 | `dataTextureA` | `rgba32float` | `rgba16float` |
| 8 | `dataTextureB` | `rgba32float` | `rgba16float` |
| 6 | `writeDepthTexture` | `r32float` | `r32float` (unchanged) |

Pipeline cache keys include `colorFormat`. Tier changes destroy textures, rebuild bind-group layout, and clear the shader cache.

## Capability probe

At device init ([`src/renderer/webgpu/device.ts`](../src/renderer/webgpu/device.ts)):

- `adapter.info` GPU type: discrete / integrated / cpu
- `float32-filterable` (existing)
- `maxTextureDimension2D` (existing)

Resolved in [`src/config/formatPolicy.ts`](../src/config/formatPolicy.ts).

## C++ WASM parity

[`wasm_renderer/resources.cpp`](../wasm_renderer/resources.cpp) and [`wasm_renderer/pipeline.cpp`](../wasm_renderer/pipeline.cpp) use the same tier mapping via [`wasm_renderer/performance_policy.h`](../wasm_renderer/performance_policy.h). WGSL rewrite runs in TypeScript before `loadShader()` passes source to C++.

## Benchmarking

Use `?testMode=1` and `__pixelocity__.runBenchmark(frames, { qualityMode: 'balanced' })` to record `colorFormat` and `estimatedTextureMiB`. Compare `ultra` vs `balanced` on the same hardware (document adapter in report).

Priority shaders: `sim-fluid-feedback-coupled`, `gen-lichen-reaction-diffusion`, `plasma`.

## Related

- [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md) — bind-group layout; storage format is tier-dependent at runtime
- [`src/config/performancePolicy.ts`](../src/config/performancePolicy.ts) — scale, slots, passes + `colorFormat`
- MEMORY.md — "don't downgrade rgba32float without tiering"
