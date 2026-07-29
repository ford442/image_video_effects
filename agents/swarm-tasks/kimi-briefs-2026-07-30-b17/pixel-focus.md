# Swarm Brief: pixel-focus

**Role:** Optimizer
**Name:** Pixel Focus
**Category:** interactive-mouse
**Description:** Applies a mosaic effect everywhere except for a clear focus area around the mouse. Audio-reactive density adds rhythmic pulse to pixelation.
**Current lines:** 95
**Target lines:** 145–185 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This focus lens reads the depth buffer but ignores it - make depth drive the focus, then add click pulses and spectral mosaic shimmer:
- DEPTH-AWARE FOCUS (priority 1): the shader samples readDepthTexture only to pass it through. Modulate the focus radius by scene depth - e.g. `focusRadius *= mix(0.7, 1.3, depth)` - so near/far content falls out of focus differently (reads as a real lens); keep the slider as the base radius.
- Click focus pulses: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple emits an expanding SHARP ring (a band where focus = 1 regardless of distance) from its click point, decaying over ~1.5s, so clicks snap a ring of clarity across the mosaic.
- Spectral mosaic shimmer: add a subtle per-bin modulation of the pixel density from bass/mid bins (`plasmaBuffer[1..4]`) so the mosaic breathes with the music beyond the existing global bass term; keep density >= 1.0 guard.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the branchless chromatic mix (useChromatic step + mix) and the alpha-from-luma formula VERBATIM. Keep all three texture samples unconditional (no divergent sampling). dataTextureA stays DISPLAY color.

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
  "id": "pixel-focus",
  "name": "Pixel Focus",
  "url": "shaders/pixel-focus.wgsl",
  "description": "Applies a mosaic effect everywhere except for a clear focus area around the mouse. Audio-reactive density adds rhythmic pulse to pixelation.",
  "params": [
    {
      "id": "mosaicSize",
      "name": "Block Size",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "radius",
      "name": "Focus Radius",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "hardness",
      "name": "Edge Hardness",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "chromatic",
      "name": "Aberration",
      "default": 0,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "filter",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "pixelation",
    "focus",
    "mosaic",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Block Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Focus Radius",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Edge Hardness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Aberration",
      "default": 0,
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
//  Pixel Focus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, filter, pixelation, chromatic-aberration, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-28
//  By: Agent 1a - Alpha Channel Specialist
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 0.001);
    var mouse = u.zoom_config.yz;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let mosaicSize = clamp(u.zoom_params.x, 0.0, 1.0);
    let focusRadius = mix(0.01, 0.5, clamp(u.zoom_params.y, 0.0, 1.0));
    let hardness = clamp(u.zoom_params.z, 0.0, 1.0);
    let chromatic = clamp(u.zoom_params.w + treble * 0.1, 0.0, 1.0);

    // Calculate distance to mouse
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    // Mixing factor: 0.0 = Pixelated, 1.0 = Clear
    let focus = clamp(
        1.0 - smoothstep(focusRadius, focusRadius + (1.0 - hardness) * 0.2, dist),
        0.0, 1.0
    );

    // Pixelation Logic
    var density = (50.0 + (1.0 - mosaicSize) * 450.0) * (1.0 + bass * 0.1 + mids * 0.05);
    density = max(density, 1.0);
    let pixelUV = floor(uv * density) / density;

    // Sample Clear and preserve input alpha
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let colClear = baseColor.rgb;

    // Sample Pixelated — branchless chromatic aberration
    let useChromatic = step(0.05, chromatic);
    let offset = chromatic * 0.01;
    let plainSample = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0);
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(pixelUV + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(pixelUV - vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let colPixel = vec3<f32>(
        mix(plainSample.r, rSample.r, useChromatic),
        plainSample.g,
        mix(plainSample.b, bSample.b, useChromatic)
    );

    let finalRGB = mix(colPixel, colClear, focus);

    // Alpha: preserve input alpha, modulated by focus region and luma
    let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(baseColor.a * (focus * 0.6 + luma * 0.3 + 0.1), 0.0, 1.0);
    let finalColor = vec4<f32>(finalRGB, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
