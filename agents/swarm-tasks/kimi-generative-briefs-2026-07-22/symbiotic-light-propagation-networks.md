# Swarm Brief: symbiotic-light-propagation-networks

**Role:** Interactivist
**Name:** Symbiotic Light Propagation Networks
**Category:** generative
**Description:** Two organic species grow while transporting and transforming light through their network. They support each other symbiotically while competing for resources. Mouse seeds new growth while audio controls light color and transmission.
**Current lines:** 133
**Target lines:** 183–223 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. Focus on input reactivity and feedback:
- Mouse seeding pulse: on mouse-down, spawn an expanding growth ring (frame-stamped in extraBuffer) that locally boosts network growth where it passes — seeds feel planted, not just held.
- Bass glow pulse as a spatial wave: make plasmaBuffer[0].x drive a slow radial glow wave from the seed point instead of a flat global gain, so beats propagate along the network.
- Feedback clamp on the temporal light accumulation (clamp pre-tint at ~1.2, luma-echo-warp lesson) so glow trails stabilize instead of saturating.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: extraBuffer[0..4] is reserved by the engine — use extraBuffer[5] and above only (indexed writes must stay in-bounds).

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
  "id": "symbiotic-light-propagation-networks",
  "name": "Symbiotic Light Propagation Networks",
  "url": "shaders/symbiotic-light-propagation-networks.wgsl",
  "category": "generative",
  "description": "Two organic species grow while transporting and transforming light through their network. They support each other symbiotically while competing for resources. Mouse seeds new growth while audio controls light color and transmission.",
  "features": [
    "light-transport",
    "organic-networks",
    "symbiotic-growth",
    "audio-color",
    "mouse-seeding",
    "upgraded-rgba",
    "chromatic-dispersion",
    "temporal-accumulation"
  ],
  "tags": [
    "symbiotic",
    "light",
    "organic",
    "network",
    "bioluminescent",
    "audio-reactive"
  ],
  "params": [
    {
      "id": "growthRate",
      "name": "Network Growth",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "How fast the light-carrying network expands"
    },
    {
      "id": "lightTransmission",
      "name": "Light Transmission",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "How efficiently light travels through the network"
    },
    {
      "id": "symbiosis",
      "name": "Symbiotic Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "How much the two species help each other"
    },
    {
      "id": "mouseSeeding",
      "name": "Mouse Seeding Power",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "How strongly the mouse can plant new network nodes"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Network Growth",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Light Transmission",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Symbiotic Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Mouse Seeding Power",
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
//  Symbiotic Light Propagation Networks
//  Category: generative
//  Features: light-transport, organic-networks, symbiotic-growth, audio-color, mouse-seeding,
//            chromatic-dispersion, bass-glow-pulses, temporal-accumulation, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Chunks From: light ray marching simulation + growth models
//  Created: 2026-05-31
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.3;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    let lightReceived = prev.a;
    let growth = (0.015 + mids * 0.025) * (0.4 + lightReceived * 1.2);

    let species1 = prev.r;
    let species2 = prev.g;

    let support = species1 * species2 * 0.6;
    let compete = abs(species1 - species2) * 0.3;

    var newS1 = species1 * 0.97 + growth * (1.0 + support - compete);
    var newS2 = species2 * 0.97 + growth * (1.0 + support - compete * 0.8);

    let mouseDist = length(uv - mouse);
    let mouseSeed = smoothstep(0.1, 0.0, mouseDist) * mouseDown * 0.8;
    newS1 += mouseSeed * 0.5;
    newS2 += mouseSeed * 0.4;

    let ps = 1.0 / res;
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0);
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(ps.x, 0.0), 0.0);
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, ps.y), 0.0);
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, ps.y), 0.0);

    newS1 = (newS1 + n1.r + n2.r + n3.r + n4.r) * 0.2;
    newS2 = (newS2 + n1.g + n2.g + n3.g + n4.g) * 0.2;

    // Chromatic light transport: R and B light travel at different speeds
    let lightDir = normalize(vec2<f32>(0.6, 0.4));
    let rLightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.035, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let bLightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.025, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let gLightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.03, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let transmittedR = (rLightSample.r + rLightSample.g) * 0.4 * (0.6 + treble * 0.5);
    let transmittedG = (gLightSample.r + gLightSample.g) * 0.4 * (0.6 + mids * 0.5);
    let transmittedB = (bLightSample.r + bLightSample.g) * 0.4 * (0.6 + bass * 0.5);

    let totalDensity = newS1 + newS2;
    let lightR = transmittedR * (1.0 - totalDensity * 0.4);
    let lightG = transmittedG * (1.0 - totalDensity * 0.4);
    let lightB = transmittedB * (1.0 - totalDensity * 0.4);

    textureStore(dataTextureA, gid.xy, vec4<f32>(newS1, newS2, lightG, totalDensity));

    // Temporal accumulation for persistent glow
    let prevLight = prev.b;
    let accumulatedLight = mix(vec3<f32>(lightR, lightG, lightB), vec3<f32>(prevLight * 0.9), 0.1);

    let c1 = vec3<f32>(0.3, 0.8, 0.5) * newS1;
    let c2 = vec3<f32>(0.8, 0.4, 0.7) * newS2;
    let glow = vec3<f32>(0.4, 0.7, 0.9) * accumulatedLight * 1.5;

    // Bass-driven glow pulses
    let pulse = 1.0 + bass * 0.5 * smoothstep(0.3, 0.0, mouseDist);
    let col = (c1 + c2 + glow) * pulse;

    let alpha = clamp(totalDensity * 0.7 + (lightR + lightG + lightB) * 0.2 + bass * 0.05, 0.2, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, applyGenerativePrimaryControls(vec4<f32>(col, a)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalDensity * 0.6 + lightG * 0.4, 0.0, 0.0, 0.0));
}
```
