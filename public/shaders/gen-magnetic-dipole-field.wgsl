// ═══════════════════════════════════════════════════════════════════
//  Magnetic Dipole Field Lines
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Lorentz gyro-helix + magnetic-mirror bounce with loss-cone precipitation; auroral oval curtains at field-line footpoints with click substorms
//  A packing: ACES display RGBA in A
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
  zoom_params: vec4<f32>,  // .x = Field Strength, .y = Particle Speed, .z = Line Density, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CAP: f32 = 6.0;        // hard bound for feedback history energy
const MAX_PARTICLES: i32 = 14;   // bounded primary particle iterations
const MAX_IONS: i32 = 10;        // bounded fast-ion iterations
const HALF_PI: f32 = 1.57079632679;
const PLANET_R: f32 = 0.045;     // conducting "planet" at the dipole centre (aurora footpoints)

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

// ── IDEA 1: Lorentz gyro-helix + magnetic-mirror bounce ──
// A charged particle on dipole shell L (r = L·sin²ψ, ψ from the moment axis)
// bounces harmonically between conjugate mirror points ψm and π−ψm. Its
// equatorial pitch angle sets ψm: small pitch → mirror point below the planet
// surface → the particle is in the LOSS CONE and precipitates to the footpoint
// (feeding the aurora). Superposed is the gyration: the projected helix wiggles
// perpendicular to B with gyroradius ∝ v⊥/|B| (tight near the poles) and
// cyclotron frequency ∝ |B|. Returns xy = position, z = brightness gate.
fn gyroMirrorParticle(dipole: vec2<f32>, moment: f32, time: f32, rate: f32, lineL: f32,
                      h1: f32, pitch: f32, charge: f32, side: f32, lossFrac: f32) -> vec3<f32> {
  let psiFoot = asin(sqrt(clamp(PLANET_R / lineL, 0.0, 0.999)));
  let inLossCone = pitch < lossFrac;
  let phase = h1 + time * rate;

  // Trapped: harmonic bounce between conjugate mirror points
  let psiMirror = mix(psiFoot + 0.12, HALF_PI - 0.1, clamp((pitch - lossFrac) / max(1.0 - lossFrac, 0.001), 0.0, 1.0));
  let psiTrapped = HALF_PI + (HALF_PI - psiMirror) * sin(TAU * phase);

  // Precipitating: slide from the equator down to a footpoint, then respawn
  let fr = fract(phase * 0.7);
  let hemi = select(-1.0, 1.0, fract(h1 * 7.31) > 0.5);
  let psiPrecip = HALF_PI - hemi * (HALF_PI - psiFoot) * fr * fr;
  let gatePrecip = smoothstep(0.0, 0.1, fr) * (1.0 - smoothstep(0.88, 1.0, fr));

  let psi = select(psiTrapped, psiPrecip, inLossCone);
  let gate = select(1.0, gatePrecip, inLossCone);
  let sp = sin(psi);
  let rr = lineL * sp * sp;
  let guide = dipole + vec2<f32>(side * sp, cos(psi)) * rr;

  let Bp = dipoleB(guide - dipole, moment);
  let Bl = length(Bp);
  let perpB = vec2<f32>(-Bp.y, Bp.x) / max(Bl, 0.0001);
  let gyroR = clamp(0.018 / sqrt(1.0 + Bl * 0.04), 0.0015, 0.018) * (0.4 + pitch);
  let omega = clamp(4.0 + log(1.0 + Bl) * 4.0, 4.0, 36.0) * charge;
  let pos = guide + perpB * gyroR * sin(omega * time + h1 * TAU);
  return vec3<f32>(pos, gate);
}

