# Swarm Brief: interactive-zoom-blur

**Role:** Optimizer
**Name:** Interactive Zoom Blur
**Category:** distortion
**Description:** Radial zoom blur centered on the mouse cursor with temporal blur trail persistence, chromatic radial streak separation, depth-scaled blur attenuation, dithered sampling, and audio-reactive intensity.
**Current lines:** 115
**Target lines:** 165–205 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This dithered chromatic zoom blur is well-built but the blur epicenter snaps to the cursor and clicks never punch the tunnel. Precision work:
- Spring-damper the epicenter (priority 1): ease the mouse center with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the tunnel glides; raw mouse stays the spring target. The spring LAG also feeds a subtle motion bonus: strength *= 1.0 + min(springSpeed * 4.0, 0.5) so fast flicks smear harder.
- Click zoom shockwaves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial blur pulse centered at its click point (local attenuatedStrength boost exp(-rippleAge * 2.0) in an aspect-corrected ~0.3 radius, ~1.2s fade), so clicks detonate secondary tunnels.
- Per-ring FFT voices: inside the sample loop, modulate each tap's weight by a bin selected from the fractional radius (`plasmaBuffer[(u32(t * 8.0) % 8u) + 1u].x * 0.15`), so blur rings shimmer across the spectrum. Fix the stale header ('Category: image' -> distortion, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the bayer() 4x4 dither, the hash11 helper, the 3-accumulator r/g/b chromatic loop structure with its rSpread/gSpread/bSpread, the sample-count mapping, the depth attenuation, the temporal trail mix (C read, 0.88 decay), and the effectBlend smoothstep VERBATIM - the streak quality is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "interactive-zoom-blur",
  "name": "Interactive Zoom Blur",
  "url": "shaders/interactive-zoom-blur.wgsl",
  "description": "Radial zoom blur centered on the mouse cursor with temporal blur trail persistence, chromatic radial streak separation, depth-scaled blur attenuation, dithered sampling, and audio-reactive intensity.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba",
    "temporal",
    "chromatic",
    "depth-aware"
  ],
  "params": [
    {
      "id": "strength",
      "name": "Blur Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "chromatic",
      "name": "Chromatic Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "sampleCount",
      "name": "Quality",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "depthAttenuation",
      "name": "Depth Attenuation",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "tags": [
    "filter",
    "image-processing",
    "zoom",
    "radial",
    "blur",
    "chromatic",
    "temporal",
    "audio-reactive",
    "depth-aware"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Blur Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Chromatic Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Quality",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Depth Attenuation",
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
//  Interactive Zoom Blur
//  Category: image
//  Features: mouse-centered, chromatic-aberration, dithered-sampling, audio-reactive,
//            temporal-blur-trail, chromatic-radial-streaks, depth-blur-attenuation
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

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn bayer(x: i32, y: i32) -> f32 {
    let matrix = array<f32, 16>(
        0.0, 0.5, 0.125, 0.625,
        0.75, 0.25, 0.875, 0.375,
        0.1875, 0.6875, 0.0625, 0.5625,
        0.9375, 0.4375, 0.8125, 0.3125
    );
    return matrix[(y % 4) * 4 + (x % 4)];
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

    let center = u.zoom_config.yz;
    let strength = u.zoom_params.x * (1.0 + bass * 0.25);
    let chromatic = u.zoom_params.y;
    let sampleCount = u.zoom_params.z;
    let depthAttenuation = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let dir = uv - center;
    let dist = length(dir);
    let dirNorm = normalize(dir + vec2<f32>(1e-4));

    // Depth-scaled blur attenuation: deeper pixels blur less
    let attenuatedStrength = strength * (1.0 - depth * depthAttenuation);

    let samples = i32(sampleCount * 30.0 + 5.0);
    let dither = bayer(i32(global_id.x), i32(global_id.y)) / f32(samples);

    // Chromatic radial streak separation
    let rSpread = chromatic * 0.008 * (1.0 + treble * 0.3);
    let gSpread = chromatic * 0.008;
    let bSpread = chromatic * 0.008 * (1.0 - bass * 0.2);

    var rAcc = vec3<f32>(0.0);
    var gAcc = vec3<f32>(0.0);
    var bAcc = vec3<f32>(0.0);

    for (var i: i32 = 0; i < samples; i = i + 1) {
        let t = (f32(i) + dither) / f32(samples);
        let rT = t + rSpread * t;
        let gT = t;
        let bT = t - bSpread * t;
        rAcc += textureSampleLevel(readTexture, u_sampler, clamp(center + dir * (1.0 + rT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        gAcc += textureSampleLevel(readTexture, u_sampler, clamp(center + dir * (1.0 + gT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        bAcc += textureSampleLevel(readTexture, u_sampler, clamp(center + dir * (1.0 + bT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    let invSamples = 1.0 / f32(samples);
    rAcc *= invSamples;
    gAcc *= invSamples;
    bAcc *= invSamples;

    var color = vec3<f32>(rAcc.r, gAcc.g, bAcc.b);

    // Temporal blur trail persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let trail = mix(color, prev * 0.88, 0.05 + mids * 0.02);
    color = mix(color, trail, 0.3);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let effectBlend = smoothstep(0.0, 1.0, dist * attenuatedStrength);
    color = mix(baseColor.rgb, color, effectBlend);

    let alpha = mix(baseColor.a, 1.0, effectBlend * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
```
