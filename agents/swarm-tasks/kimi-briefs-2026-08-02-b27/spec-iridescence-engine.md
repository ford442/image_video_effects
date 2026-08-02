# Swarm Brief: spec-iridescence-engine

**Role:** Visualist
**Name:** Iridescence Engine
**Category:** advanced-hybrid
**Description:** Thin-film interference simulation creating soap-bubble and oil-slick iridescence. Uses depth texture for film thickness and physically-correct optical path difference.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This is a SPECTRAL-RENDER shader that never samples the audio spectrum - plasmaBuffer is declared and ignored - and the mouse only matters while the button is held. Give the film a light show:
- WIRE THE DEAD AUDIO (priority 1): per-wavelength spectral voices - inside the thinFilmColor call site, modulate the computed iridescent color's RGB channels by FFT bins mapped across the visible range (e.g. iridescent.r *= 1.0 + plasmaBuffer[7].x * 0.25, .g by bin 4, .b by bin 2 - high wavelengths ride high bins), so music plays across the rainbow. Also a global bass breathing on intensity (intensity *= 1.0 + bass * 0.3).
- Spring-damper film lens (mouse matters unpressed): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT); near the sprung point, add a gentle always-on thickness lens (thickness += 80nm * aspect-corrected gaussian ~0.25 radius) so hovering tilts the film; the existing mouseDown perturbation rides the SPRUNG position.
- Click film waves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple launches an expanding thickness wave from its click point (thickness += 150nm * sin(age * 20.0 - dist * 40.0) * exp(-age * 2.0) * ring mask, ~1.5s), so clicks send iridescent ripples across the oil slick.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash12 helper, wavelengthToRGB, the thinFilmColor spectral integration loop (380-700nm, 20nm step), the OPD/cosTheta_t math, the depth+noise thickness construction, the fresnel blend, the HDR tonemap, and the alpha=thickness/1000.0 semantic (both writes) VERBATIM - the spectral physics are the identity. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stores (iridescent, thickness/1000) - keep that packing. extraBuffer in [133..255] ONLY.

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
  "id": "spec-iridescence-engine",
  "name": "Iridescence Engine",
  "url": "shaders/spec-iridescence-engine.wgsl",
  "description": "Thin-film interference simulation creating soap-bubble and oil-slick iridescence. Uses depth texture for film thickness and physically-correct optical path difference.",
  "tags": [
    "iridescence",
    "thin-film",
    "interference",
    "spectral",
    "oil-slick",
    "soap-bubble"
  ],
  "features": [
    "thin-film-interference",
    "depth-aware",
    "spectral-render",
    "mouse-driven",
    "HDR"
  ],
  "params": [
    {
      "id": "film_thickness",
      "name": "Film Thickness",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "film_ior",
      "name": "Film IOR",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "intensity",
      "name": "Intensity",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "target_rating": 4.8,
  "updatedParams": [
    {
      "index": 0,
      "name": "Film Thickness",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Film IOR",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Intensity",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Turbulence",
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
//  spec-iridescence-engine
//  Category: advanced-hybrid
//  Features: thin-film-interference, depth-aware, spectral-render
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Thin-Film Interference (Soap Bubbles / Oil Slicks)
//  Simulates thin-film interference where reflected color depends on
//  viewing angle and film thickness. Uses depth texture for thickness.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;

    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
    let intensity = mix(0.3, 1.5, u.zoom_params.z);
    let turbulence = mix(0.0, 1.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sample base image and depth
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Viewing angle from pixel position (simulated)
    let toCenter = uv - vec2<f32>(0.5);
    let dist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

    // Film thickness varies with depth + animated noise
    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - time * 0.15) * 0.25;

    var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

    // Mouse interaction: local thickness perturbation
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
        thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
    }

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;

    // Fresnel-like blend based on viewing angle
    let fresnel = pow(1.0 - cosTheta, 3.0);
    let outColor = mix(baseColor, iridescent, fresnel * 0.7);

    // HDR tone map
    let tonemapped = outColor / (1.0 + outColor * 0.2);

    // Alpha stores film thickness for downstream use
    textureStore(writeTexture, gid.xy, vec4<f32>(tonemapped, thickness / 1000.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(iridescent, thickness / 1000.0));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
```
