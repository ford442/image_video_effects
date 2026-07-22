// ═══════════════════════════════════════════════════════════════
// Generative Turing Veins - PASS 1 of 1
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            multi-scale-reaction-diffusion, vein-thickness, nutrient-flow,
//            upgraded-rgba, depth-aware, slider-wired-rd, click-seeding
//  Multiscale reaction-diffusion Turing patterns generating organic
//  vein/network structures with bioluminescent glow. Evolves procedurally
//  over time with depth-modulated complexity. Pure generative output.
//  Created: 2026-05-31
//  Upgraded: 2026-06-28
//  Upgraded: 2026-07-22 (Algorithmist) — sliders wired to real sim constants:
//    Primary Scale   -> Gray-Scott kernel radius (5-point Laplacian reach)
//    Secondary Scale -> secondary RD layer scale
//    Feed Rate       -> Gray-Scott feed, striped-vein regime (0.03-0.07)
//    Vein Glow       -> bioluminescent gain on vein ridges
//  Plus: bass radial nutrient pulse on feed, click-seeded activator
//  colonies (rising edge tracked in extraBuffer[133], colony state [6..8]).
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Gray-Scott regime guards: feed must stay inside the striped-vein band,
// otherwise the pattern collapses to uniform spots or dies out entirely.
const FEED_MIN: f32 = 0.03;
const FEED_MAX: f32 = 0.07;
const KILL_BASE: f32 = 0.062;

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

// ── Reaction-diffusion state fields ─────────────────────────────
// The activator/inhibitor "concentrations" are sampled from drifting fbm
// fields; the explicit Gray-Scott step below reacts/diffuses them once per
// frame. This keeps the original organic look while making the sim
// constants (kernel radius, feed) genuinely controllable.
fn activatorField(p: vec2<f32>) -> f32 {
  return fbm(p, 4);
}

fn inhibitorField(p: vec2<f32>) -> f32 {
  return fbm(p * 0.5 + vec2<f32>(11.3, 7.9), 3);
}

// One explicit Gray-Scott step with a 5-point Laplacian whose reach is the
// kernel radius. Activator/inhibitor are clamped to [0,1] after the update
// so the explicit scheme can never blow up, no matter the slider state.
fn turing_pattern(uv: vec2<f32>, time: f32, scale: f32, feed: f32, kernelRadius: f32) -> vec2<f32> {
  let p = uv * scale + vec2<f32>(time * 0.1, time * 0.07);
  var a = activatorField(p);
  var b = inhibitorField(p);
  let r = max(kernelRadius, 0.02);
  let lapA = (activatorField(p + vec2<f32>(r, 0.0)) + activatorField(p - vec2<f32>(r, 0.0))
            + activatorField(p + vec2<f32>(0.0, r)) + activatorField(p - vec2<f32>(0.0, r))) * 0.25 - a;
  let lapB = (inhibitorField(p + vec2<f32>(r, 0.0)) + inhibitorField(p - vec2<f32>(r, 0.0))
            + inhibitorField(p + vec2<f32>(0.0, r)) + inhibitorField(p - vec2<f32>(0.0, r))) * 0.25 - b;
  let f = clamp(feed, FEED_MIN, FEED_MAX);
  let k = KILL_BASE;
  let reaction = a * b * b;
  a = a + (lapA * 0.6 - reaction + f * (1.0 - a)) * 0.9;
  b = b + (lapB * 0.3 + reaction - (f + k) * b) * 0.9;
  return clamp(vec2<f32>(a, b), vec2<f32>(0.0), vec2<f32>(1.0));
}

