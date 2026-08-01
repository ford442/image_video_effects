# Swarm Brief: spectral-rain

**Role:** Visualist
**Name:** Spectral Rain
**Category:** visual-effects
**Description:** Falling streaks of chromatic distortion with audio-reactive intensity and mouse-driven angle and speed controls.
**Current lines:** 104
**Target lines:** 154–194 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This chromatic rain reads bass but declares mids and treble and NEVER USES THEM - dead audio reads. The rain angle/speed snap with the mouse. Make the whole spectrum fall:
- Per-column FFT voices (priority 1): kill the dead mids/treble reads by giving each rain column its own bin (`plasmaBuffer[(u32(gridID.x) % 8u) + 1u].x` - gridID.x is f32, cast it): bin amplitude modulates that column's drop brightness (`bright` term) and trail length (+-20%), so the streaks shimmer across the spectrum instead of all following global bass.
- Spring-damper the rain controls: ease the mouse-derived angleVal/speedVal with critically-damped springs (extraBuffer[133..138]: angle pos+vel, speed pos+vel; [0..4] reserved, [5..132] = engine FFT) so direction changes sweep smoothly; raw mouse stays the spring target.
- Click splash bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a radial chromatic splash at its click point (a decaying displace kick ~0.03 amplitude, ~1.0s fade, along the aspect-corrected radial direction), so clicks splatter the rain.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash12 helper, the rotated-grid rain construction (rotMat/rotUV/gridUV/colSpeed/dropNoise/drop), the displace vec2(s,c) structure, and the r/g/b samplePos/sampleNeg taps VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY (note rain_angle_scale's 0-1.5 range). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "spectral-rain",
  "url": "shaders/spectral-rain.wgsl",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "density",
      "name": "Rain Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Density of rain streaks"
    },
    {
      "id": "chromatic_strength",
      "name": "Chromatic Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Strength of chromatic displacement"
    },
    {
      "id": "trail_length",
      "name": "Trail Length",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Length of raindrop trails"
    },
    {
      "id": "rain_angle_scale",
      "name": "Rain Angle Scale",
      "default": 0.5,
      "min": 0,
      "max": 1.5,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Scale of the rain angle variation"
    }
  ],
  "tags": [
    "rain",
    "chromatic",
    "distortion",
    "filter",
    "image-processing",
    "audio-reactive"
  ],
  "name": "Spectral Rain",
  "description": "Falling streaks of chromatic distortion with audio-reactive intensity and mouse-driven angle and speed controls.",
  "updatedParams": [
    {
      "index": 0,
      "name": "Rain Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Chromatic Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Trail Length",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Rain Angle Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.5,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Spectral Rain
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  By: Phase A Upgrade Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=ChromaticStr, z=TrailLen, w=AngleControl
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse Controls
    var mouse = u.zoom_config.yz;
    let angleVal = (mouse.x - 0.5) * 2.0;
    let speedVal = mouse.y * 2.0 + 0.5;

    // Params
    let density = u.zoom_params.x * 20.0 + 5.0;
    let chromaticStr = u.zoom_params.y * 0.05 * (1.0 + bass * 0.4);
    let trailLen = u.zoom_params.z * 0.5 + 0.1;

    // Rotate UV for rain direction
    let angle = angleVal * mix(0.0, 1.5, u.zoom_params.w);
    let c = cos(angle);
    let s = sin(angle);
    let rotMat = mat2x2<f32>(c, -s, s, c);

    let rotUV = rotMat * (uv * vec2<f32>(aspect, 1.0));

    // Rain generation
    let gridUV = rotUV * density;
    let gridID = floor(gridUV);
    let gridOffset = fract(gridUV);

    let colSpeed = hash12(vec2<f32>(gridID.x, 0.0)) * 0.5 + 0.5;
    let yPos = rotUV.y + time * speedVal * colSpeed;
    let dropNoise = fract(yPos * density * 0.1 + hash12(vec2<f32>(gridID.x, 10.0)) * 100.0);
    let drop = smoothstep(1.0 - trailLen, 1.0, dropNoise);

    // Apply displacement
    let displace = vec2<f32>(s, c) * drop * chromaticStr;

    let samplePos = clamp(uv + displace, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleNeg = clamp(uv - displace, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleNeg, 0.0).b;

    let bright = drop * 0.1;

    // Semantic alpha
    let baseLum = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(drop * 0.6 + bright * 2.0 + length(displace) * 8.0 + baseLum * 0.15 + 0.1, 0.1, 1.0);

    let finalRGB = vec3<f32>(r + bright, g + bright, b + bright);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
```
