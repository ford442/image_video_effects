// ═══════════════════════════════════════════════════════════════════
//  Magnetic Dipole Field Lines
//  Category: generative
//  Description: Procedurally rendered magnetic dipole field lines
//    with charged particle trajectories. Simulates iron filings
//    aligning to field lines with glowing ionized particles.
//    Mouse moves the dipole position and strength.
//  Complexity: Medium
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  Magnetic Dipole Field
//  Category: generative
//  Features: magnetic, dipole, field, audio-reactive, mouse-interactive,
//    semantic-alpha, fast-motion, analytic-fieldline-advection,
//    velocity-aligned-motion-blur, temporal-feedback, hdr-clamped
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-08-06 (Batch 38 FAST MOTION — Optimizer pass)
//  By: Kimi Agent (Bright batch)
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CAP: f32 = 6.0;        // hard bound for feedback history energy
const MAX_PARTICLES: i32 = 14;   // bounded primary particle iterations
const MAX_IONS: i32 = 10;        // bounded fast-ion iterations

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Branchless hue-to-RGB via array lookup
fn field_palette(t: f32, p4: f32) -> vec3<f32> {
  let hue = fract(t * 0.7 + p4);
  let h = hue * 6.0;
  let c = 0.8;
  let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
  let m = 0.1;
  let rgb_table = array<vec3<f32>, 6>(
    vec3<f32>(c, x, 0.0), vec3<f32>(x, c, 0.0), vec3<f32>(0.0, c, x),
    vec3<f32>(0.0, x, c), vec3<f32>(x, 0.0, c), vec3<f32>(c, 0.0, x)
  );
  return rgb_table[clamp(i32(h), 0, 5)] + vec3<f32>(m);
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

// Smooth value noise — temporal-coherent (no hash-jitter strobing)
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x),
    w.y
  );
}

// Analytic dipole B-field: B = (3(m·r)r − m r²) / r⁵  (m along +y)
fn dipoleB(r: vec2<f32>, moment: f32) -> vec2<f32> {
  let r_sq = dot(r, r);
  let safe_r = max(sqrt(r_sq), 0.01);
  let inv_r2 = 1.0 / (safe_r * safe_r);
  let inv_r5 = inv_r2 * inv_r2 / safe_r;
  return (3.0 * moment * r.y * r - vec2<f32>(0.0, moment) * r_sq) * inv_r5;
}

