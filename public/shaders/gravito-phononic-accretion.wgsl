// ═══════════════════════════════════════════════════════════════════
//  Gravito-Phononic Accretion v4 — Optimized
//  Category: generative
//  Features: SPH-density, orbital-velocity, shock-detection, blackbody,
//            audio-driven, mouse-rogue-body, ripple-perturbation
//  Upgrades: 7-tap-hex-density-kernel, fast-exp, branchless-mouse,
//            reduced-gradient-samples, named-consts, pm-alpha,
//            honest-uv-lensing (p2), diffusion-persistence (p3),
//            treble-relativistic-jet (extraBuffer[133..134])
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

// ── 7-tap hex bokeh kernel (replaces 16-tap 4x4 SPH loop) ────────
const HEX_TAPS = array<vec2<f32>, 7>(
  vec2<f32>( 0.0,  0.0),
  vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
  vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
  vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);

// ── Physics & Render Constants ───────────────────────────────────
const G1_ORBIT = vec2<f32>(0.35, 0.42);
const G2_ORBIT = vec2<f32>(0.68, 0.58);
const SOFTEN_1 = 0.06;
const SOFTEN_2 = 0.06;
const SOFTEN_3 = 0.04;
const VEL_AMP1 = 0.025;
const VEL_AMP2 = 0.020;
const VEL_AMP3 = 0.040;
const FLOW_AMP = 8.0;
const RIPPLE_DECAY = 8.0;
const RIPPLE_FREQ  = 10.0;
const RIPPLE_AGE   = 3.0;
const STAND_FREQ_X = 20.0;
const STAND_FREQ_Y = 16.0;
const STAND_AMP    = 0.12;
const TONE_GAIN    = 0.8;

// ── Lensing constants (p2 = Lensing Strength) ────────────────────
// Einstein-ring style uv deflection: duv ~ p2 * mass / dist^2, clamped
// so the sampling coordinate can never fold back across an accretor.
const LENS_AMP   = 0.012;  // deflection scale per unit p2
const LENS_CLAMP = 0.08;   // max |duv| per accretor (uv units)

// ── Relativistic jet constants (treble transient driven) ─────────
// Envelope decays ~e^-1 over 0.5 s (~30 frames @60fps: 0.93^30 ~ 0.11).
const JET_DECAY  = 0.93;    // per-frame envelope decay (~0.5 s fade)
const JET_GAIN   = 4.0;     // transient delta -> envelope kick
const JET_WIDTH  = 220.0;   // beam thinness (higher = thinner)
const JET_LENGTH = 0.45;    // vertical reach from the primary (uv units)
const JET_BRIGHT = 1.8;     // beam luminance
const JET_CORE_GAP = 0.03;  // dark gap so the beam emerges from the disk
const JET_TEMP   = 0.35;    // small heat bump along the beam

fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbody(t: f32) -> vec3<f32> {
  let kt = clamp(t, 0.0, 1.0);
  let g = mix(0.2, 1.0, smoothstep(0.15, 0.6, kt));
  let b = mix(0.0, 1.0, smoothstep(0.3, 0.9, kt));
  return vec3<f32>(kt, g, b);
}

