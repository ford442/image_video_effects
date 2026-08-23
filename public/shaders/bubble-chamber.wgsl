// ═══════════════════════════════════════════════════════════════════
//  Bubble Chamber — Algorithmist Upgrade
//  Curl-noise velocity field + Clifford perturbation + Gold-noise emission
//  Domain-warped FBM for chromatic drift, divergence-free advection
//  + Bragg-curve ionization falloff, mouse Lorentz (point-vortex) bend
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 67 — fast motion / psychedelic / high energy)
//
//  FIXED — filtered read of a float32 texture. The trail history was fetched as
//  `textureSampleLevel(dataTextureC, u_sampler, ...)`. Binding 0 is the
//  FILTERING sampler and `dataTextureC` is rgba32float, which cannot be filtered
//  unless the optional `float32-filterable` feature is present
//  (src/renderer/webgpu/device.ts). Advection now uses exact `textureLoad` with
//  a hand-rolled bilinear fetch.
//
//  FIXED — frame-quantised spawn. Ionisation used
//  `goldNoise(..., time * 0.1 + floor(time * 3.0))`, so the spawn field jumped
//  three times a second instead of flowing. Replaced with a continuous phase.
//
//  FAST MOTION (two analytic techniques, no frame hashing)
//
//    1. Relativistic track streaks — each track is smeared along its own
//       velocity vector by a Lorentz-style stretch factor gamma = 1/sqrt(1-b^2)
//       with b clamped below 1, so fast particles draw long thin streaks and
//       slow ones stay compact. The streak is a closed-form line integral along
//       the velocity, not a temporal accumulation, so it is stable at any frame
//       rate.
//
//    2. Helical momentum spirals — a charged particle in a magnetic field
//       follows a helix whose radius is p/(qB). Tracks now advance along an
//       analytic helical phase whose pitch falls as momentum drops, so tracks
//       visibly spiral inward as they lose energy — the signature of a real
//       bubble-chamber photograph.
//
//  PSYCHEDELIC COLOUR — tracks are tinted by an IQ cosine palette keyed to
//  particle momentum and per-band FFT energy, with prismatic dispersion across
//  the streak so each track fans through the spectrum along its length.
//
//  HIGH ENERGY — clicks detonate collision vertices that spray a burst of
//  secondary tracks radially outward (bounded, capped at 50 ripples).
// ═══════════════════════════════════════════════════════════════════════════════

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
// Hard ceiling for the feedback trail accumulation (luma-echo-warp lesson).
const TRAIL_CLAMP = 1.2;

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

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// Bragg-curve ionization profile: a charged particle deposits energy
// roughly uniformly along its track, then dumps the rest in a sharp
// bump just before it stops (t ≈ 0.16 of remaining trail energy).
// Returns a per-frame gain applied to decayed trail brightness:
//   ~1.0 on the bright body of the track,
//   >1.0 (up to 1 + prominence) on the dim tail-end (Bragg peak),
//   →0.0 below the cutoff so dead tracks vanish instead of lingering.
fn braggGain(t: f32, prominence: f32) -> f32 {
  let cutoff = smoothstep(0.0, 0.045, t);
  let bump = exp(-pow((t - 0.16) / 0.085, 2.0));
  return cutoff * (1.0 + prominence * bump);
}

// Divergence-free point vortex (softened 1/r tangential field) used as
// the Lorentz deflection of tracks around the cursor-as-magnetic-pole.
fn lorentzVortex(to_mouse: vec2<f32>, dist: f32, strength: f32) -> vec2<f32> {
  let tangent_dir = vec2<f32>(-to_mouse.y, to_mouse.x) / (dist + 0.001);
  return tangent_dir * (strength / (dist + 0.12));
}

