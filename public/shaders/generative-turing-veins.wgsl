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
//  colonies (rising edge tracked in extraBuffer[133], colony state [134..136]).
//  Upgraded: 2026-10-19
//  Ideas: isotropic 9-point RD stencil (§12.2D Isotropic 9-point Laplacian);
//         reaction-front sprouting tips (a*b^2 promoted, lights growing vein tips);
//         flow-driven vessel remodelling (exact C luma re-feeds lit vessels)
//  A packing: linear colour history RGB (pre-ACES, clamped 0..2) + semantic alpha;
//             C read back as colour. ACES on writeTexture only.
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

// ── Idea 1: isotropic 9-point RD stencil (§12.2D) ──
// The 5-point Laplacian (mean of 4 - centre) is axis-biased, so veins
// favoured 0/90 degrees. The Mehrstellen 9-point stencil
// (4*edges + diagonals - 20*centre)/24 has the same h^2 coefficient (0.25)
// as the old mean-of-4 form, so the Primary Scale -> diffusion relation is
// unchanged; only the directional bias goes.
fn lapActivator(p: vec2<f32>, r: f32, c: f32) -> f32 {
  let edges = activatorField(p + vec2<f32>(r, 0.0)) + activatorField(p - vec2<f32>(r, 0.0))
            + activatorField(p + vec2<f32>(0.0, r)) + activatorField(p - vec2<f32>(0.0, r));
  let diags = activatorField(p + vec2<f32>(r, r)) + activatorField(p + vec2<f32>(-r, r))
            + activatorField(p + vec2<f32>(r, -r)) + activatorField(p - vec2<f32>(r, r));
  return (4.0 * edges + diags - 20.0 * c) / 24.0;
}

fn lapInhibitor(p: vec2<f32>, r: f32, c: f32) -> f32 {
  let edges = inhibitorField(p + vec2<f32>(r, 0.0)) + inhibitorField(p - vec2<f32>(r, 0.0))
            + inhibitorField(p + vec2<f32>(0.0, r)) + inhibitorField(p - vec2<f32>(0.0, r));
  let diags = inhibitorField(p + vec2<f32>(r, r)) + inhibitorField(p + vec2<f32>(-r, r))
            + inhibitorField(p + vec2<f32>(r, -r)) + inhibitorField(p - vec2<f32>(r, r));
  return (4.0 * edges + diags - 20.0 * c) / 24.0;
}

// One explicit Gray-Scott step with a Laplacian whose reach is the
// kernel radius. Activator/inhibitor are clamped to [0,1] after the update
// so the explicit scheme can never blow up, no matter the slider state.
// Returns (a, b, reaction) — z is the a*b^2 growth term (Idea 2).
fn turing_pattern(uv: vec2<f32>, time: f32, scale: f32, feed: f32, kernelRadius: f32) -> vec3<f32> {
  let p = uv * scale + vec2<f32>(time * 0.1, time * 0.07);
  var a = activatorField(p);
  var b = inhibitorField(p);
  let r = max(kernelRadius, 0.02);
  let lapA = lapActivator(p, r, a);
  let lapB = lapInhibitor(p, r, b);
  let f = clamp(feed, FEED_MIN, FEED_MAX);
  let k = KILL_BASE;
  let reaction = a * b * b;
  a = a + (lapA * 0.6 - reaction + f * (1.0 - a)) * 0.9;
  b = b + (lapB * 0.3 + reaction - (f + k) * b) * 0.9;
  return vec3<f32>(clamp(vec2<f32>(a, b), vec2<f32>(0.0), vec2<f32>(1.0)), reaction);
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
  // .w was an unused echo of `feed`; it now carries the coarse+fine reaction rate (Idea 2).
  return vec4<f32>(coarse, fine, micro, p1.z + p2.z * 0.6);
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
  //    activator colony that persists for a few seconds via [134..136]. ──
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

  // ── Idea 3: flow-driven vessel remodelling ──
  // Vessels that carried flow persist, unused ones regress. Last frame's vessel
  // luminance (exact C load, colour history) re-feeds a little activator where the
  // network was already lit, in proportion to the vein that is already there.
  let prevC = textureLoad(dataTextureC, coord, 0);
  let prevFlow = smoothstep(0.25, 1.1, dot(prevC.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)));
  veinsRaw = clamp(veinsRaw + prevFlow * veinsRaw * 0.18, 0.0, 1.0);
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

  // ── Idea 2: reaction-front sprouting tips ──
  // Gray-Scott growth happens where a*b^2 peaks: the advancing fronts and tips
  // of veins. The reaction rate the step already computed (scales.w) is
  // normalised (top ~quartile of a*b^2, typical 0.6..3) and gated to the vein ridge, lighting sprouting tips in the
  // activator green; gain rides Vein Glow (bioGain).
  let sprout = smoothstep(1.6, 2.6, scales.w) * veinMask * (0.35 + veinRidge * 0.65);
  final_rgb = final_rgb + sprout * vec3<f32>(0.35, 1.0, 0.6) * (0.25 + bioGain * 0.35);

  // History blend (exact load, see Idea 3). (Idea 3) Lit ridges hold their past a
  // little longer, so established vessels change slowly while new branches fade in.
  let prev = prevC.rgb;
  let holdRidge = prevFlow * veinRidge * 0.12;
  final_rgb = mix(final_rgb, prev * 0.9, 0.05 + bass * 0.02 + holdRidge);

  final_rgb = clamp(final_rgb, vec3<f32>(0.0), vec3<f32>(2.0));

  // Semantic alpha: opacity follows vein intensity + glow, not a constant.
  let alpha = clamp(0.45 + veinMask * 0.35 + veinRidge * bioGain * 0.2, 0.0, 1.0);

  // Display: ACES on the clamped linear colour; A keeps the linear history C reads.
  let display = clamp((final_rgb * (2.51 * final_rgb + 0.03)) / (final_rgb * (2.43 * final_rgb + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
  textureStore(writeTexture, coord, vec4(display, alpha));
  textureStore(dataTextureA, coord, vec4(final_rgb, alpha));
  // Truthful relief: vessels stand proud of the dark tissue.
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(veinMask * 0.6 + veinRidge * 0.4, 0.0, 1.0), 0.0, 0.0, 0.0));
}
