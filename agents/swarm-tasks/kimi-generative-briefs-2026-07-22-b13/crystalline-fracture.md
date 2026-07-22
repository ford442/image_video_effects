# Swarm Brief: crystalline-fracture

**Role:** Algorithmist
**Name:** Crystalline Fracture
**Category:** generative
**Description:** Fracture mechanics simulation with stress intensity factor-driven crack propagation, branching, percolation connectivity, and hackle marks on translucent crystal surfaces. Thin-film iridescence and subsurface scattering. Audio loads stress and triggers catastrophic failure; mouse applies point stress. Depth controls crystal thickness perspective.
**Current lines:** 175
**Target lines:** 225–265 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Extend the fracture mechanics: stress waves, grain boundaries, and persistent crack memory:
- Click stress rings: use u.config.y (MouseClickCount, currently unused) or the ripples[] uniform to spawn ring-shaped stress waves on click that propagate outward and trigger cracks where K exceeds toughness.
- Weak grain boundaries: make fracture toughness spatially varying via one fbm lookup so cracks preferentially propagate along weak paths - reads as real material grain.
- Crack memory healing: decay the stored stress memory (feedback .r) slower (e.g. store prev.r*0.98) so fracture patterns persist and evolve across frames instead of resetting; keep the effective feedback ratio strictly < 1.0.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: dataTextureA channels are SIM STATE (.r = accumulated stress, .g = crack connectivity), not color - preserve that layout. The stress feedback ratio (prev.r*0.5) is a geometric series: never raise the coefficient to >= 1.0 or stress diverges. Keep the thin-film iridescence and SSS math intact.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.

## JSON Parameters / Controls

