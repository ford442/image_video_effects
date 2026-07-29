# Swarm Brief: interactive-glitch-brush

**Role:** Interactivist
**Name:** Glitch Brush
**Category:** interactive-mouse
**Description:** Paint digital glitches onto the screen with audio-reactive intensity.
**Current lines:** 95
**Target lines:** 145–185 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This glitch brush works but the brush has no weight and clicks do nothing - give it glide and click burst grenades:
- Spring-damper the brush (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..134]) so the brush trails the cursor with a little lag - glitch smears feel painted, not teleported.
- Click glitch grenades: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns a temporary glitch zone at its click point (radius ~ brushSize, decaying over ~1s) that forces block displacement + inversion inside the zone even away from the brush.
- Per-channel split shimmer: drive the r/b sample offsets from DIFFERENT treble bins (`plasmaBuffer[5].x` vs `plasmaBuffer[8].x`) instead of one global colorSplit, so the chromatic tear shimmers across the spectrum; keep the slider as the base amount.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: this shader is deliberately BRANCHLESS (select()-based, see docs/BRANCHLESS_PATTERNS.md) - keep new logic branchless too (select/step/smoothstep, no if/discount on per-pixel paths). Preserve the blockUV quantization and scanline modulo VERBATIM. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "interactive-glitch-brush",
  "name": "Glitch Brush",
  "url": "shaders/interactive-glitch-brush.wgsl",
  "description": "Paint digital glitches onto the screen with audio-reactive intensity.",
  "params": [
    {
      "id": "brush_size",
      "name": "Brush Size",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "intensity",
      "name": "Glitch Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "block_scale",
      "name": "Block Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "color_split",
      "name": "Color Split",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "features": [
    "mouse-driven",
    "glitch",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "glitch",
    "interactive",
    "brush",
    "mouse-driven",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Brush Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Glitch Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Block Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Split",
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
//  Interactive Glitch Brush
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let brushSize = max(u.zoom_params.x * 0.3 + 0.05, 0.001);
    let intensity = clamp(u.zoom_params.y, 0.0, 1.0);
    let blockScale = max(u.zoom_params.z * 50.0 + 5.0, 0.001);
    let colorSplit = clamp(u.zoom_params.w * 0.1, 0.0, 1.0);

    let audioIntensity = intensity * (1.0 + bass * 0.5 + mids * 0.25);

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let mouseValid = mousePos.x >= 0.0;
    let diff = mousePos - uv;
    let diffAspect = vec2<f32>(diff.x * aspect, diff.y);
    let dist = length(diffAspect);
    let inBrush = mouseValid && (dist < brushSize);

    let blockUV = floor(uv * blockScale) / blockScale;
    let noise = random(blockUV + vec2<f32>(time * 0.1));
    let offsetX = select(0.0, (random(vec2<f32>(noise, time)) - 0.5) * audioIntensity * 0.2, noise > 0.5);
    let offset = vec2<f32>(offsetX, 0.0);

    let sampleUV_r = clamp(uv + offset - vec2<f32>(colorSplit, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV_g = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV_b = clamp(uv + offset + vec2<f32>(colorSplit, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, sampleUV_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV_b, 0.0).b;

    let invertCond = random(vec2<f32>(time, noise)) > 0.95;
    let glitchR = select(r, 1.0 - r, invertCond);
    let glitchG = select(g, 1.0 - g, invertCond);
    let glitchB = select(b, 1.0 - b, invertCond);

    let glitchLuma = 0.299 * glitchR + 0.587 * glitchG + 0.114 * glitchB;
    let glitchAlpha = clamp(glitchLuma + treble * 0.1, 0.1, 1.0);
    var glitchColor = vec4<f32>(glitchR, glitchG, glitchB, glitchAlpha);

    let scanlineCond = fract(uv.y * resolution.y * 0.5) < 0.5;
    glitchColor = select(glitchColor, glitchColor * 0.8, scanlineCond);

    color = select(color, glitchColor, inBrush);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, color);
    textureStore(dataTextureA, global_id.xy, color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
