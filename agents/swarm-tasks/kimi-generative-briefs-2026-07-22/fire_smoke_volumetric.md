# Swarm Brief: fire_smoke_volumetric

**Role:** Visualist
**Name:** Fire Smoke Volumetric
**Category:** generative
**Description:** Volumetric fire and smoke simulation with chromatic temperature gradients (R hot to B cool), temporal smoke persistence via dataTextureC, audio-driven turbulence enhancement, physical transmittance, and depth-layered alpha.
**Current lines:** 117
**Target lines:** 167–207 (expand by +50 to +90)

## Role Instructions

You are the Visualist. Focus on color, lighting, and visual richness:
- Worley-noise ember particles: add rising ember sparks (animated worley cells scrolling upward) masked by the fire shape and tinted by the existing chromatic temperature gradient. Restrained — embers must not dominate the smoke.
- Feedback stability: clamp the temporal smoke accumulation path (prevSmoke * decay) pre-write at ~1.2 (luma-echo-warp lesson) so the smoke buffer can never run away or lock to white.
- Treble-reactive edge flicker: modulate the fire silhouette turbulence amplitude with plasmaBuffer[0].z so the flame edge crackles on high-frequency content.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional — only declare it if the shader already uses it.

## JSON Parameters / Controls

```json
{
  "id": "fire_smoke_volumetric",
  "name": "Fire Smoke Volumetric",
  "url": "shaders/fire_smoke_volumetric.wgsl",
  "description": "Volumetric fire and smoke simulation with chromatic temperature gradients (R hot to B cool), temporal smoke persistence via dataTextureC, audio-driven turbulence enhancement, physical transmittance, and depth-layered alpha.",
  "tags": [
    "fire",
    "smoke",
    "volumetric",
    "simulation",
    "temporal",
    "audio-reactive",
    "chromatic",
    "depth-aware",
    "blackbody"
  ],
  "features": [
    "upgraded-rgba",
    "volumetric",
    "fire",
    "smoke",
    "audio-reactive",
    "temporal",
    "depth-aware"
  ],
  "params": [
    {
      "id": "fireIntensity",
      "name": "Fire Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "smokeDensity",
      "name": "Smoke Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "depthWeight",
      "name": "Depth Weight",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.7,
  "updatedParams": [
    {
      "index": 0,
      "name": "Fire Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Smoke Density",
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
//  Fire Smoke Volumetric
//  Category: simulation
//  Features: advanced-alpha, fire, smoke, volumetric,
//            chromatic-temperature, temporal-smoke, audio-turbulence
//  Complexity: High
//  Upgraded: 2026-06-06
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

fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.3, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 54.53))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let dM = length(uv - mouse);
    let mouseHeat = exp(-dM * dM * 8.0) * (mouseDown * 0.6 + 0.2);
    let fireIntensity = u.zoom_params.x * 2.0 * (1.0 + bass * 0.4 + mouseHeat * 0.5);
    let smokeDensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let turbulence = u.zoom_params.w * (1.0 + bass * 0.3);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let noiseUV = vec3<f32>(uv * 5.0, time * 0.5);
    let n = hash(vec3<f32>(noiseUV * 10.0));

    let fireShape = smoothstep(0.3, 0.7, 1.0 - uv.y + n * turbulence);
    let density = fireShape * smokeDensity;

    // Chromatic temperature gradient: hot core = white-yellow, cool edges = red-orange
    let temp = uv.y * fireIntensity;
    let fireR = mix(1.0, 0.9, temp) * (1.0 + treble * 0.2);
    let fireG = mix(0.8, 0.3, temp) * (1.0 + mids * 0.2);
    let fireB = mix(0.1, 0.05, temp) * (1.0 + bass * 0.1);
    let fireColor = vec3<f32>(fireR, fireG, fireB) * fireShape;

    let smokeColor = vec3<f32>(0.3, 0.3, 0.35) * density;
    let effectColor = mix(smokeColor, fireColor, fireShape);

    // Temporal smoke persistence via dataTextureC
    let prevSmoke = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let persistentSmoke = mix(effectColor, prevSmoke * 0.92, 0.08 + bass * 0.02);

    let opticalDepth = density * (1.0 + turbulence);
    let absorptionCoeff = vec3<f32>(0.5, 0.6, 0.7);
    let transmitted = physicalTransmittance(persistentSmoke, opticalDepth, absorptionCoeff);

    let volAlpha = volumetricAlpha(density, 1.0);
    let effectAlpha = volAlpha * depthLayeredAlpha(uv, depthWeight);

    let finalColor = mix(baseColor.rgb, transmitted, effectAlpha);
    let finalAlpha = mix(baseColor.a, 1.0, effectAlpha * 0.7);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesToneMap((finalColor) * 1.1), finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 0.0));
}
```