// ── IDEA 2: auroral oval at the field-line footpoints ──
// Pixel's own shell parameter L = r / sin²ψ. The oval is the ring of pixels just
// above the planet whose shell matches the auroral shell L_aur (footpoint
// latitude sin²ψ = R/L_aur). Curtains: 557.7 nm green base, 630 nm red tops,
// ray structure along the oval from coherent noise.
fn auroralOval(r: vec2<f32>, time: f32, lAur: f32, flux: f32) -> vec4<f32> {
  let rp = length(r);
  let sp = clamp(abs(r.x) / max(rp, 0.0001), 0.0, 1.0);
  let lPix = rp / max(sp * sp, 0.0005);
  let dl = (lPix - lAur) / (0.28 * lAur);
  let shell = exp(-dl * dl);
  let h = rp - PLANET_R;
  let height = smoothstep(-0.002, 0.004, h) * exp(-max(h, 0.0) / 0.014);
  let psi = atan2(abs(r.x), r.y);
  let rays = 0.45 + 0.55 * valueNoise(vec2<f32>(psi * 38.0 + time * 1.3, time * 0.6 + h * 60.0));
  let redTop = smoothstep(0.004, 0.02, h);
  let curtainCol = mix(vec3<f32>(0.25, 1.0, 0.45), vec3<f32>(1.0, 0.18, 0.28), redTop);
  let e = shell * height * rays * flux;
  return vec4<f32>(curtainCol * e, e);
}