// Evaluate field and particles at a given UV, returning color + particle density in alpha.
// withParticles=false skips the particle loops (cheap variant for the ghost dipole).
fn sampleField(uv: vec2<f32>, time: f32, p1: f32, p2: f32, p3: f32, p4: f32, dipole: vec2<f32>, bass: f32, ionDrive: f32, withParticles: bool) -> vec4<f32> {
  let r = uv - dipole;
  let r_sq = dot(r, r);
  let dipole_moment = 1.0 + p1 * 2.0;
  let B = dipoleB(r, dipole_moment);
  let B_len = length(B);
  let B_dir = B / max(B_len, 0.0001);
  let line_density = 4.0 + p3 * 20.0;
  let perp_B = vec2<f32>(-B_dir.y, B_dir.x);
  let stream_val = dot(uv, perp_B) * line_density;
  let field_line = exp(-abs(stream_val - round(stream_val)) * 40.0);
  let intensity = dipole_moment / (r_sq + 0.02);

  var particle_glow = 0.0;
  if (withParticles) {
    // ── FAST MOTION: analytic closed-form advection along dipole field lines ──
    // Dipole field lines satisfy r = L·sin²θ. A particle's position on its line
    // is a pure function of time (no per-frame integration → frame-rate
    // independent and O(1) per particle). Triangle-wave phase bounces the
    // particle pole-to-pole smoothly (no wrap jump / streak pop).
    let speed_scale = (0.4 + p2 * 3.5) * (1.0 + bass * 0.9);
    let num_particles = min(i32(4.0 + p1 * 10.0), MAX_PARTICLES);
    for (var i = 0; i < num_particles; i++) {
      let seed = f32(i) * 157.0;
      let h1 = hashf(seed);
      let h2 = hashf(seed + 1.0);
      let h3 = hashf(seed + 2.0);
      let line_L = 0.06 + h2 * 0.42;                       // field-line constant
      let phase = fract(h1 + time * (0.08 + h3 * 0.22) * speed_scale);
      let tri = 1.0 - abs(1.0 - 2.0 * phase);              // 0→1→0 smooth bounce
      let theta = tri * PI;
      let st = sin(theta);
      let rr = line_L * st * st;
      let p_pos = dipole + vec2<f32>(cos(theta), sin(theta)) * rr;
      let d = uv - p_pos;
      particle_glow += exp(-dot(d, d) * 500.0) * 0.35;
    }

    // Secondary fast ion population (audio-excited) — tighter lines, higher speed
    let fast_count = min(i32(clamp(bass * 5.0 + ionDrive * 6.0, 0.0, 10.0)), MAX_IONS);
    for (var i = 0; i < fast_count; i++) {
      let seed = f32(i) * 293.0;
      let h1 = hashf(seed + 7.0);
      let h2 = hashf(seed + 11.0);
      let h3 = hashf(seed + 13.0);
      let line_L = 0.03 + h2 * 0.16;
      let phase = fract(h1 + time * (0.35 + h3 * 0.6) * speed_scale);
      let tri = 1.0 - abs(1.0 - 2.0 * phase);
      let theta = tri * PI;
      let st = sin(theta);
      let rr = line_L * st * st;
      let p_pos = dipole + vec2<f32>(cos(theta), sin(theta)) * rr;
      let d = uv - p_pos;
      particle_glow += exp(-dot(d, d) * 700.0) * 0.28 * (1.0 + bass);
    }
  }

  let field_contrib = field_line * intensity * 0.15;
  let total_intensity = field_contrib + particle_glow;
  let strength_norm = clamp(intensity * 0.3, 0.0, 1.0);
  var color = field_palette(strength_norm + field_line * 0.2, p4) * total_intensity;
  let bg_glow = dipole_moment * 0.03 / (r_sq + 0.1);
  color += vec3<f32>(0.05, 0.08, 0.15) * bg_glow;
  color += vec3<f32>(0.8, 0.9, 1.0) * particle_glow * 0.5;
  return vec4<f32>(color, particle_glow);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  // Bounds guard — mandatory
  if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // Guarded engine FFT bins 1–8 (extraBuffer[5+bin]) — read-only audio spectrum
  var fftLo = 0.0;
  var fftHi = 0.0;
  if (arrayLength(&extraBuffer) > 13u) {
    fftLo = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) * 0.3333;
    fftHi = (extraBuffer[11] + extraBuffer[12] + extraBuffer[13]) * 0.3333;
  }
  let ionDrive = clamp(fftLo * 0.5, 0.0, 1.5);

  // Branchless dipole selection (mouse when pressed, slow auto-drift otherwise)
  let auto_dipole = vec2<f32>(0.0, sin(time * p2 * 0.15) * 0.1);
  let mouse_dipole = (mouse - 0.5) * 2.0;
  let dipole = select(auto_dipole, mouse_dipole, mouseDown);

  let dipole_moment = 1.0 + p1 * 2.0;
  let r = uv - dipole;
  let r_sq = dot(r, r);
  let field_intensity = dipole_moment / (r_sq + 0.02);

  // ── Single full field evaluation (was 4×: R/G/B chromatic + ghost) ──
  let gResult = sampleField(uv, time, p1, p2, p3, p4, dipole, bass, ionDrive, true);
  var color = gResult.rgb;

  // Ghost dipole orbiting for topological complexity — cheap variant, no particle loops
  let ghost_angle = time * p2 * 0.4 + bass * 3.0;
  let ghost_dipole = dipole + vec2<f32>(cos(ghost_angle), sin(ghost_angle)) * 0.12;
  let ghostResult = sampleField(uv, time, p1 * 0.4, p2, p3, p4 + 0.3, ghost_dipole, bass, 0.0, false);
  color += ghostResult.rgb * 0.12 * (1.0 + bass * 0.6);

  // Analytic chromatic split (replaces 2 extra full field evaluations):
  // tangential direction around the dipole tints R/B channels in opposition.
  let caStr = 0.25 * field_intensity / (1.0 + field_intensity) * (0.4 + bass * 0.6);
  let caDir = normalize(vec2<f32>(r.y, -r.x) + vec2<f32>(0.001));
  color = vec3<f32>(
    color.r * (1.0 + caDir.x * caStr),
    color.g,
    color.b * (1.0 - caDir.x * caStr * 0.6)
  );

  // Field magnitude contours
  let contour = abs(fract(log(field_intensity + 1.0) * 3.0) - 0.5) * 2.0;
  let contour_glow = exp(-contour * contour * 30.0) * 0.08 * depth;
  color += field_palette(fract(field_intensity * 0.05 + p4), p4) * contour_glow;

  // Magnetic storm shimmer — smooth temporal-coherent value noise (was per-frame
  // hash jitter → strobed at speed). Treble/FFT-driven.
  let storm = valueNoise(uv * 22.0 + vec2<f32>(time * 2.6, -time * 1.9));
  color += vec3<f32>(0.3, 0.5, 0.8) * (bass * 0.12 + fftHi * 0.25 + treble * 0.05) * storm * min(field_intensity * 0.1, 1.0);

  // Aurora-like background glow
  let aurora = sin(uv.x * 3.0 + time * p2 * 0.6) * exp(-abs(uv.y) * 2.0);
  color += vec3<f32>(0.1, 0.4, 0.3) * aurora * 0.05 * (1.0 + bass);

  // Subtle pulsing (time-warped, frame-rate independent)
  color *= 1.0 + sin(time * (1.2 + p2 * 2.0)) * 0.07;

  // Depth-based intensity falloff + bass modulation
  color *= 0.5 + 0.5 * depth;
  color *= 1.0 + bass * 0.4;

  // ── FAST MOTION: velocity-aligned motion-blur feedback ──
  // Backtrace along the local field direction (particle velocity is tangent to
  // B) so fast particles streak along field lines. textureLoad only, integer
  // pixel offset, displacement clamped. HDR history hard-clamped ≤ HDR_CAP so
  // speed never blows up the feedback loop.
  let Bv = dipoleB(r, dipole_moment);
  let Bv_len = length(Bv);
  let Bv_dir = Bv / max(Bv_len, 0.0001);
  let blur_px = clamp((2.0 + p2 * 14.0) * (0.5 + bass * 0.9), 0.0, 22.0);
  let max_px = vec2<i32>(resolution) - vec2<i32>(1);
  let back_px = clamp(pixel - vec2<i32>(Bv_dir * blur_px), vec2<i32>(0), max_px);
  let hist = min(textureLoad(dataTextureC, back_px, 0).rgb, vec3<f32>(HDR_CAP));
  let persistence = 0.90 - bass * 0.05;
  let temporal = hist * persistence * (0.6 + depth * 0.4);
  color = max(color, temporal);

  // Semantic alpha from field/particle energy (never constant)
  let particle_density = clamp(gResult.w, 0.0, 1.0);
  let f_intensity = clamp(field_intensity * 0.5, 0.0, 1.0);
  let alpha = clamp(f_intensity * 0.55 + particle_density * 0.85, 0.05, 1.0) * (0.45 + 0.55 * depth);

  // Feedback state written EVERY frame (HDR, clamped) — read back next frame via C
  textureStore(dataTextureA, pixel, vec4<f32>(min(color, vec3<f32>(HDR_CAP)), alpha));

  // ACES tone mapping for presentation only
  color = acesToneMap(color * (1.3 + mids * 0.3));

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(f_intensity * 0.6 + particle_density * 0.4, 0.0, 1.0), 0.0, 0.0, 0.0));
}
