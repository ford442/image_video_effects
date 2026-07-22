# Swarm Brief: generative-turing-veins

**Role:** Algorithmist
**Name:** Turing Veins Generative
**Category:** generative
**Description:** Multiscale reaction-diffusion Turing patterns generating organic vein/network structures with bioluminescent glow, chromatic activator/inhibitor separation, temporal colony evolution via dataTextureC, and audio-driven feed rate modulation.
**Current lines:** 165
**Target lines:** 215–255 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This reaction-diffusion shader's sliders are DEAD — the JSON declares 4 params but the WGSL never reads u.zoom_params. Wire them for real:
- WIRE THE SLIDERS (priority 1): Primary Scale -> RD kernel radius, Secondary Scale -> second RD layer scale, Feed Rate -> Gray-Scott feed parameter (stay inside the striped-vein regime ~0.03-0.07), Vein Glow -> bioluminescent gain on vein ridges. Keep ids/defaults.
- Bass nutrient pulse: plasmaBuffer[0].x modulates the feed rate in a slow radial wave from center so veins visibly grow on beats.
- Click seeding: mouse-down drops a gaussian activator seed (rising-edge tracked via extraBuffer[5]) so users can plant new vein colonies.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds. Keep the multi-scale RD update stable (clamp activator/inhibitor to sane ranges after update).

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
  "id": "generative-turing-veins",
  "name": "Turing Veins Generative",
  "url": "shaders/generative-turing-veins.wgsl",
  "description": "Multiscale reaction-diffusion Turing patterns generating organic vein/network structures with bioluminescent glow, chromatic activator/inhibitor separation, temporal colony evolution via dataTextureC, and audio-driven feed rate modulation.",
  "features": [
    "mouse-driven",
    "generative",
    "audio-reactive",
    "temporal",
    "semantic-alpha",
    "reaction-diffusion",
    "biological"
  ],
  "tags": [
    "procedural",
    "generative",
    "turing",
    "veins",
    "organic",
    "chromatic",
    "audio-reactive",
    "temporal",
    "bioluminescence"
  ],
  "params": [
    {
      "id": "scale1",
      "name": "Primary Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "scale2",
      "name": "Secondary Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "feedRate",
      "name": "Feed Rate",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "veinGlow",
      "name": "Vein Glow",
      "default": 0.65,
      "min": 0,
      "max": 1.5,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Primary Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Secondary Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Feed Rate",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Vein Glow",
      "default": 0.65,
      "min": 0.0,
      "max": 1.5,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════
// Generative Turing Veins - PASS 1 of 1
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            multi-scale-reaction-diffusion, vein-thickness, nutrient-flow,
//            upgraded-rgba, depth-aware
//  Multiscale reaction-diffusion Turing patterns generating organic
//  vein/network structures with bioluminescent glow. Evolves procedurally
//  over time with depth-modulated complexity. Pure generative output.
//  Created: 2026-05-31
//  Upgraded: 2026-06-28
// ═══════════════════════════════════════════════════════════════

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

fn hash21(p: vec2<f32>) -> f32 {
  var n = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
  return fract(sin(n * 43758.5453) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2(17.1, 29.6)));
}

fn noise(p: vec2<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 1.0;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value += amplitude * noise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

fn turing_pattern(uv: vec2<f32>, time: f32, scale: f32, feed: f32) -> vec2<f32> {
  var p = uv * scale;
  let activator = fbm(p + vec2(time * 0.1, 0.0), 6);
  let inhibitor = fbm(p * 0.5 + vec2(0.0, time * 0.05), 4);
  let reaction = activator * inhibitor * (feed + 0.5);
  let diffusion_a = (fbm(p * 1.2, 5) - 0.5) * 0.1;
  let diffusion_i = (fbm(p * 0.6, 4) - 0.5) * 0.2;
  return vec2(activator + diffusion_a + reaction * 0.1, inhibitor + diffusion_i - reaction * 0.05);
}

fn multi_scale_turing(uv: vec2<f32>, time: f32, params: vec4<f32>, bass: f32) -> vec4<f32> {
  let s1 = params.x * 2.0 + 1.0;
  let s2 = params.y * 1.5 + 0.5;
  let s3 = params.z * 4.0 + 2.0;
  let feed = params.w * 0.5 + 0.5 + bass * 0.1 * sin(time * 0.3);

  let p1 = turing_pattern(uv, time, s1, feed);
  let p2 = turing_pattern(uv * 1.3 + vec2<f32>(0.4, -0.2), time * 0.8, s2, feed * 0.9);
  let p3 = turing_pattern(uv * 0.7 + vec2<f32>(-0.3, 0.5), time * 1.2, s3, feed * 1.1);

  let coarse = (p1.x * p2.y + p1.y * p2.x) * 2.0;
  let fine = (p2.x * p3.y + p2.y * p3.x) * 2.5;
  let micro = abs(p3.x - p3.y) * 3.0;
  return vec4<f32>(coarse, fine, micro, feed);
}

fn veinThickness(uv: vec2<f32>, veins: f32, time: f32) -> f32 {
  let n = fbm(uv * 18.0 + time * 0.2, 3);
  let thickness = 0.45 + 0.35 * sin(n * 6.28318 + time * 0.5);
  return smoothstep(thickness, thickness + 0.12, veins);
}

fn nutrientFlow(uv: vec2<f32>, time: f32, thicknessMask: f32) -> f32 {
  var flow = 0.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let fi = f32(i);
    let seed = hash22(vec2<f32>(fi, fi * 7.3));
    let pos = uv + vec2<f32>(sin(time * 0.4 + fi * 1.7) * 0.3, cos(time * 0.35 + fi * 2.1) * 0.3);
    let d = length(pos - seed);
    let pulse = 0.5 + 0.5 * sin(time * 3.0 + fi * 1.3 + d * 25.0);
    flow += exp(-d * d * 40.0) * pulse * thicknessMask;
  }
  return clamp(flow, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let resolution = vec2<f32>(dims);
  var uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let time = u.config.x;
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  var mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let scale1 = zp.x * 1.5 + 0.5;
  let scale2 = zp.y * 1.0 + 0.25;
  let feed_rate = zp.z * 0.5 + 0.5;
  let intensity = zp.w * 0.8 + 0.2;

  let warpedUV = uv + vec2<f32>(
    fbm(uv * 3.0 + vec2<f32>(time * 0.1, 0.0), 3) - 0.5,
    fbm(uv * 3.0 + vec2<f32>(0.0, time * 0.12), 3) - 0.5
  ) * 0.04 * (1.0 + mids);

  let scales = multi_scale_turing(warpedUV * scale1 + mouse * 0.1, time, vec4<f32>(scale1, scale2, 1.0, feed_rate), bass);
  let veinsRaw = scales.x * 0.55 + scales.y * 0.35 + scales.z * 0.15;
  let veinMask = veinThickness(warpedUV, veinsRaw, time);
  let veinGlow = smoothstep(0.3, 0.7, veinsRaw) * (1.0 - smoothstep(0.7, 1.0, abs(veinsRaw - 0.5) * 2.0));

  let nutrients = nutrientFlow(warpedUV, time, veinMask);
  let nutrientGlow = nutrients * (0.6 + treble * 0.4);

  let actColor = vec3<f32>(0.2, 0.9, 0.5) * scales.x * (1.0 + treble * 0.3);
  let inhColor = vec3<f32>(0.9, 0.3, 0.6) * scales.y * (1.0 + mids * 0.3);
  let vein_hue = fract(veinsRaw * 0.3 + time * 0.1 + scales.y * 0.5);
  let vein_sat = 0.8 + 0.2 * sin(time * 2.0);
  let vein_val = pow(veinMask, 0.5) * (intensity + 0.5);
  var vein_color = mix(vec3(vein_hue, vein_sat, vein_val), actColor + inhColor, 0.3 + bass * 0.2);

  let nutrientColor = vec3<f32>(0.9, 0.95, 0.3) * nutrientGlow;
  let deepColor = vec3<f32>(0.05, 0.08, 0.12) * (1.0 - veinMask);
  var final_rgb = deepColor + vein_color * veinMask + nutrientColor;

  let glow = veinMask * vein_val * 2.0 + nutrientGlow * 0.8;
  final_rgb = final_rgb + glow * vec3<f32>(0.2, 0.4, 0.6);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  final_rgb = mix(final_rgb, prev * 0.9, 0.05 + bass * 0.02);

  final_rgb = clamp(final_rgb, vec3<f32>(0.0), vec3<f32>(2.0));

  textureStore(writeTexture, coord, vec4(final_rgb, 1.0));
  textureStore(dataTextureA, coord, vec4(final_rgb, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
```
