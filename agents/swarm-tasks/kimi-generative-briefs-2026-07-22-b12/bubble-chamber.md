# Swarm Brief: bubble-chamber

**Role:** Algorithmist
**Name:** Bubble Chamber
**Category:** generative
**Description:** Simulates subatomic particle trails in a magnetic field using a feedback loop.
**Current lines:** 163
**Target lines:** 213–253 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on the particle-physics flavor: tracks, ionization, and field response:
- Ionization falloff: bubble-track brightness decays along trail length with a Bragg-curve-like bump near the end — tracks read as physical particles, not uniform worms.
- Mouse Lorentz deflection: nearby tracks curve around the cursor like a magnetic pole (falloff ~1/r, strength by mouse-down), so moving the mouse visibly bends the chamber.
- Clean up the param double-duty: zoom_params.z currently drives BOTH turbulence and spawn_rate — separate concerns so Scale controls spatial scale and spawn density follows Intensity/Detail sensibly; keep ids/defaults.
- Feedback clamp on the trail accumulation pre-tint at ~1.2 (luma-echo-warp lesson).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: bubble-chamber has temporal feedback (decay) — keep the divergence-free advection intact and clamp the accumulation so trails cannot blow out.

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
  "id": "bubble-chamber",
  "name": "Bubble Chamber",
  "url": "shaders/bubble-chamber.wgsl",
  "description": "Simulates subatomic particle trails in a magnetic field using a feedback loop.",
  "features": [
    "mouse-driven",
    "feedback"
  ],
  "tags": [
    "procedural",
    "generative"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
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
//  Bubble Chamber — Algorithmist Upgrade
//  Curl-noise velocity field + Clifford perturbation + Gold-noise emission
//  Domain-warped FBM for chromatic drift, divergence-free advection
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

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.001;
  let nx = fbm(p + vec2<f32>(0.0, eps) + t * 0.1) - fbm(p - vec2<f32>(0.0, eps) + t * 0.1);
  let ny = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1) - fbm(p - vec2<f32>(eps, 0.0) + t * 0.1);
  return vec2<f32>(nx, -ny) / (2.0 * eps);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  return vec2<f32>(sin(a * p.y) + c * cos(a * p.x),
                   sin(b * p.x) + d * cos(b * p.y));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  var p = uv * 2.0 - 1.0;
  p.x *= aspect;

  var mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
  mouse_pos.x *= aspect;

  let to_mouse = p - mouse_pos;
  let dist = length(to_mouse);

  // Magnetic spiral base field
  let tangent = vec2<f32>(-to_mouse.y, to_mouse.x) / (dist + 0.001);
  var radial = vec2<f32>(0.0);
  if (dist > 0.001) { radial = normalize(to_mouse); }

  let field_strength = u.zoom_params.x * 0.02 + 0.002;
  let base_vel = (tangent + radial * 0.2) * field_strength;

  // Divergence-free curl noise turbulence layer
  let turb = curl2D(p * 3.0 + mouse_pos * 2.0, time) * (u.zoom_params.z * 0.5 + 0.05);
  // Clifford strange-attractor perturbation for organic drift
  let cliff = clifford(p * 2.0, 1.7, 1.3, 1.1 + time * 0.02, 1.9) * 0.015 * u.zoom_params.w;
  let velocity = base_vel + turb + cliff;

  let uv_velocity = velocity * vec2<f32>(1.0 / aspect, 1.0);
  let sample_uv = uv - uv_velocity;

  let history = textureSampleLevel(dataTextureC, u_sampler, sample_uv, 0.0);

  var decay = u.zoom_params.y;
  if (decay < 0.01) { decay = 0.96; }
  decay = min(decay, 0.995);

  let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luminance = dot(input_color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Gold-noise ionization spawn (quasi-random, better distribution)
  let rand_val = goldNoise(uv, time * 0.1 + floor(time * 3.0));
  var spawn_rate = u.zoom_params.z;
  if (spawn_rate < 0.001) { spawn_rate = 0.05; }

  var spark = vec4<f32>(0.0);
  if (rand_val < luminance * spawn_rate * 0.2) {
    spark = input_color * 2.5;
    spark.a = luminance * 2.0;
  }

  var shifted_history = history * decay;
  if (u.zoom_params.w > 0.1) {
    let shift_speed = u.zoom_params.w * 0.05;
    let r = shifted_history.r;
    let g = shifted_history.g;
    let b = shifted_history.b;
    shifted_history.r = r * (1.0 - shift_speed) + g * shift_speed;
    shifted_history.g = g * (1.0 - shift_speed) + b * shift_speed;
    shifted_history.b = b * (1.0 - shift_speed) + r * shift_speed;
  }

  // Domain-warped FBM absorption drift
  let drift = warpedFBM(uv * 3.0, time * 0.03) * 0.02;
  shifted_history = shifted_history * (1.0 - drift);

  let output = max(shifted_history, spark);
  let energy = dot(output.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = max(0.0, energy - 0.7) * 3.0;
  let alpha = clamp(energy * 1.5 + bloom + output.a * 0.5, 0.0, 1.0);
  let depth = clamp(1.0 - energy * 0.8, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(output.rgb, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(output.rgb, alpha));
}
```
