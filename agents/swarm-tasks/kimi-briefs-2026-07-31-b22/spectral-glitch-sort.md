# Swarm Brief: spectral-glitch-sort

**Role:** Optimizer
**Name:** Spectral Glitch Sort
**Category:** retro-glitch
**Description:** Displaces pixels based on their brightness, creating a glitchy sorting effect controlled by the mouse.
**Current lines:** 108
**Target lines:** 158–198 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This luma sort is honest and branchless - but the mouse influence is elliptical (no aspect correction), the cursor snaps, and clicks do nothing. Precision work:
- Aspect-correct + spring the influence (priority 1): `mouseDist = distance(uv, mouse)` ignores aspect - on wide canvases the influence zone is an ellipse; correct both uv and mouse by (aspect, 1.0). Then ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the sort epicenter glides.
- Click sort tears: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying directional tear at its click point (local finalStrength spike + a brief angle perturbation, ~0.8s fade), so clicks rip the sort.
- Per-block FFT voices: modulate the noiseVal block hash by FFT bins (`plasmaBuffer[(u32(blockUV.x * 8.0) % 8u) + 1u].x`) so the glitch blocks flicker with the spectrum instead of uniformly.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the getLuma/hash12 helpers, the dispFactor threshold smoothstep, the dir/offset displacement, the branchless chromatic aberration (aberScale + r/b mix), and the treble shimmer VERBATIM (docs/BRANCHLESS_PATTERNS.md). All 4 sliders honestly wired (Direction default 0 = 0 radians) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "spectral-glitch-sort",
  "name": "Spectral Glitch Sort",
  "url": "shaders/spectral-glitch-sort.wgsl",
  "features": [
    "mouse-driven",
    "chromatic-aberration",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "description": "Displaces pixels based on their brightness, creating a glitchy sorting effect controlled by the mouse.",
  "params": [
    {
      "id": "strength",
      "name": "Sort Length",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "threshold",
      "name": "Luma Threshold",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "angle",
      "name": "Direction",
      "default": 0,
      "min": 0,
      "max": 1
    },
    {
      "id": "noise",
      "name": "Digital Noise",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "glitch",
    "retro",
    "vintage"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Sort Length",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Luma Threshold",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Direction",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Digital Noise",
      "default": 0.2,
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
//  Spectral Glitch Sort
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=Strength, y=Threshold, z=Angle, w=Noise
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / dims;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters — bass amplifies sort strength
    let strength    = mix(0.0, 0.5, u.zoom_params.x) * (1.0 + bass * 0.4);
    let threshold   = u.zoom_params.y;
    let angleParam  = u.zoom_params.z * 6.28;
    let noiseAmt    = u.zoom_params.w;

    let mouse     = u.zoom_config.yz;
    let mouseDist = distance(uv, mouse);

    let dir = vec2<f32>(cos(angleParam), sin(angleParam));

    let cSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let c = cSample.rgb;
    let luma = getLuma(c);

    let dispFactor = smoothstep(threshold, threshold + 0.2, luma);

    // Glitch noise block
    let blockUV  = floor(uv * 20.0) / 20.0;
    let noiseVal = hash12(blockUV + u.config.x * 0.1);

    // Mouse proximity increases strength
    let influence = 1.0 - smoothstep(0.0, 0.5, mouseDist);
    var finalStrength = strength * (1.0 + influence * 2.0);

    // Branchless noise modulation
    finalStrength *= mix(1.0, noiseVal * 2.0, noiseAmt);

    let offset  = -dir * finalStrength * dispFactor;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

    var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Chromatic aberration — branchless, scaled by offset magnitude
    let aberScale = smoothstep(0.005, 0.03, length(offset));
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    finalColor.r = mix(finalColor.r, rSample, aberScale);
    finalColor.b = mix(finalColor.b, bSample, aberScale);

    // Treble adds subtle high-freq shimmer
    finalColor += vec3<f32>(0.05) * treble * noiseVal;
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: sort displacement + luma + audio
    let alpha = clamp(dispFactor * 0.5 + aberScale * 0.3 + bass * 0.1 + cSample.a * 0.15, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
```
