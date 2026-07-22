# Swarm Brief: supernova-remnant

**Role:** Visualist
**Name:** Supernova Remnant
**Category:** generative
**Description:** Expanding supernova shockwave with turbulent ejecta filaments. Bass drives the expansion front, mids create Rayleigh-Taylor instability fingers, treble adds radioactive decay sparkles. Mouse pulls the remnant center.
**Current lines:** 174
**Target lines:** 224–264 (expand by +50 to +90)

## Role Instructions

You are the Visualist. Push the stellar-explosion realism: thermal aging, shock physics, interactive detonations:
- Blackbody age ramp: accumulate a slow inertial 'age' in dataTextureA alpha (read back smoothed) and map shell color through a white-hot -> orange -> deep-red blackbody-style ramp as age grows, instead of fixed RGB shell weights.
- Click detonation: mouse-down spawns a secondary expanding shock front using the ripples[] uniform array in Uniforms (currently unused) - ring radius expands from the click point and perturbs the shock shell where it passes.
- Inertial bass kicks: bass nudges the age/expansion accumulator rather than rescaling expansion directly, so kicks feel like momentum, not zoom.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the normalize(uv01 - 0.5 + 0.001) epsilon guard and the existing chromatic-dispersed feedback (decay 0.92, mix ~0.15) - it is stable, do not retune it. The 4 sliders are already shader-specific; keep their mappings.

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
  "id": "supernova-remnant",
  "name": "Supernova Remnant",
  "url": "shaders/supernova-remnant.wgsl",
  "description": "Expanding supernova shockwave with turbulent ejecta filaments. Bass drives the expansion front, mids create Rayleigh-Taylor instability fingers, treble adds radioactive decay sparkles. Mouse pulls the remnant center.",
  "tags": [
    "generative",
    "supernova",
    "space",
    "shockwave",
    "audio-reactive",
    "mouse-driven",
    "temporal",
    "chromatic"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "temporal"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Expansion Rate",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Filament Turbulence",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Shock Density",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Decay Sparkles",
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
      "name": "Expansion Rate",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Filament Turbulence",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Shock Density",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Decay Sparkles",
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
//  Supernova Remnant
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware
//  Complexity: Very High
//  Description: Expanding supernova shockwave with turbulent ejecta filaments.
//               Bass drives the expansion front, mids create Rayleigh-Taylor
//               instability fingers, treble adds radioactive decay sparkles.
//               Mouse pulls the remnant center.
//  Created: 2026-05-30
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

const PI: f32 = 3.14159265;

fn hash21(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 5; i++) {
    v += a * noise(pp);
    a *= 0.5;
    pp *= 2.03;
  }
  return v;
}

// Polar coordinates with turbulence
fn turbulentPolar(uv: vec2<f32>, t: f32, turbulence: f32) -> vec2<f32> {
  let r = length(uv);
  let a = atan2(uv.y, uv.x);
  let turb = fbm(vec2<f32>(r * 3.0, a * 2.0) + t * 0.2) * turbulence;
  return vec2<f32>(r, a + turb);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv01 = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mousePos = vec2<f32>(mouse.x * aspect, mouse.y);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let expansionRate    = mix(0.1, 1.0, u.zoom_params.x);
  let filamentTurb     = mix(0.0, 2.0, u.zoom_params.y);
  let shockDensity     = mix(0.5, 3.0, u.zoom_params.z);
  let decaySparkle     = mix(0.0, 1.5, u.zoom_params.w);

  // Mouse pulls the remnant center
  let center = mousePos * 0.3;
  let relUV = uv - center;

  // Supernova expansion driven by bass
  let age = fract(time * expansionRate * 0.1 + bass * 0.05);
  let shockRadius = age * 0.8;

  // Polar turbulence
  let tp = turbulentPolar(relUV, time, filamentTurb);
  let r = tp.x;
  let a = tp.y;

  // Shockwave front
  let shockWidth = 0.03 + bass * 0.02;
  let shockDist = abs(r - shockRadius);
  let shockFront = exp(-shockDist * shockDist / (shockWidth * shockWidth));

  // Rayleigh-Taylor instability fingers (mids)
  let fingers = fbm(vec2<f32>(a * 8.0, r * 10.0) + mids * 2.0) * mids;
  let fingerMask = exp(-abs(r - shockRadius * 0.7) * 5.0);
  let rtInstability = fingers * fingerMask;

  // Ejecta filaments
  let filamentNoise = fbm(vec2<f32>(cos(a) * 3.0, sin(a) * 3.0) + time * 0.1);
  let filamentMask = exp(-abs(r - shockRadius * (0.5 + filamentNoise * 0.3)) * 8.0);
  let filaments = filamentMask * shockDensity;

  // Inner core glow
  let coreGlow = exp(-r * r * 10.0) * (1.0 - age * 0.5);

  // ═══ Chromatic shell: different effective radius per channel ═══
  let rR = r + bass * 0.01;
  let rG = r + mids * 0.015;
  let rB = r + treble * 0.008;

  let shellR = exp(-abs(rR - shockRadius) * 12.0);
  let shellG = exp(-abs(rG - shockRadius) * 12.0);
  let shellB = exp(-abs(rB - shockRadius) * 12.0);

  var col = vec3<f32>(0.0);
  col.r = shellR * 1.2 + rtInstability * 0.8 + coreGlow * 1.5;
  col.g = shellG * 0.9 + rtInstability * 0.5 + coreGlow * 0.8;
  col.b = shellB * 0.7 + filaments * 0.6 + coreGlow * 0.4;

  // Radioactive decay sparkles (treble)
  let sparkleNoise = hash21(vec2<f32>(floor(relUV * 50.0) + time * 5.0));
  let sparkle = step(0.98 - treble * 0.05, sparkleNoise) * treble * decaySparkle;
  let sparkleGlow = exp(-r * r * 3.0) * sparkle;
  col += vec3<f32>(0.9, 0.95, 1.0) * sparkleGlow;

  // ═══ Temporal feedback with chromatic dispersion ═══
  let cStr = 0.003 + bass * 0.005;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));

  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.5 + treble), 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
  let prevCol = vec3<f32>(prevR, prevG, prevB);
  col = mix(col, prevCol * 0.92, 0.15 + bass * 0.03);

  // Alpha based on total energy
  let energy = shockFront + rtInstability + filaments + coreGlow + sparkleGlow;
  let alpha = clamp(energy * 0.8, 0.0, 1.0);

  // Depth based on radial distance and alpha
  let depthVal = clamp(1.0 - r * 1.5, 0.0, 1.0) * alpha;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
}
```