```json
{
  "id": "crystalline-fracture",
  "name": "Crystalline Fracture",
  "category": "generative",
  "url": "shaders/crystalline-fracture.wgsl",
  "description": "Fracture mechanics simulation with stress intensity factor-driven crack propagation, branching, percolation connectivity, and hackle marks on translucent crystal surfaces. Thin-film iridescence and subsurface scattering. Audio loads stress and triggers catastrophic failure; mouse applies point stress. Depth controls crystal thickness perspective.",
  "features": [
    "audio-reactive",
    "fracture-mechanics",
    "stress-intensity",
    "crack-propagation",
    "iridescence",
    "subsurface-scatter",
    "voronoi-cells",
    "upgraded-rgba",
    "chromatic-edges"
  ],
  "params": [
    {
      "id": "cells",
      "name": "Cell Density",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "glow",
      "name": "Edge Glow",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "fracture",
      "name": "Fracture Amount",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "chromatic",
      "name": "Chromatic Shift",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "generative",
    "crystal",
    "fracture",
    "voronoi",
    "chromatic",
    "audio-reactive",
    "geometric",
    "abstract",
    "fracture-mechanics",
    "stress-intensity",
    "crack-propagation",
    "iridescence",
    "subsurface-scatter",
    "percolation",
    "hackle"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Cell Density",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Edge Glow",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Fracture Amount",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chromatic Shift",
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
//  Crystalline Fracture v2
//  Category: generative
//  Features: audio-reactive, fracture-mechanics, stress-intensity,
//            crack-propagation, iridescence, subsurface-scatter, upgraded-rgba, aces-tone-map
//  Complexity: Very High
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
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
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let cellCount = mix(3.0, 15.0, u.zoom_params.x) * (1.0 + depth * 0.5);
    let edgeGlow = u.zoom_params.y;
    let fractureAmt = u.zoom_params.z;
    let chromatic = u.zoom_params.w * 0.02;

    let aspect = res.x / res.y;
    let p = uv * vec2<f32>(aspect, 1.0) * cellCount;
    let cellId = floor(p);
    let cellUV = fract(p);

    // Stress field: bass loading + mouse point stress + temporal crack memory
    let mouseDist = length(uv - mouse);
    let mouseField = exp(-mouseDist * mouseDist * 20.0) * u.zoom_config.w;
    let mouseStress = smoothstep(0.15, 0.0, mouseDist) * u.zoom_config.w * 4.0;
    var stress = bass * 2.0 + mouseStress + mouseField * 2.0 + prev.r * 0.5;

    // Fracture toughness from mids
    let toughness = 0.4 + mids * 0.6;

    // Catastrophic failure events triggered by treble
    let catastrophic = step(0.8, treble) * 2.0;
    stress = stress + catastrophic;

    // Percolation connectivity boost from neighboring cracks
    let connectivity = smoothstep(0.3, 0.7, prev.g);
    stress = stress + connectivity * 0.3;

    // Time-evolving Voronoi crystal cells
    var minDist = 1e9;
    var secondMinDist = 1e9;
    var nearestId = vec2<f32>(0.0);
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let nid = cellId + vec2<f32>(f32(x), f32(y));
            let center = hash22(nid + vec2<f32>(time * 0.01 * fractureAmt, 0.0)) + vec2<f32>(f32(x), f32(y));
            let d = length(cellUV - center);
            if (d < minDist) {
                secondMinDist = minDist;
                minDist = d;
                nearestId = nid;
            } else if (d < secondMinDist) {
                secondMinDist = d;
            }
        }
    }

    let edgeDist = secondMinDist - minDist;
    let edge = smoothstep(0.05, 0.0, edgeDist);

    // Stress intensity factor K drives crack propagation
    let crackSpeed = 0.1 + bass * 0.2;
    let crackLength = hash21(nearestId) * 2.0 + time * crackSpeed * fractureAmt;
    let K = stress * sqrt(max(crackLength, 0.0));
    let crack = step(toughness, K);
    let branch = step(toughness * 1.3, K) * hash21(nearestId + vec2<f32>(1.0, 0.0));
    let crackDensity = crack + branch * 0.5;

    // Crack tip singularity glow
    let tip = smoothstep(0.015, 0.0, minDist) * crack * (1.0 - branch);

    // Hackle marks on fracture surfaces
    let hackle = sin(dot(cellUV, vec2<f32>(12.0, 5.0)) + hash21(nearestId) * 6.28) * 0.5 + 0.5;
    let hackleMask = smoothstep(0.45, 0.55, hackle) * edge * crackDensity;

    let hackleDir = atan2(cellUV.y - 0.5, cellUV.x - 0.5);
    let hackleRidge = sin(hackleDir * 6.0 + hash21(nearestId) * 6.28) * 0.5 + 0.5;
    let hackleMask2 = smoothstep(0.4, 0.6, hackleRidge) * edge * crackDensity * 0.5;

    // Thin-film iridescence on fracture surfaces
    let film = sin(length(cellUV - 0.5) * 25.0 - time * 1.5 + depth * 3.14) * 0.5 + 0.5;
    let irid = mix(vec3<f32>(0.9, 0.2, 0.2), vec3<f32>(0.2, 0.8, 0.9), film) * edge * crackDensity;

    // Internal refraction lines
    let refraction = sin(minDist * 20.0 + time * 0.5) * smoothstep(0.3, 0.0, edgeDist) * 0.12 * fractureAmt;

    // Subsurface scattering approximation
    let sss = smoothstep(0.25, 0.0, edgeDist) * 0.25 * (1.0 + mids);

    // Chromatic aberration on internal reflections
    let ca = chromatic * (1.0 + treble) * edgeDist;
    let rEdge = smoothstep(0.05 + ca, 0.0, edgeDist);
    let bEdge = smoothstep(0.05 - ca, 0.0, edgeDist);
    let chromaEdge = vec3<f32>(rEdge, edge, bEdge) * edgeGlow * (1.0 + treble);

    // Cell interior with depth perspective (crystal thickness)
    let cellHue = hash21(cellId + vec2<f32>(time * 0.005, 0.0));
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let h = abs(fract(vec3<f32>(cellHue) + k) * 6.0 - vec3<f32>(3.0));
    let cellColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)) * (0.3 + mids * 0.2) * (1.0 - depth * 0.3);

    // HDR bloom at crack tips
    let bloom = tip * 3.0 * (1.0 + bass);
    var color = cellColor + chromaEdge + irid + vec3<f32>(sss) + vec3<f32>(refraction) + vec3<f32>(bloom);
    color = color + vec3<f32>(0.35, 0.3, 0.25) * hackleMask;
    color = color + vec3<f32>(0.3, 0.25, 0.2) * hackleMask2;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color);

    // Alpha: crack density × stress intensity × depth perspective
    let alpha = clamp(crackDensity * K * depth + edge * 0.15, 0.0, 1.0);

    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(stress, crackDensity, 0.0, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(edge * 0.5 + crackDensity * 0.3, 0.0, 0.0, 0.0));
}
```
