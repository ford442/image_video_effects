# Swarm Brief: plasma-jet-stream

**Role:** Algorithmist
**Name:** Plasma Jet Stream
**Category:** generative
**Description:** High-energy plasma jets radiate from center with bass-driven intensity, mids-driven spread, and treble sparks.
**Current lines:** 152
**Target lines:** 202–242 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on the jet shear-layer physics and boundary structure:
- Chromatic shear fringe: at jet boundaries (high velocity-gradient regions) add subtle RGB dispersion — shear layers get a prismatic edge.
- Bass surge wave: plasmaBuffer[0].x launches a slow radial velocity pulse from the stream origin that temporarily widens spread as it passes, so beats visibly pump the jets.
- Strengthen the divergence-free perturbation: derive the turbulence offset from a curl of a noise potential (finite-difference gradient rotated 90 deg) instead of raw noise — jets bend without artificial sources/sinks.
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
  "id": "plasma-jet-stream",
  "name": "Plasma Jet Stream",
  "url": "shaders/plasma-jet-stream.wgsl",
  "category": "generative",
  "description": "High-energy plasma jets radiate from center with bass-driven intensity, mids-driven spread, and treble sparks.",
  "tags": [
    "generative",
    "plasma",
    "jets",
    "energy",
    "physics",
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
      "id": "jetCount",
      "name": "Jet Count",
      "default": 0.44,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "velocity",
      "name": "Velocity",
      "default": 0.48,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "spread",
      "name": "Spread",
      "default": 0.38,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.35,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Jet Count",
      "default": 0.44,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Velocity",
      "default": 0.48,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Spread",
      "default": 0.38,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Turbulence",
      "default": 0.35,
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
//  Plasma Jet Stream — Algorithmist Upgrade
//  Warped FBM turbulence + Clifford drift + Gold-noise sparks
//  Multi-scale jet boundaries with divergence-free perturbation
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

const PI     = 3.14159265358979323846;
const TAU    = 6.28318530717958647692;
const PHI    = 1.61803398874989484820;
const INV_PI = 0.31830988618379067154;

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn goldNoise(uv: vec2<f32>, seed: f32) -> f32 {
  let d = distance(uv * PHI, uv);
  return fract(sin(d * seed) * cos(d * seed * 0.7) * uv.x * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 5; i = i + 1) {
    s = s + a * valueNoise(q);
    q = q * 2.02; a = a * 0.5;
  }
  return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)),
                    fbm(p + vec2<f32>(5.2, 1.3)));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)),
                    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
  return fbm(p + 4.0 * r);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  return vec2<f32>(sin(a * p.y) + c * cos(a * p.x),
                   sin(b * p.x) + d * cos(b * p.y));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
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

  let jetCount = mix(1.0, 8.0, u.zoom_params.x);
  let velocity = mix(0.5, 4.0, u.zoom_params.y);
  let spread = mix(0.02, 0.25, u.zoom_params.z);
  let turbulence = mix(0.0, 1.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let aim = mouse * 0.4;
  var jetIntensity = 0.0;
  var jetHeat = 0.0;

  for (var j = 0u; j < u32(jetCount); j = j + 1u) {
    let fj = f32(j);
    let seed = hash21(vec2<f32>(fj, 7.3));
    let angle = (fj / jetCount) * TAU + seed * 2.0 + aim.x * 2.0;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let perp = vec2<f32>(-dir.y, dir.x);

    // Clifford attractor drift for organic jet origin perturbation
    let drift = clifford(vec2<f32>(fj, time * 0.1), 1.5, 2.1, 0.9, 1.3) * 0.04 * turbulence;
    let origin = aim * 0.5 + drift;
    let along = dot(p - origin, dir);
    let across = dot(p - origin, perp);

    let pulse = 0.5 + 0.5 * sin(time * velocity * (1.0 + seed * 2.0) + fj * 3.7 + bass * 4.0);
    let width = spread * (0.6 + pulse * 0.6) * (1.0 + mids * 0.3);

    // Domain-warped FBM for turbulent jet boundary
    let warp = warpedFBM(vec2<f32>(across, along) * 2.0 + seed * 10.0, time * 0.2) * turbulence * 0.12;
    let dist = abs(across + warp);

    let jcore = exp(-0.5 * dist * dist / (width * width * 0.2 + 0.001)) * pulse;
    let jhalo = exp(-0.5 * dist * dist / (width * width * 0.8 + 0.001)) * 0.4;
    jetIntensity = jetIntensity + jcore + jhalo;
    jetHeat = jetHeat + jcore * (1.0 + bass);
  }

  let shock = smoothstep(0.6, 1.0, jetIntensity);
  // Gold-noise spark generation (quasi-random, better temporal stability)
  let spark = step(0.996 - treble * 0.03, goldNoise(floor((uv + time * 0.1) * 200.0), time)) * shock;

  // Chromatic: R core, G shock, B sparks
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(1.0, 0.35, 0.05) * jetHeat * (1.0 + bass * 0.25);
  color = color + vec3<f32>(0.85, 0.9, 0.3) * shock * 0.5 * (1.0 + mids * 0.15);
  color = color + vec3<f32>(0.4, 0.7, 1.0) * spark * (0.5 + treble);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.03 + bass * 0.015);

  let presence = sat(jetIntensity * 0.85 + spark * 0.8);
  let alpha = sat(0.15 + presence * 0.85);
  let depth = sat(0.95 - jetHeat * 0.6 - spark * 0.2);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(jetIntensity, shock, spark, alpha));
}
```