// Three coupled RD layers. The kernel radius comes from the Primary Scale
// slider and reaches every layer; the Secondary Scale slider owns layer 2.
fn multi_scale_turing(uv: vec2<f32>, time: f32, secScale: f32, feed: f32, kernelRadius: f32) -> vec4<f32> {
  let p1 = turing_pattern(uv, time, 2.0, feed, kernelRadius);
  let p2 = turing_pattern(uv * 1.3 + vec2<f32>(0.4, -0.2), time * 0.8, secScale, feed * 0.92, kernelRadius * 0.7);
  let p3 = turing_pattern(uv * 0.7 + vec2<f32>(-0.3, 0.5), time * 1.2, 5.0, feed * 1.05, kernelRadius * 0.5);

  let coarse = clamp((p1.x * p2.y + p1.y * p2.x) * 2.0, 0.0, 1.0);
  let fine = clamp((p2.x * p3.y + p2.y * p3.x) * 2.5, 0.0, 1.0);
  let micro = clamp(abs(p3.x - p3.y) * 3.0, 0.0, 1.0);
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
  let zp = u.zoom_params;
  var mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Slider wiring: each param drives a real RD sim constant ───
  // Primary Scale (0-1)   -> Gray-Scott kernel radius of the 5-point
  //                          Laplacian: wider kernel = thicker, lazier veins.
  let kernelRadius = mix(0.05, 0.35, clamp(zp.x, 0.0, 1.0));
  // Secondary Scale (0-1) -> scale of the second RD layer only.
  let secScale = mix(0.75, 2.25, clamp(zp.y, 0.0, 1.0));
  // Feed Rate (0-1)       -> Gray-Scott feed, locked to the striped-vein
  //                          regime 0.03-0.07 so the pattern never dies.
  var feed = mix(FEED_MIN, FEED_MAX, clamp(zp.z, 0.0, 1.0));
  // Vein Glow (0-1.5!)    -> bioluminescent gain on the vein ridges.
  //                          NOTE: this slider's max is 1.5, not 1.0.
  let bioGain = mix(0.2, 2.4, clamp(zp.w, 0.0, 1.5) / 1.5);

  // ── Bass nutrient pulse: slow radial wave from center modulates
  //    the feed rate so veins visibly swell/grow on the beat. ─────
  let aspect = resolution.x / max(resolution.y, 1.0);
  let centerDist = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
  let radialWave = sin(TAU * (centerDist * 2.5 - time * 0.35));
  feed = clamp(feed + bass * radialWave * 0.012, FEED_MIN, FEED_MAX);

  // ── Click seeding: rising edge of mouse-down (tracked in
  //    extraBuffer[133]; [0..4] are engine-reserved) plants a gaussian
  //    activator colony that persists for a few seconds via [6..8]. ──
  let mouseDown = u.zoom_config.w > 0.5;
  let wasDown = extraBuffer[133] > 0.5;
  let clickEdge = f32(mouseDown) * (1.0 - f32(wasDown));
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = f32(mouseDown); // single writer; all threads read next frame
    if (clickEdge > 0.5) {
      extraBuffer[134] = mouse.x;
      extraBuffer[135] = mouse.y;
      extraBuffer[136] = time;
    }
  }
  let colonyPos = vec2<f32>(extraBuffer[134], extraBuffer[135]);
  let colonyAge = max(time - extraBuffer[136], 0.0);
  let colonyDist = distance(uv * vec2<f32>(aspect, 1.0), colonyPos * vec2<f32>(aspect, 1.0));
  let colonySeed = exp(-colonyDist * colonyDist * 220.0) * exp(-colonyAge * 0.8) * step(0.001, extraBuffer[136]);

  let warpedUV = uv + vec2<f32>(
    fbm(uv * 3.0 + vec2<f32>(time * 0.1, 0.0), 3) - 0.5,
    fbm(uv * 3.0 + vec2<f32>(0.0, time * 0.12), 3) - 0.5
  ) * 0.04 * (1.0 + mids);

  let scales = multi_scale_turing(warpedUV + mouse * 0.1, time, secScale, feed, kernelRadius);
  var veinsRaw = scales.x * 0.55 + scales.y * 0.35 + scales.z * 0.15;
  // The planted colony injects activator: new veins nucleate around clicks.
  veinsRaw = clamp(veinsRaw + colonySeed * 0.8, 0.0, 1.0);
  let veinMask = veinThickness(warpedUV, veinsRaw, time);
  // Ridge mask: bright spine between the activator/inhibitor flanks.
  let veinRidge = smoothstep(0.3, 0.7, veinsRaw) * (1.0 - smoothstep(0.7, 1.0, abs(veinsRaw - 0.5) * 2.0));

  let nutrients = nutrientFlow(warpedUV, time, veinMask);
  let nutrientGlow = nutrients * (0.6 + treble * 0.4);

  let actColor = vec3<f32>(0.2, 0.9, 0.5) * scales.x * (1.0 + treble * 0.3);
  let inhColor = vec3<f32>(0.9, 0.3, 0.6) * scales.y * (1.0 + mids * 0.3);
  let vein_hue = fract(veinsRaw * 0.3 + time * 0.1 + scales.y * 0.5);
  let vein_sat = 0.8 + 0.2 * sin(time * 2.0);
  let vein_val = pow(veinMask, 0.5) * (0.7 + bioGain * 0.3);
  var vein_color = mix(vec3(vein_hue, vein_sat, vein_val), actColor + inhColor, 0.3 + bass * 0.2);

  let nutrientColor = vec3<f32>(0.9, 0.95, 0.3) * nutrientGlow;
  let deepColor = vec3<f32>(0.05, 0.08, 0.12) * (1.0 - veinMask);
  var final_rgb = deepColor + vein_color * veinMask + nutrientColor;

  // Bioluminescent ridge glow, driven by the Vein Glow slider (bioGain).
  let glow = (veinMask * vein_val + veinRidge * bioGain) + nutrientGlow * 0.8;
  final_rgb = final_rgb + glow * vec3<f32>(0.2, 0.4, 0.6);
  // Fresh colonies flash bright cyan-green at the click point.
  final_rgb = final_rgb + colonySeed * vec3<f32>(0.3, 0.9, 0.7) * (0.5 + bioGain);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  final_rgb = mix(final_rgb, prev * 0.9, 0.05 + bass * 0.02);

  final_rgb = clamp(final_rgb, vec3<f32>(0.0), vec3<f32>(2.0));

  // Semantic alpha: opacity follows vein intensity + glow, not a constant.
  let alpha = clamp(0.45 + veinMask * 0.35 + veinRidge * bioGain * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4(final_rgb, alpha));
  textureStore(dataTextureA, coord, vec4(final_rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
