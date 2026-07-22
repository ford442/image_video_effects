# Swarm Brief: acoustic-string-theory

**Role:** Interactivist
**Name:** Acoustic String Theory
**Category:** generative
**Description:** Vibrating string harmonics visualized as oscillating sine waves in perspective, with audio-driven pluck and resonance.
**Current lines:** 157
**Target lines:** 207–247 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. Make the strings feel played, not just drawn:
- Pluck on click: mouse-down rising edge (tracked via extraBuffer[5]) excites the nearest string with a gaussian displacement that decays by Tension — clicks pluck, they don't just glow.
- Audio spectrum drive: use plasmaBuffer bands (bass/mids/treble) to weight per-string harmonic amplitudes across the string index range — the instrument visibly tracks the music's spectrum.
- Spring-damper gravity well: the existing gravity well follows the mouse with damped overshoot (state in extraBuffer[6..9]); clamp the feedback-loop accumulation pre-tint at ~1.2 (luma-echo-warp lesson).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds.

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
  "id": "acoustic-string-theory",
  "name": "Acoustic String Theory",
  "url": "shaders/acoustic-string-theory.wgsl",
  "category": "generative",
  "description": "Vibrating string harmonics visualized as oscillating sine waves in perspective, with audio-driven pluck and resonance.",
  "tags": [
    "generative",
    "strings",
    "harmonics",
    "physics",
    "acoustic",
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
      "id": "strings",
      "name": "Strings",
      "default": 0.46,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "tension",
      "name": "Tension",
      "default": 0.48,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "harmonics",
      "name": "Harmonics",
      "default": 0.42,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "resonance",
      "name": "Resonance",
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
      "name": "Strings",
      "default": 0.46,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Tension",
      "default": 0.48,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Harmonics",
      "default": 0.42,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Resonance",
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
//  Acoustic String Theory
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, feedback-loop,
//            gravity-well, shockwave, video-luma, sparkle
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  let dist2 = dot(d, d) + 0.01;
  return normalize(d) * strength / dist2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let rawBass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bass = bass_env(prev.r, rawBass, 0.8, 0.15);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w;

  let strings = mix(2.0, 16.0, u.zoom_params.x);
  let tension = mix(0.5, 5.0, u.zoom_params.y);
  let harmonics = mix(1.0, 8.0, u.zoom_params.z);
  let resonance = mix(0.2, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Mouse gravity well bends string space
  let well = gravityWell(p, vec2<f32>(mouse.x * aspect, mouse.y), 0.08 + bass * 0.06);
  p = p + well;

  // Click shockwave ripple
  let mDist = length(p - vec2<f32>(mouse.x * aspect, mouse.y));
  let shock = exp(-mDist * 4.0) * mouseDown * sin(mDist * 25.0 - time * 10.0);

  // Video luma feedback boosts brightness
  let vid = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(vid, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = smoothstep(0.5, 1.0, luma) * 0.4;

  var stringField = 0.0;
  var harmonicField = 0.0;
  var nodeField = 0.0;

  for (var s = 0u; s < u32(strings); s = s + 1u) {
    let fs = f32(s);
    let sy = -0.9 + (fs + 0.5) / strings * 1.8;
    let pluck = sin(p.x * tension * (1.0 + fs * 0.15) - time * (2.0 + fs * 0.5) * (1.0 + bass * 0.5));
    let damp = exp(-abs(p.x - mouse.x * aspect * 0.5) * 2.0) * (0.5 + mids);
    let wave = sin((p.y - sy + shock * 0.15) * tension * 15.0) * exp(-abs(p.y - sy) * tension * 3.0);
    let amp = (0.15 + damp) * resonance * (1.0 + bass * 0.3);
    let stringLine = abs(wave + pluck * amp);
    stringField = stringField + smoothstep(0.05, 0.0, stringLine) * (0.7 + fs * 0.05);

    for (var h = 1u; h < u32(harmonics); h = h + 1u) {
      let fh = f32(h);
      let harmY = sy + sin(fh * 1.618) * 0.15;
      let harmWave = sin((p.y - harmY) * tension * 15.0 * fh) * exp(-abs(p.y - harmY) * tension * 5.0);
      let harmLine = abs(harmWave + pluck * amp * pow(0.6, fh));
      harmonicField = harmonicField + smoothstep(0.03, 0.0, harmLine) * 0.3;
    }

    let nodeX = sin(fs * 2.7 + time * 0.3) * 0.5 + well.x * 0.5;
    let nodeDist = length(p - vec2<f32>(nodeX, sy));
    nodeField = nodeField + exp(-nodeDist * nodeDist * 80.0) * (0.5 + treble);
  }

  // Treble sparkle on nodes
  let sparkle = step(0.88, hash21(uv * 150.0 + time * 10.0)) * treble * nodeField * 3.0;
  let depthSample = textureLoad(readDepthTexture, coord, 0).r;
  let ao = exp(-depthSample * 3.0);

  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.9, 0.55, 0.2) * stringField * resonance * (1.0 + bass * 0.15);
  color = color + vec3<f32>(0.25, 0.75, 0.95) * harmonicField * (1.0 + mids * 0.2);
  color = color + vec3<f32>(1.0, 0.95, 0.85) * nodeField * (0.5 + treble * 0.3);
  color = color + vec3<f32>(1.0, 0.9, 0.7) * sparkle;
  color = color * (1.0 + lumaBoost) * (0.6 + 0.4 * ao);

  // Temporal accumulation with bass-reactive feedback
  color = mix(color, prev.rgb * 0.94, 0.03 + bass * 0.015);

  let presence = sat(stringField * 0.85 + harmonicField * 0.6 + nodeField * 0.9);
  let mouseProx = exp(-mDist * 2.0);
  let alpha = sat(0.08 + presence * 0.65 + mouseProx * 0.2 + bass * 0.12);
  let trailAge = prev.a * 0.96;
  let finalAlpha = max(alpha, trailAge * 0.6);

  let depth = sat(0.92 - stringField * 0.5 - nodeField * 0.3);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(bass, harmonicField, nodeField, finalAlpha));
}
```