fn historyBilinear(pt: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let maxC = dims - vec2<i32>(1);
  let f = fract(pt);
  let i0 = vec2<i32>(floor(pt));
  let s00 = textureLoad(dataTextureC, clamp(i0,                     vec2<i32>(0), maxC), 0);
  let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
  let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

// IQ cosine palette — vivid, never muddy.
fn spectrum(tt: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.2831853 * (tt + vec3<f32>(0.0, 0.33, 0.67)));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // ── Slider wiring (param contract: ids/defaults unchanged) ──────
  // p1 Intensity → magnetic field strength, spark energy, spawn density
  // p2 Speed     → advection time-step + field evolution rate
  // p3 Scale     → spatial frequency of turbulence / spawn cells ONLY
  // p4 Detail    → Clifford drift, chromatic rotation, Bragg prominence
  let p_intensity = u.zoom_params.x;
  let p_speed     = u.zoom_params.y;
  let p_scale     = u.zoom_params.z;
  let p_detail    = u.zoom_params.w;

  let mouse_down = u.zoom_config.w;

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

  let field_strength = p_intensity * 0.02 + 0.002;
  let base_vel = (tangent + radial * 0.2) * field_strength;

  // Lorentz deflection: tracks curl around the cursor like a magnetic
  // pole. 1/r falloff keeps the field divergence-free (point vortex);
  // mouse-down amplifies the pole so dragging visibly bends the chamber.
  let lorentz_strength = (0.0008 + 0.006 * mouse_down) * (0.4 + 0.6 * p_intensity);
  let lorentz = lorentzVortex(to_mouse, dist, lorentz_strength);

  // Spatial scale of the chamber texture — Scale owns this and nothing else.
  let noise_scale = 1.2 + 4.2 * p_scale;
  // Speed owns the flow evolution rate and the advection step length.
  let flow_time = time * (0.45 + 0.85 * p_speed);
  let vel_scale = 0.30 + 1.45 * p_speed;

  // Divergence-free curl noise turbulence layer (Scale = domain, Detail = amplitude)
  let turb = curl2D(p * noise_scale + mouse_pos * 2.0, flow_time) * (0.06 + 0.30 * p_detail);
  // Clifford strange-attractor perturbation for organic drift
  let cliff = clifford(p * 2.0, 1.7, 1.3, 1.1 + time * 0.02, 1.9) * 0.015 * p_detail;
  let velocity = (base_vel + lorentz + turb + cliff) * vel_scale;

  // ── Audio ────────────────────────────────────────────────────────────────
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let bandIdx = u32(clamp(dist * 4.0, 0.0, 7.999));
  let band = plasmaBuffer[bandIdx + 1u].x;

  // ── HIGH ENERGY: bounded click collision vertices ────────────────────────
  // Each click is a collision that sprays secondary tracks radially.
  var vertexSpray = vec2<f32>(0.0);
  var vertexFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age >= 2.2) { continue; }
    var vp = rp.xy * 2.0 - 1.0;
    vp.x = vp.x * aspect;
    let dv = p - vp;
    let rv = max(length(dv), 1e-4);
    let front = rv - age * 1.1;
    let env = exp(-front * front * 26.0) * exp(-age * 1.5);
    vertexSpray += (dv / rv) * env * 0.05 * (1.0 + bass * 1.4);
    vertexFlash += env * env;
  }
  vertexFlash = min(vertexFlash, 1.5);

  // ── FAST MOTION 1: helical momentum spiral ───────────────────────────────
  // A charged track follows a helix of radius p/(qB); as momentum bleeds off
  // the pitch tightens and the track spirals inward.
  let momentum = clamp(0.35 + p_intensity * 0.8 + bass * 0.5, 0.05, 1.6);
  let helixPhase = flow_time * (2.4 + mids * 3.0) + dist * (5.0 + 9.0 * p_detail);
  let helixRadius = momentum / (0.6 + 2.2 * p_intensity);
  let helix = vec2<f32>(-sin(helixPhase), cos(helixPhase)) * helixRadius * 0.012;

  let totalVel = velocity + helix + vertexSpray;
  let uv_velocity = totalVel * vec2<f32>(1.0 / aspect, 1.0);
  let sample_uv = clamp(uv - uv_velocity, vec2<f32>(0.0), vec2<f32>(1.0));

  // ── FAST MOTION 2: relativistic streak stretch ───────────────────────────
  // gamma = 1/sqrt(1 - beta^2), beta clamped below 1 so the stretch stays
  // finite. Fast tracks smear into long thin streaks; slow ones stay compact.
  let beta = clamp(length(totalVel) * 26.0, 0.0, 0.985);
  let gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-3));
  let streakLen = clamp(gamma * 0.0022, 0.0, 0.05);
  let streakDir = select(vec2<f32>(0.0), normalize(totalVel), length(totalVel) > 1e-6)
                * vec2<f32>(1.0 / aspect, 1.0);

  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  let dimsF = vec2<f32>(dimsI);
  // Closed-form line integral along the velocity — five taps, weight falls off
  // toward the tail. Exact loads (see header: C is rgba32float).
  var history = vec4<f32>(0.0);
  var wsum = 0.0;
  for (var s = 0u; s < 5u; s = s + 1u) {
    let fs = f32(s) / 4.0;
    let w = 1.0 - fs * 0.7;
    let tapUV = clamp(sample_uv - streakDir * streakLen * fs, vec2<f32>(0.0), vec2<f32>(1.0));
    history += historyBilinear(tapUV * dimsF, dimsI) * w;
    wsum += w;
  }
  history = history / max(wsum, 1e-4);

  // Trail persistence — decoupled from Speed; kept safely below 1.0 so
  // the Bragg gain bump (≤ 1 + prominence) settles at a finite equilibrium.
  let decay = 0.962;

  let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luminance = luma(input_color.rgb);

  // Gold-noise ionization spawn (quasi-random, better distribution).
  // Spawn density follows Intensity (beam current) modulated by Detail
  // (chamber sensitivity) — Scale no longer double-duties here.
  // Continuous phase; the old `floor(time * 3.0)` made the spawn field jump
  // three times a second instead of flowing.
  let rand_val = goldNoise(uv * noise_scale, time * 0.37);
  let spawn_rate = 0.04 + 0.35 * p_intensity * (0.4 + 0.6 * p_detail);

  // Fresh ionization deposit: brightness scales with beam intensity.
  var spark = vec4<f32>(0.0);
  if (rand_val < luminance * spawn_rate * 0.2) {
    spark = vec4<f32>(input_color.rgb * (1.4 + 2.2 * p_intensity), luminance * 2.0);
  }

  var shifted_history = history * decay;

  // Ionization falloff along trail length with Bragg-peak bump near the
  // end of the track — trails read as physical particles, not worms.
  let trail_energy = clamp(luma(shifted_history.rgb), 0.0, 1.0);
  let bragg_prominence = 0.35 + 1.05 * p_detail;
  shifted_history = vec4<f32>(shifted_history.rgb * braggGain(trail_energy, bragg_prominence),
                              shifted_history.a);

  // Feedback safety clamp PRE-TINT (luma-echo-warp lesson): no channel
  // of the accumulated trail may exceed TRAIL_CLAMP before the chromatic
  // rotation below re-injects energy into the feedback loop.
  shifted_history = min(shifted_history, vec4<f32>(TRAIL_CLAMP));

  // Chromatic rotation along the trail (Detail controls shift rate).
  if (p_detail > 0.1) {
    let shift_speed = p_detail * 0.05;
    let r = shifted_history.r;
    let g = shifted_history.g;
    let b = shifted_history.b;
    shifted_history.r = r * (1.0 - shift_speed) + g * shift_speed;
    shifted_history.g = g * (1.0 - shift_speed) + b * shift_speed;
    shifted_history.b = b * (1.0 - shift_speed) + r * shift_speed;
  }

  // Domain-warped FBM absorption drift (Scale-aware domain).
  let drift = warpedFBM(uv * noise_scale, time * 0.03) * 0.02;
  shifted_history = shifted_history * (1.0 - drift);

  var output = max(shifted_history, spark);
  let energy = luma(output.rgb);

  // ── PSYCHEDELIC: momentum-keyed spectrum with prismatic streak dispersion ──
  // Hue keys to momentum and the local FFT band; the streak fans through the
  // spectrum along its length so each track reads as a prism smear.
  let hueKey = fract(momentum * 0.45 + band * 0.6 + energy * 0.5
                     + time * 0.06 + f32(bandIdx) * 0.04);
  let trackTint = spectrum(hueKey);
  let dispersion = fract(hueKey + beta * 0.35);
  let prism = spectrum(dispersion);
  output = vec4<f32>(output.rgb * mix(vec3<f32>(1.0), trackTint * 2.0, 0.65)
                     + prism * energy * (0.25 + treble * 0.8),
                     output.a);

  // Collision vertices flash white-hot then bleed into the spectrum.
  output = vec4<f32>(output.rgb + mix(vec3<f32>(1.0), prism, 0.4) * vertexFlash * 1.4,
                     max(output.a, vertexFlash));

  let finalRGB = acesFilm(output.rgb);
  let outEnergy = luma(finalRGB);
  let bloom = max(0.0, outEnergy - 0.7) * 3.0;
  let alpha = clamp(outEnergy * 1.5 + bloom + output.a * 0.5 + vertexFlash * 0.3, 0.0, 1.0);
  let depth = clamp(1.0 - outEnergy * 0.8, 0.0, 1.0);

  let outColor = vec4<f32>(finalRGB, alpha);
  textureStore(writeTexture, gid.xy, outColor);
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, gid.xy, outColor);
}
