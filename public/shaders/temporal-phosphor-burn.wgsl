// ═══════════════════════════════════════════════════════════════════
//  Temporal Phosphor Burn
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring,
//            upgraded-rgba, scanline-bloom, halation-glow,
//            fbm-phosphor-mask, per-channel-decay
//  Complexity: Medium
//  Upgraded: 2026-06-28
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//
//  Per-channel CRT phosphor persistence with added scanline bloom,
//  halation glow around bright edges, and an FBM-driven phosphor
//  mask that varies the CRT cell texture across the screen.  Each
//  channel decays at a different rate so bright pixels leave long,
//  colour-tinted trails.
//
//  zoom_params layout:
//    x = R decay rate (0→0.85, 1→0.99, default 0.50 → 0.92)
//    y = G decay rate (0→0.85, 1→0.99, default 0.79 → 0.96)
//    z = B decay rate (0→0.85, 1→0.99, default 0.93 → 0.98)
//    w = luminance floor / phosphor mask strength
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=R-decay, y=G-decay, z=B-decay, w=maskStr
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const PI: f32 = 3.14159265358979323846;

// ── Hash & Noise ─────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Scanline bloom ───────────────────────────────────────────────
fn scanlineBloom(uv: vec2<f32>, luma: f32, strength: f32) -> f32 {
  let scan = sin(uv.y * u.config.z * PI);
  let lineGlow = pow(abs(scan), 0.5);
  return 1.0 + luma * strength * lineGlow;
}

// ── Halation glow (simple neighbour luma blur) ───────────────────
fn halationGlow(uv: vec2<f32>, tex: texture_2d<f32>, samp: sampler, radius: f32) -> f32 {
  let off = radius / vec2<f32>(u.config.z, u.config.w);
  var glow = 0.0;
  glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv + vec2<f32>(off.x, 0.0), 0.0).rgb);
  glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv - vec2<f32>(off.x, 0.0), 0.0).rgb);
  glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv + vec2<f32>(0.0, off.y), 0.0).rgb);
  glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv - vec2<f32>(0.0, off.y), 0.0).rgb);
  return glow * 0.25;
}

// ── FBM-driven phosphor mask ─────────────────────────────────────
fn phosphorMask(uv: vec2<f32>, time: f32, strength: f32) -> vec3<f32> {
  let n = fbm(uv * 120.0 + time * 0.05, 2);
  let r = 0.7 + 0.3 * sin(n * 6.28);
  let g = 0.7 + 0.3 * sin(n * 6.28 + 2.09);
  let b = 0.7 + 0.3 * sin(n * 6.28 + 4.18);
  return mix(vec3<f32>(1.0), vec3<f32>(r, g, b), strength);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);

  // Clamp params
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));

  // Per-channel CRT decay rates — bass extends phosphor persistence
  let decayR = clamp(0.85 + zp.x * 0.14 + bass * 0.04, 0.0, 0.999);
  let decayG = clamp(0.85 + zp.y * 0.14 + bass * 0.02, 0.0, 0.999);
  let decayB = clamp(0.85 + zp.z * 0.14, 0.0, 0.999);
  let maskStrength = zp.w * 0.5;
  let lumFloor = zp.w * 0.10 + mids * 0.02;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let historyHead = u32(extraBuffer[4]);

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var beam = rawMouse; var beamVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { beam = vec2<f32>(extraBuffer[133], extraBuffer[134]); beamVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { beam = rawMouse; beamVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 12.0; let springDecay = exp(-omega * dt); let springDelta = beam - rawMouse; let springTemp = (beamVel + omega * springDelta) * dt;
  beamVel = (beamVel - omega * springTemp) * springDecay; beam = rawMouse + (springDelta + springTemp) * springDecay;
  if (hasSpring && global_id.x == 0u && global_id.y == 0u) { extraBuffer[133] = beam.x; extraBuffer[134] = beam.y; extraBuffer[135] = beamVel.x; extraBuffer[136] = beamVel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }

  // Immediate authoritative display history plus seven older ring frames.
  let historyDims = vec2<i32>(textureDimensions(dataTextureC));
  let immediate = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), historyDims - vec2<i32>(1)), 0);
  var burned = max(current.rgb, vec3<f32>(immediate.r * decayR, immediate.g * decayG, immediate.b * decayB));
  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist  = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let f = f32(age);
    let decayed = vec3<f32>(
      hist.r * pow(decayR, f),
      hist.g * pow(decayG, f),
      hist.b * pow(decayB, f),
    );
    burned = max(burned, decayed);
  }

  burned = max(burned, vec3<f32>(lumFloor));

  let beamDist = length((uv - beam) * aspectVec);
  let beamBurn = exp(-beamDist * beamDist * 120.0) * (0.2 + 0.8 * u.zoom_config.w) * (1.0 + treble * 0.6);
  var clickBurn = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 3.2) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    let core = exp(-dist * dist * 95.0) * exp(-age * 0.8);
    let ring = exp(-pow((dist - age * 0.15) * 30.0, 2.0)) * (1.0 - age / 3.2);
    clickBurn += core + ring * 0.45;
  }
  burned += vec3<f32>(1.0, 0.45 + mids * 0.2, 0.12 + treble * 0.2) * (beamBurn + clickBurn);

  // Halation glow around bright edges
  let curLuma = rgbToLuma(current.rgb);
  let glow = halationGlow(uv, readTexture, u_sampler, 3.0);
  let halation = smoothstep(0.4, 0.9, glow) * 0.35 * (1.0 + mids * 0.3);
  burned = burned + vec3<f32>(halation * 0.9, halation * 0.5, halation * 0.3);

  // Scanline bloom modulates brightness by scanlines
  let bloom = scanlineBloom(uv, curLuma, 0.25 + zp.w * 0.35);
  burned = burned * bloom;

  // FBM phosphor mask tints the CRT cells
  let mask = phosphorMask(uv, time, maskStrength);
  burned = burned * mask;

  // Alpha: luminance of burn excess above current, boosted by bass
  let burnLuma = dot(max(burned - current.rgb, vec3<f32>(0.0)), vec3<f32>(0.299, 0.587, 0.114));
  let burnEnergy = clamp(burnLuma * 2.0 + beamBurn + clickBurn + immediate.a * 0.25, 0.0, 1.0);
  let alpha = clamp(current.a + (1.0 - current.a) * burnEnergy, 0.0, 1.0);
  let finalOut = vec4<f32>(acesToneMap(max(burned, vec3<f32>(0.0))), alpha);
  let depth = textureLoad(readDepthTexture, coord, 0).r;

  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
