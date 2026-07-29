# Swarm Brief: prismatic-feedback-loop

**Role:** Algorithmist
**Name:** Prismatic Feedback Loop (Pass 2)
**Category:** interactive-mouse
**Description:** Consumes displacement from Pass 1 to create chromatic aberration, temporal feedback, and glowing halos.
**Current lines:** 97
**Target lines:** 147–187 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Every one of this shader's four slider labels is a lie - 'Feedback' drives the accumulation rate, 'Blur Radius' drives prism strength, 'Glow Intensity' drives rotation, and 'Chromatic Spread' (default 0.02!) drives the feedback mix. Make the labels honest:
- REWIRE THE MISLABELED SLIDERS (priority 1): x ('Feedback', default 0.5) must drive the temporal feedback mix `mix(prev.rgb, prismColor, x)`; y ('Blur Radius', default 1) must drive the prism tap spread magnitude (reads as a blur/soften - map so default 1 reproduces the current ~0.1 offset scale); z ('Glow Intensity', default 0.8) must drive a real glow term (brightness lift of the accumulated trails, 0 at 0); w ('Chromatic Spread', default 0.02) must scale the chromatic r/b separation angle/amount (small default = subtle, matching its tiny default). Keep ids/names/defaults EXACTLY (saved-preset contract). The old rotation role can become a slow constant drift (time * 0.1).
- Fix the stale header comment claiming 'Category: image' (JSON lives in interactive-mouse) - comment-only.
- Click prism bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial chromatic kick centered on its click point (extra r/b separation fading over ~1.5s), so clicks shatter the prism locally.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the accumulativeAlpha() function and its select-based zero-guard VERBATIM - feedback stability depends on it. dataTextureA is ACCUMULATION STATE - never tonemap/clamp it beyond the existing caps; keep the A write and C read symmetric. Guard the feedback mix so values stay in [0,1] (runaway feedback blowout is the classic failure mode here).

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
  "id": "prismatic-feedback-loop",
  "name": "Prismatic Feedback Loop (Pass 2)",
  "url": "shaders/prismatic-feedback-loop.wgsl",
  "description": "Consumes displacement from Pass 1 to create chromatic aberration, temporal feedback, and glowing halos.",
  "params": [
    {
      "id": "feedbackAmount",
      "name": "Feedback",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "blurRadius",
      "name": "Blur Radius",
      "default": 1,
      "min": 0,
      "max": 10
    },
    {
      "id": "glowIntensity",
      "name": "Glow Intensity",
      "default": 0.8,
      "min": 0,
      "max": 2
    },
    {
      "id": "chromaticSpread",
      "name": "Chromatic Spread",
      "default": 0.02,
      "min": 0,
      "max": 0.2
    }
  ],
  "features": [
    "multi-pass",
    "feedback",
    "chromatic",
    "mouse-driven",
    "upgraded-rgba",
    "audio-reactive",
    "depth-aware"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Feedback",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Blur Radius",
      "default": 1,
      "min": 0.0,
      "max": 10.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Glow Intensity",
      "default": 0.8,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chromatic Spread",
      "default": 0.02,
      "min": 0.0,
      "max": 0.2,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Prismatic Feedback Loop
//  Category: image
//  Features: advanced-alpha, prismatic, feedback, chromatic, multi-pass
//  Complexity: High
//  Upgraded: 2026-05-23
//  upgraded-rgba
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
  zoom_params: vec4<f32>,  // x=AccumulationRate, y=PrismStrength, z=Rotation, w=Feedback
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let accumulationRate = u.zoom_params.x;
    let prismStrength = u.zoom_params.y * 0.1 * (1.0 + bass * 0.4 + treble * 0.3);
    let rotation = u.zoom_params.z * TAU * (1.0 + mids * 0.3);
    let feedback = u.zoom_params.w;
    
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Prismatic chromatic separation
    let centered = uv - 0.5;
    let c = cos(rotation + time * 0.1);
    let s = sin(rotation + time * 0.1);
    let rotated = vec2<f32>(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
    
    let rUV = uv + rotated * prismStrength;
    let gUV = uv;
    let bUV = uv - rotated * prismStrength;
    
    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    let prismColor = vec3<f32>(r, g, b);
    let blended = mix(prev.rgb, prismColor, feedback);
    
    let brightness = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = mix(baseColor.a, brightness, feedback);
    
    let accumulated = accumulativeAlpha(blended, newAlpha, prev.rgb, prev.a, accumulationRate);
    
    textureStore(dataTextureA, coord, accumulated);
    textureStore(writeTexture, global_id.xy, accumulated);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
