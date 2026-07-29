# Swarm Brief: holographic-sticker

**Role:** Visualist
**Name:** Holographic Sticker
**Category:** visual-effects
**Description:** Mouse-centered iridescent sticker with chromatic view-angle dispersion, temporal foil shimmer persistence, audio-driven sticker pulse, depth-layered alpha, and rainbow phase shift.
**Current lines:** 100
**Target lines:** 150–190 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This foil sticker has an out-of-bounds palette risk and a static feel - guard the read, then make it glide and flash:
- GUARD THE PALETTE READ (priority 1): `plasmaBuffer[palIdx % 256u]` can index past the actual FFT bin count (the engine publishes far fewer vec4 bins) - OOB storage reads return zeros (dead black palette). Wrap to the real bin range instead (`(palIdx % 8u) + 1u`, bins 1-8) so the palette modulation is always live audio data.
- Spring-damper the sticker: ease the mouse center with a critically-damped spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the foil glides after the cursor; raw mouse stays the spring target.
- Click foil flashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds an expanding iridescent flash ring (hue-cycling band matching the foil palette, decaying ~1.5s) centered on its click point, so clicks scatter rainbows.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the HSV foil construction (k-vec palette math), the viewAngle hue mapping, and the depthLayeredAlpha helper VERBATIM. The temporal shimmer (C read / A write) must stay subtle and raw - never tonemap the A write. The odd `vec4(depth, 0, 0, 1)` depth write is harmless - you may normalize it to (depth,0,0,0) but keep depth itself passthrough. extraBuffer in [133..255] ONLY.

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
  "id": "holographic-sticker",
  "name": "Holographic Sticker",
  "url": "shaders/holographic-sticker.wgsl",
  "description": "Mouse-centered iridescent sticker with chromatic view-angle dispersion, temporal foil shimmer persistence, audio-driven sticker pulse, depth-layered alpha, and rainbow phase shift.",
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
      "id": "radius",
      "name": "Sticker Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "intensity",
      "name": "Foil Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "rainbowSpeed",
      "name": "Rainbow Speed",
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
    }
  ],
  "tags": [
    "vfx",
    "particles",
    "glow",
    "audio",
    "music",
    "holographic",
    "sticker",
    "chromatic",
    "temporal",
    "iridescent"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Sticker Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Foil Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Rainbow Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Depth Weight",
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
//  Holographic Sticker
//  Category: image
//  Features: advanced-alpha, depth-aware, mouse-driven, audio-reactive, chromatic-view-angle,
//            temporal-foil-shimmer, audio-sticker-pulse, depth-layered-alpha
//  Complexity: Medium
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let radius = u.zoom_params.x;
    let intensity = u.zoom_params.y;
    let rainbowSpeed = u.zoom_params.z;
    let depthWeight = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let dM = length(uv - mouse);
    let aspect = resolution.x / resolution.y;

    let inCircle = smoothstep(radius, radius * 0.9, dM);

    let viewAngle = atan2((uv.y - mouse.y) * aspect, uv.x - mouse.x);
    let hue = fract(viewAngle / TAU + time * rainbowSpeed * 0.5 + depth * 0.1 + bass * 0.05);

    let saturation = 0.9 + treble * 0.1;
    let value = 0.8 + mids * 0.2;
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(vec3<f32>(hue, hue, hue) + k.xyz) * 6.0 - k.www);
    var foil = value * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);

    let palIdx = u32(clamp(hue * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    foil = mix(foil, foil * (0.7 + palette * 0.5), 0.3);

    let edgeGlow = smoothstep(radius * 1.1, radius, dM);
    foil = mix(foil, foil * 1.3, edgeGlow);

    // Audio-driven sticker pulse: radius expands/contracts with bass
    let pulse = 1.0 + bass * 0.2 * sin(time * 4.0);
    let pulsedCircle = smoothstep(radius * pulse, radius * 0.9 * pulse, dM);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var finalColor = mix(baseColor.rgb, baseColor.rgb * 0.4 + foil * intensity, pulsedCircle * inCircle);

    // Temporal foil shimmer: slow phase drift for organic iridescence
    let prevFoil = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let shimmer = mix(finalColor, prevFoil * 0.95, 0.04 + mids * 0.015);
    finalColor = mix(finalColor, shimmer, 0.4);

    let alpha = depthLayeredAlpha(finalColor, uv, depthWeight);
    let stickerAlpha = mix(baseColor.a, 1.0, inCircle * 0.8);
    let finalAlpha = mix(alpha, stickerAlpha, inCircle * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
```
