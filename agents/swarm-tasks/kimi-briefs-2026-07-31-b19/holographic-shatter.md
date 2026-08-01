# Swarm Brief: holographic-shatter

**Role:** Algorithmist
**Name:** Holographic Shatter
**Category:** image
**Description:** Fractures the image into digital shards with temporal shard velocity persistence, chromatic edge refraction per shard, audio-driven impact intensity, holographic interference patterns, and plasma palette tinting.
**Current lines:** 103
**Target lines:** 153–193 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This shatter has THREE bugs: an out-of-bounds palette read, a 'Depth Weight' slider that is completely dead (depthLayeredAlpha is never called), and an impact falloff that is inverted - pressing the mouse shatters everything EXCEPT where you click. Fix the plumbing:
- GUARD THE PALETTE READ + WIRE THE DEAD SLIDER (priority 1): (a) `plasmaBuffer[palIdx % 256u]` can index past the real FFT bin count (OOB storage reads return zeros - dead black palette); wrap to the live range instead (`(palIdx % 8u) + 1u`, bins 1-8). (b) depthWeight (zoom_params.z) is read but depthLayeredAlpha() is NEVER CALLED - the slider does nothing. Wire it: `finalAlpha = mix(baseColor.a, depthLayeredAlpha(finalColor, uv, depthWeight), clamp(effectIntensity, 0.0, 1.0))` so z blends between source alpha and the depth/luma-tiered alpha (default 0.5 keeps the alpha lively without flattening).
- FIX THE INVERTED IMPACT: `impact = (0.4 + mouseDown * 0.6) * smoothstep(0.0, 0.6, dM)` GROWS with distance from the mouse - mouse-down flings far shards while the cursor zone sits still. Invert the falloff to near-focused (`smoothstep(0.6, 0.0, dM)`) but keep a small global baseline (`impact = max(nearImpact, 0.25 * (0.4 + mouseDown * 0.6))`) so the idle/far-field drift survives.
- Click shatter detonations: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a decaying impact center (same flightDir math with the ripple position as origin, weight exp(-age * 2.5), ~1.5s), so individual clicks crack the glass even with the button up. Normalize the odd depth write `vec4(depth, 0, 0, 1)` to `vec4(depth, 0.0, 0.0, 0.0)` (depth value itself passthrough).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the rand() helper, the shard grid + edgeGlow construction, the holographic phase/palette sin() math (only the plasmaBuffer INDEX changes), the temporal settling (C read * 0.92, mix 0.06 + bass*0.02), and the depthLayeredAlpha helper body VERBATIM. dataTextureA stays DISPLAY color (raw - the C feedback expects color, not masks). extraBuffer (if used) in [133..255] ONLY.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "holographic-shatter",
  "name": "Holographic Shatter",
  "url": "shaders/holographic-shatter.wgsl",
  "description": "Fractures the image into digital shards with temporal shard velocity persistence, chromatic edge refraction per shard, audio-driven impact intensity, holographic interference patterns, and plasma palette tinting.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven",
    "upgraded-rgba",
    "temporal",
    "chromatic",
    "depth-aware"
  ],
  "params": [
    {
      "id": "shatterAmount",
      "name": "Shatter Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "holo",
      "name": "Hologram Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "depthWeight",
      "name": "Depth Weight",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "shardCount",
      "name": "Shard Count",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "tags": [
    "filter",
    "image-processing",
    "audio",
    "music",
    "shatter",
    "holographic",
    "chromatic",
    "temporal",
    "shard"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Shatter Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Hologram Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Depth Weight",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Shard Count",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Holographic Shatter
//  Category: image
//  Features: advanced-alpha, holographic, shatter, glass, mouse-driven, audio-reactive,
//            temporal-shard-persistence, audio-impact, chromatic-edge-refraction
//  Complexity: High
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════

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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let shatterAmount = clamp(u.zoom_params.x * (1.0 + bass * 0.4), 0.0, 1.0);
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let shardCount = u.zoom_params.w * 50.0 + 10.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dM = distance(uv, mouse);
    let impact = (0.4 + mouseDown * 0.6) * smoothstep(0.0, 0.6, dM);

    let gridUV = uv * shardCount;
    let shardId = floor(gridUV);
    let shardUv = fract(gridUV);

    let shardRand = rand(shardId);
    let shardCenter = (shardId + 0.5) / shardCount;
    let flightDir = normalize(shardCenter - mouse + vec2<f32>(1e-4));
    // Audio-driven impact force
    let offset = flightDir * shatterAmount * impact * (0.4 + shardRand * 0.6) * (1.0 + treble * 0.3);

    let warpedUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let edgeDist = min(min(shardUv.x, 1.0 - shardUv.x), min(shardUv.y, 1.0 - shardUv.y));
    let edgeGlow = smoothstep(0.1, 0.0, edgeDist);

    // Chromatic edge refraction per shard
    let phase = time + shardRand * TAU + depth * PI;
    let holographic = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));
    let palIdx = u32(clamp((shardRand + time * 0.05) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    let foil = mix(holographic, holographic * (0.6 + palette * 0.7), 0.4);

    // Temporal shard persistence: previous frame offsets blend for settling glass
    let prevShards = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let settled = mix(sample.rgb, prevShards * 0.92, 0.06 + bass * 0.02);

    let finalColor = mix(settled, foil, edgeGlow * holographicIntensity);
    let effectIntensity = edgeGlow * holographicIntensity + shatterAmount * 0.5;
    let finalAlpha = mix(baseColor.a, 1.0, clamp(effectIntensity * 0.7, 0.0, 1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
```
