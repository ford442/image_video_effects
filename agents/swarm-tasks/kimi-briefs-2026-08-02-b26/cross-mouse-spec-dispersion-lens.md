# Swarm Brief: cross-mouse-spec-dispersion-lens

**Role:** Algorithmist
**Name:** Prismatic Lens
**Category:** interactive-mouse
**Description:** Crossover shader combining mouse-driven lens interaction with physical spectral dispersion. The cursor becomes a prismatic lens that refracts RGB channels differently using Cauchy's equation.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This Cauchy-dispersion lens has two problems: the lens is ELLIPTICAL on any non-square canvas (mouseDist never aspect-corrects) and treble sits unused while bass/mids do all the work. Fix the geometry, then the spectrum:
- ASPECT-CORRECT THE LENS (priority 1): `mouseDist = length(toMouse)` ignores aspect - on wide canvases the 'circular' lens is an ellipse; correct both uv and mousePos by (aspect, 1.0) before the distance (and use the same corrected vector for the refraction normal so dispersion stays radial). Verify the rim gaussian uses the corrected distance.
- Spring-damper + wire treble: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the prism glides; raw mouse stays the spring target. Wire the unused treble: per-channel sparkle - the dispR/dispB split shimmers by `plasmaBuffer[6].x * 0.3` and `plasmaBuffer[8].x * 0.3` respectively, so high frequencies twinkle the fringes.
- Click spectrum flares: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying dispersion burst at its click point (local localDispersion spike exp(-rippleAge * 2.0) * 1.5 in an aspect-corrected ~0.25 radius, ~1.2s fade) plus a brief spectral ring at the burst edge, so clicks scatter rainbows beyond the held-button boost.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the cauchyIOR helper, the n0/B constants, the 650/530/460nm wavelengths, the parabolic lensProfile, the time-rotation matrix, the per-channel r/g/b sample split, and the rim gaussian form VERBATIM - the spectral physics are the identity. The mouseDown clickBoost (select 1.0/2.0) stays. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "cross-mouse-spec-dispersion-lens",
  "name": "Prismatic Lens",
  "url": "shaders/cross-mouse-spec-dispersion-lens.wgsl",
  "description": "Crossover shader combining mouse-driven lens interaction with physical spectral dispersion. The cursor becomes a prismatic lens that refracts RGB channels differently using Cauchy's equation.",
  "tags": [
    "crossover",
    "mouse-driven",
    "prismatic",
    "dispersion",
    "lens",
    "refraction",
    "chromatic"
  ],
  "features": [
    "crossover",
    "mouse-driven",
    "spectral-rendering",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "lensRadius",
      "name": "Lens Radius",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "dispersionScale",
      "name": "Dispersion Scale",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "lensStrength",
      "name": "Lens Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "rotationSpeed",
      "name": "Rotation Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Lens Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Dispersion Scale",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Lens Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Rotation Speed",
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
//  Crossover: Mouse + Spectral — Prismatic Lens
//  Category: interactive-mouse
//  Features: crossover, mouse-driven, spectral-rendering, audio-reactive, upgraded-rgba
//  Crosses: mouse-wormhole-lens (2C) + spec-prismatic-dispersion (3C)
//  Complexity: High
//  Created: 2026-04-19
//  By: Agent 5C — Phase C Crossover Integration
// ═══════════════════════════════════════════════════════════════════
//
//  The mouse cursor becomes a prismatic lens that spectrally disperses
//  the input image. Moving the mouse changes the lens focal point;
//  clicking increases the dispersion intensity. The lens uses physical
//  refraction with Cauchy's equation for wavelength-dependent IOR.
//
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

fn cauchyIOR(lambda: f32, n0: f32, B: f32) -> f32 {
    return n0 + B / (lambda * lambda);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Bass breathes the lens aperture; mids widen spectral dispersion
    let lensRadius = mix(0.05, 0.3, u.zoom_params.x) * (1.0 + bass * 0.4);
    let dispersionScale = mix(0.0, 0.03, u.zoom_params.y) * (1.0 + mids * 0.5);
    let lensStrength = mix(0.5, 2.0, u.zoom_params.z);
    let rotationSpeed = mix(-1.0, 1.0, u.zoom_params.w);
    
    let clickBoost = select(1.0, 2.0, mouseDown);
    let localDispersion = dispersionScale * clickBoost;
    
    let toMouse = uv - mousePos;
    let mouseDist = length(toMouse);
    
    // Lens profile: parabolic thickness
    let lensProfile = max(0.0, 1.0 - (mouseDist * mouseDist) / (lensRadius * lensRadius));
    let lensFactor = lensProfile * lensStrength;
    
    // Rotation over time
    let angle = time * rotationSpeed * 0.2 + lensProfile * 3.14159;
    let ca = cos(angle);
    let sa = sin(angle);
    let rotDir = vec2<f32>(toMouse.x * ca - toMouse.y * sa, toMouse.x * sa + toMouse.y * ca);
    
    // Wavelengths for RGB
    let lambdaR = 650.0;
    let lambdaG = 530.0;
    let lambdaB = 460.0;
    let n0 = 1.4;
    let B = 3000.0;
    
    let iorR = cauchyIOR(lambdaR, n0, B);
    let iorG = cauchyIOR(lambdaG, n0, B);
    let iorB = cauchyIOR(lambdaB, n0, B);
    
    // Refraction displacement
    let normal = normalize(rotDir + vec2<f32>(0.0001));
    let dispR = normal * (iorR - iorG) * localDispersion * lensFactor;
    let dispB = normal * (iorB - iorG) * localDispersion * lensFactor;
    
    let sampleR = textureSampleLevel(readTexture, u_sampler, uv - dispR, 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, uv - dispB, 0.0).b;
    
    var finalColor = vec3<f32>(sampleR, sampleG, sampleB);
    
    // Add chromatic aberration glow inside lens
    let glow = lensProfile * 0.15 * clickBoost * (1.0 + bass * 0.6);
    finalColor = finalColor + vec3<f32>(glow * 0.8, glow * 0.5, glow * 1.0);

    // Bass rings the lens rim with a caustic flare
    let rim = exp(-pow((mouseDist / max(lensRadius, 0.001)) - 1.0, 2.0) * 30.0) * bass;
    finalColor = finalColor + vec3<f32>(1.0, 0.7, 0.35) * rim * 0.6;

    // Alpha represents lens intensity
    let alpha = clamp(mix(1.0, 0.9, lensProfile * 0.3) + rim * 0.3, 0.0, 1.0);

    let outColor = vec4<f32>(finalColor, alpha);
    textureStore(writeTexture, global_id.xy, outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
