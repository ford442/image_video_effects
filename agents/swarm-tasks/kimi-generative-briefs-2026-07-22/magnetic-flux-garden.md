# Swarm Brief: magnetic-flux-garden

**Role:** Optimizer
**Name:** Magnetic Flux Garden
**Category:** generative
**Description:** Ferrofluid-like magnetic field lines curve between cursor poles, blooming with organic turbulence and treble seeds.
**Current lines:** 128
**Target lines:** 178–218 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. Focus on performance, structure, and polish without disturbing the core algorithm:
- Curl-noise perturbation on the field lines: add a small-amplitude curl (derivative-of-noise) offset to the flux-line sampling so lines weave organically instead of lying perfectly smooth.
- IQ cosine palette blend on the bloom layer at low mix (~0.3), param-scaled; the original field-line coloring stays dominant.
- Feedback clamp on any temporal accumulation write (clamp pre-tint at ~1.2, luma-echo-warp lesson) so the bloom trails cannot blow out over time.
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
  "id": "magnetic-flux-garden",
  "name": "Magnetic Flux Garden",
  "url": "shaders/magnetic-flux-garden.wgsl",
  "category": "generative",
  "description": "Ferrofluid-like magnetic field lines curve between cursor poles, blooming with organic turbulence and treble seeds.",
  "tags": [
    "generative",
    "magnetic",
    "ferrofluid",
    "fields",
    "organic",
    "audio-reactive"
  ],
  "features": [
    "procedural",
    "audio-reactive",
    "mouse-driven",
    "upgraded-rgba",
    "temporal",
    "chromatic",
    "depth-aware"
  ],
  "params": [
    {
      "id": "fieldLines",
      "name": "Field Lines",
      "default": 0.44,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "fieldStrength",
      "name": "Field Strength",
      "default": 0.48,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "organic",
      "name": "Organic",
      "default": 0.35,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "bloom",
      "name": "Bloom",
      "default": 0.42,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Field Lines",
      "default": 0.44,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Field Strength",
      "default": 0.48,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Organic",
      "default": 0.35,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Bloom",
      "default": 0.42,
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
//  Magnetic Flux Garden
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, aces-tone-map, depth-aware
//  Complexity: High
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

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
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
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let fieldLines = mix(4.0, 24.0, u.zoom_params.x);
  let fieldStrength = mix(0.2, 2.0, u.zoom_params.y);
  let organic = mix(0.0, 1.0, u.zoom_params.z);
  let bloom = mix(0.2, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let poleA = mouse * 0.5;
  let poleB = -mouse * 0.3;

  var flux = 0.0;
  var curl = 0.0;
  var seed = 0.0;

  for (var i = 0u; i < u32(fieldLines); i = i + 1u) {
    let fi = f32(i);
    let angle = fi * 6.28318 / fieldLines;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let start = poleA + dir * 0.02;

    var pos = start;
    var lineInt = 0.0;
    for (var step = 0u; step < 40u; step = step + 1u) {
      let toB = poleB - pos;
      let toA = poleA - pos;
      let distA = length(toA);
      let distB = length(toB);
      if (distA < 0.02 || distB < 0.02) { break; }

      let fieldDir = normalize(toA / (distA * distA + 0.001) - toB / (distB * distB + 0.001));
      let organicWarp = vec2<f32>(
        sin(pos.y * 8.0 + time * 0.5 + fi) * organic * 0.15,
        cos(pos.x * 6.0 + time * 0.3 + fi * 1.3) * organic * 0.15
      );
      pos = pos + (fieldDir + organicWarp) * 0.02;

      let pd = length(p - pos);
      lineInt = lineInt + exp(-pd * pd * 800.0);
    }
    flux = flux + lineInt;
    let curlAngle = angle + time * 0.2 * (1.0 + bass * 0.5);
    let curlPos = poleA + vec2<f32>(cos(curlAngle), sin(curlAngle)) * (0.1 + fi * 0.02);
    curl = curl + exp(-length(p - curlPos) * length(p - curlPos) * 300.0) * (0.5 + mids);
  }

  seed = step(0.995 - treble * 0.02, hash21(floor(uv * 250.0 + time * 0.08))) * flux;

  // Chromatic: teal flux lines, magenta curls, gold seeds
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.1, 0.85, 0.75) * flux * fieldStrength * bloom * (1.0 + bass * 0.2);
  color = color + vec3<f32>(0.9, 0.35, 0.75) * curl * bloom * 0.5 * (1.0 + mids * 0.15);
  color = color + vec3<f32>(1.0, 0.85, 0.25) * seed * (0.4 + treble);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.025 + bass * 0.01);

  let presence = sat(flux * 0.85 + curl * 0.6 + seed * 0.9);
  let alpha = sat(0.1 + presence * 0.9);
  let depth = sat(0.92 - flux * 0.5 - curl * 0.3);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(flux, curl, seed, alpha));
}
```