// Evaluate field and particles at a given UV, returning color + particle density in alpha.
// withParticles=false skips the particle loops (cheap variant for the ghost dipole).
fn sampleField(uv: vec2<f32>, time: f32, p1: f32, p2: f32, p3: f32, p4: f32, dipole: vec2<f32>, bass: f32, ionDrive: f32, lossFrac: f32, withParticles: bool) -> vec4<f32> {
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
    // ── FAST MOTION: analytic closed-form guiding-centre motion along dipole
    // shells (r = L·sin²ψ) — pure function of time, frame-rate independent —
    // now with gyro-helix + mirror bounce (IDEA 1).
    let speed_scale = (0.4 + p2 * 3.5) * (1.0 + bass * 0.4);
    let num_particles = min(i32(4.0 + p1 * 10.0), MAX_PARTICLES);
    for (var i = 0; i < num_particles; i++) {
      let seed = f32(i) * 157.0;
      let h1 = hashf(seed);
      let h2 = hashf(seed + 1.0);
      let h3 = hashf(seed + 2.0);
      let h4 = hashf(seed + 3.0);
      let line_L = 0.06 + h2 * 0.42;                       // shell parameter
      let side = select(-1.0, 1.0, h3 > 0.5);
      let charge = select(-1.0, 1.0, h4 > 0.35);           // ions vs electrons gyrate oppositely
      let q = gyroMirrorParticle(dipole, dipole_moment, time, (0.08 + h3 * 0.22) * speed_scale * 0.5,
                                 line_L, h1, fract(h4 * 3.7 + h2), charge, side, lossFrac);
      let d = uv - q.xy;
      particle_glow += exp(-dot(d, d) * 500.0) * 0.35 * q.z;
    }

    // Secondary fast ion population (audio-excited) — tighter shells, higher speed
    let fast_count = min(i32(clamp(bass * 5.0 + ionDrive * 6.0, 0.0, 10.0)), MAX_IONS);
    for (var i = 0; i < fast_count; i++) {
      let seed = f32(i) * 293.0;
      let h1 = hashf(seed + 7.0);
      let h2 = hashf(seed + 11.0);
      let h3 = hashf(seed + 13.0);
      let line_L = 0.06 + h2 * 0.16;
      let side = select(-1.0, 1.0, h3 > 0.5);
      let q = gyroMirrorParticle(dipole, dipole_moment, time, (0.35 + h3 * 0.6) * speed_scale * 0.5,
                                 line_L, h1, fract(h2 * 5.3 + h3), 1.0, side, lossFrac);
      let d = uv - q.xy;
      particle_glow += exp(-dot(d, d) * 700.0) * 0.28 * (1.0 + bass * 0.5) * q.z;
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
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let minRes = min(resolution.x, resolution.y);

  // Mid-band drives the fast-ion population (replaces fake extraBuffer FFT read)
  let ionDrive = clamp(mids * 0.75, 0.0, 1.5);

  // Click ripples → geomagnetic substorms: loss cone opens, oval brightens and
  // expands equatorward, a dipolarization front sweeps out from the click.
  var substorm = 0.0;
  var front = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age >= 0.0 && age < 3.0) {
      substorm += exp(-age * 1.3);
      let ruv = (rip.xy * resolution - resolution * 0.5) / minRes;
      front = max(front, exp(-abs(length(uv - ruv) - age * 0.45) * 70.0) * exp(-age * 1.5));
    }
  }
  substorm = clamp(substorm, 0.0, 1.5);
  let lossFrac = clamp(0.12 + bass * 0.2 + substorm * 0.25, 0.0, 0.7);

  // Branchless dipole selection (mouse when pressed, slow auto-drift otherwise)
  let auto_dipole = vec2<f32>(0.0, sin(time * p2 * 0.15) * 0.1);
  let mouse_dipole = (mouse * resolution - resolution * 0.5) / minRes;  // same centred space as uv
  let dipole = select(auto_dipole, mouse_dipole, mouseDown);

  let dipole_moment = 1.0 + p1 * 2.0;
  let r = uv - dipole;
  let r_sq = dot(r, r);
  let field_intensity = dipole_moment / (r_sq + 0.02);

  // ── Single full field evaluation (was 4×: R/G/B chromatic + ghost) ──
  let gResult = sampleField(uv, time, p1, p2, p3, p4, dipole, bass, ionDrive, lossFrac, true);
  var color = gResult.rgb;

  // Ghost dipole orbiting for topological complexity — cheap variant, no particle loops
  let ghost_angle = time * p2 * 0.4 + bass * 3.0;
  let ghost_dipole = dipole + vec2<f32>(cos(ghost_angle), sin(ghost_angle)) * 0.12;
  let ghostResult = sampleField(uv, time, p1 * 0.4, p2, p3, p4 + 0.3, ghost_dipole, bass, 0.0, 0.0, false);
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
  color += vec3<f32>(0.3, 0.5, 0.8) * (bass * 0.12 + treble * 0.3) * storm * min(field_intensity * 0.1, 1.0);

  // Aurora-like background glow
  let aurora = sin(uv.x * 3.0 + time * p2 * 0.6) * exp(-abs(uv.y) * 2.0);
  color += vec3<f32>(0.1, 0.4, 0.3) * aurora * 0.05 * (1.0 + bass);

  // Subtle pulsing (time-warped, frame-rate independent)
  color *= 1.0 + sin(time * (1.2 + p2 * 2.0)) * 0.07;

  // Depth-based intensity falloff + bass modulation
  color *= 0.5 + 0.5 * depth;
  color *= 1.0 + bass * 0.4;
  color += vec3<f32>(0.5, 0.35, 1.0) * front * (0.6 + bass * 0.4);

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

  // ── Planet body + auroral oval (after feedback so trails never smear the limb) ──
  let rp = length(r);
  let planetMask = smoothstep(PLANET_R - 0.003, PLANET_R + 0.001, rp);
  let nightSide = vec3<f32>(0.015, 0.02, 0.04) * (0.6 + 0.4 * smoothstep(0.0, PLANET_R, rp));
  color = mix(nightSide, color, planetMask);
  // Stronger field (p1) = bigger magnetosphere = poleward (larger-L) oval;
  // substorms push it equatorward. Precipitating flux ∝ loss-cone fraction.
  let lAur = (0.2 + p1 * 0.14) * (1.0 - substorm * 0.18);
  let flux = (0.6 + lossFrac * 4.0 + treble * 0.4) * select(1.0, 1.35, mouseDown);
  let aurora_oval = auroralOval(r, time, lAur, flux);
  color += aurora_oval.rgb * 1.6;

  // Semantic alpha from field/particle/aurora energy (never constant)
  let particle_density = clamp(gResult.w, 0.0, 1.0);
  let f_intensity = clamp(field_intensity * 0.5, 0.0, 1.0) * planetMask;
  let alpha = clamp(f_intensity * 0.55 + particle_density * 0.85 + aurora_oval.w * 0.6 + front * 0.3, 0.05, 1.0) * (0.45 + 0.55 * depth);

  // ACES tone mapping; the same display RGBA goes to screen and to A (read back via C)
  color = acesToneMap(min(color, vec3<f32>(HDR_CAP)) * (1.3 + mids * 0.3));
  let finalColor = vec4<f32>(color, alpha);

  textureStore(writeTexture, pixel, finalColor);
  textureStore(dataTextureA, pixel, finalColor);
  let planetDepth = (1.0 - planetMask) * 0.9;
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(max(f_intensity * 0.6 + particle_density * 0.4, planetDepth), 0.0, 1.0), 0.0, 0.0, 0.0));
}