// Per-accretor lensing offset: bend the sample position toward the
// mass by p2 * mass / dist^2, magnitude-clamped (branchless).
fn lensOffset(rel: vec2<f32>, dist: f32, mass: f32, gain: f32) -> vec2<f32> {
  let pull = clamp(gain * mass / (dist * dist), 0.0, LENS_CLAMP);
  return rel * pull;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.4;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x; // Accretion Speed   -> mass + flow gain
  let p2 = u.zoom_params.y; // Lensing Strength  -> real uv deflection
  let p3 = u.zoom_params.z; // Material Diffusion -> kernel + persistence
  let p4 = u.zoom_params.w; // Mouse Gravity Power

  // ── Treble relativistic jet envelope (persistent state) ────────
  // extraBuffer[133] = jet envelope, [134] = previous treble level.
  // Single-writer (thread 0,0) update; all threads read this frame's
  // values. Transient = positive treble delta, then exponential fade.
  let prevJet = extraBuffer[133];
  let prevTreble = extraBuffer[134];
  let trebleTransient = max(treble - prevTreble, 0.0) * JET_GAIN;
  let jetEnv = clamp(max(prevJet * JET_DECAY, trebleTransient), 0.0, 1.0);
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = jetEnv;
    extraBuffer[134] = treble;
  }

  // Orbital centers with precession
  let precess = mids * 0.8;
  let g1 = vec2<f32>(
    G1_ORBIT.x + sin(time * 0.3 + precess) * 0.12,
    G1_ORBIT.y + cos(time * 0.25) * 0.09
  );
  let g2 = vec2<f32>(
    G2_ORBIT.x + cos(time * 0.35 - precess) * 0.1,
    G2_ORBIT.y + sin(time * 0.3 + precess) * 0.08
  );

  // Masses (audio + params)
  let mass1 = 0.9 + bass * 1.4 + p1 * 0.8;
  let mass2 = 0.8 + mids * 1.0 + p1 * 0.6;
  let mass3 = (0.7 + treble * 0.6) * mouseDown * (1.0 + p4 * 2.0);

  let d1 = length(uv - g1) + SOFTEN_1;
  let d2 = length(uv - g2) + SOFTEN_2;
  let d3 = length(uv - mouse) + SOFTEN_3;

  // Orbital velocity field (branchless — mouse mass zeros out when released)
  let v1 = vec2<f32>(-(uv.y - g1.y), uv.x - g1.x) * (mass1 / (d1 * d1)) * VEL_AMP1;
  let v2 = vec2<f32>(-(uv.y - g2.y), uv.x - g2.x) * (mass2 / (d2 * d2)) * VEL_AMP2;
  let v3 = vec2<f32>(-(uv.y - mouse.y), uv.x - mouse.x) * (mass3 / (d3 * d3)) * VEL_AMP3;
  let vel = v1 + v2 + v3;

  // ── Honest gravitational lensing (p2) ──────────────────────────
  // Bend the density-sampling coordinate toward each accretor BEFORE
  // any dataTextureC reads, so mass visibly warps the advected field.
  // mass3 is already branchlessly zeroed when the mouse is released.
  let lensGain = p2 * LENS_AMP;
  let duvLens = lensOffset(g1 - uv, d1, mass1, lensGain)
              + lensOffset(g2 - uv, d2, mass2, lensGain)
              + lensOffset(mouse - uv, d3, mass3, lensGain);
  let uvLens = clamp(uv + duvLens, vec2<f32>(0.0), vec2<f32>(1.0));

  // ── Density: 7-tap hex kernel replaces 16-sample 4x4 SPH loop ──
  let h_uv = (0.045 + p3 * 0.04) * 1.5;
  let center = textureSampleLevel(dataTextureC, u_sampler, uvLens, 0.0).r;
  var density = center;
  var gradX = 0.0;
  var gradY = 0.0;
  for (var i = 1; i < 7; i = i + 1) {
    let off = HEX_TAPS[i] * h_uv;
    let sp = clamp(uvLens + off, vec2<f32>(0.0), vec2<f32>(1.0));
    let samp = textureSampleLevel(dataTextureC, u_sampler, sp, 0.0).r;
    density += samp * 0.5;
    gradX   += samp * off.x;
    gradY   += samp * off.y;
  }
  density *= 0.25;
  let gradD = length(vec2<f32>(gradX, gradY)) * res.x * 0.5;

  // Flow advection (single sample, lensed origin)
  let flowUV = clamp(uvLens - vel * FLOW_AMP * (0.6 + p1), vec2<f32>(0.0), vec2<f32>(1.0));
  let flowed = textureSampleLevel(dataTextureC, u_sampler, flowUV, 0.0).r;

  // Standing acoustic waves
  let standing = sin(uv.x * STAND_FREQ_X + time * 3.0)
               * cos(uv.y * STAND_FREQ_Y - time * 2.5)
               * treble * STAND_AMP;

  // Ripple perturbations (fast_exp, same visual decay)
  var ripplePert = 0.0;
  let rCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rd = length(uv - rp.xy);
    let rt = time - rp.z;
    ripplePert += fast_exp(-rd * RIPPLE_DECAY)
                * sin(rt * RIPPLE_FREQ)
                * 0.03
                * smoothstep(RIPPLE_AGE, 0.0, rt);
  }

  // ── Diffusion-controlled persistence (p3) ──────────────────────
  // Material Diffusion now also sets advected-trail longevity:
  // high p3 = wide kernel AND long-lived trails (0.99 feedback),
  // low p3 = tight kernel AND fast-fading trails (0.90 feedback).
  let persist = mix(0.90, 0.99, p3);
  let advected = flowed * persist + density * (1.0 - persist) * 0.5;
  density = mix(advected, density, 0.3) + standing + ripplePert;

  // Shock detection from hex-kernel gradient + velocity magnitude
  let shock = smoothstep(0.3, 1.2, gradD + length(vel) * 3.0);

  // ── Relativistic jet shape (perpendicular to orbital plane) ────
  // Thin two-sided vertical beam launched from the primary accretor,
  // gated by the treble-transient envelope. Aspect-corrected width so
  // the beam stays thin at any resolution; dark gap at the disk core.
  let aspect = res.x / res.y;
  let beamDX = abs(uv.x - g1.x) * aspect;
  let beamDY = uv.y - g1.y;
  let beamCore = fast_exp(-beamDX * beamDX * JET_WIDTH);
  let beamTip = smoothstep(JET_LENGTH, 0.0, abs(beamDY));
  let beamGap = smoothstep(JET_CORE_GAP, JET_CORE_GAP * 2.5, abs(beamDY));
  let jet = beamCore * beamTip * beamGap * jetEnv;

  // Temperature field (+ jet heat along the beam)
  var temp = shock * 0.7
           + (mass1 / (d1 * d1 * 20.0 + 1.0)) * 0.4
           + (mass2 / (d2 * d2 * 20.0 + 1.0)) * 0.3
           + jet * JET_TEMP;
  temp = clamp(temp, 0.0, 1.0);

  // State writeback for slot chaining (SIM STATE — no clamping added)
  textureStore(dataTextureA, gid.xy, vec4<f32>(density, temp, shock, jetEnv));

  // Blackbody render (+ beam glow folded in before the tonemap)
  let bb = blackbody(temp) * (1.0 + shock * 2.0);
  let scatter = smoothstep(0.02, 0.25, density) * temp * 0.6;
  var col = bb * (0.5 + density * 1.2) + vec3<f32>(0.3, 0.5, 1.0) * scatter;
  col += vec3<f32>(0.55, 0.7, 1.0) * jet * JET_BRIGHT;
  let bloom = shock * vec3<f32>(1.0, 0.9, 0.7) * 1.5;
  let tone = acesToneMap((col + bloom) * TONE_GAIN);

  let bgEmpty = smoothstep(0.15, 0.0, density);
  let alpha = clamp(density * 1.1 * temp * (1.0 - bgEmpty * 0.8)
                  + shock * 0.5 + jet * 0.6, 0.0, 1.0);

  // Premultiplied alpha for compositing (tone * alpha — no post-tonemap)
  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * temp * 0.7, 0.0, 0.0, 0.0));
}
