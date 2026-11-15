// ═══════════════════════════════════════════════════════════════════
//  Ripple Tank — Node 2: Harmonic Dipper, Click & Audio Rain Sources
//  Category: simulation
//  Features: multi-pass, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: branchless sympathetic twin-dipper interference harmonic & meniscus wake; bathymetric shoaling & Jacobian floor caustics (Nodes 1 & 4)
//  A packing: raw (height, velocity, foam energy, oscillator phase)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash11(x: f32) -> f32 {
  return fract(sin(x * 127.1) * 43758.5453);
}

fn hash21(x: f32) -> vec2<f32> {
  return vec2<f32>(hash11(x), hash11(x + 73.156));
}

fn splash(distanceSquared: f32, radius: f32) -> f32 {
  let normalizedDistance = sqrt(max(distanceSquared, 0.0)) / max(radius, 0.0001);
  return smoothstep(1.0, 0.0, normalizedDistance) *
    cos(min(normalizedDistance, 1.0) * 1.5707963);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let sourceStrength = mix(0.15, 1.5, u.zoom_params.z) * (1.0 + audio.x * 0.65);

  let state = textureLoad(dataTextureC, pixel, 0);
  var height = state.r;
  var velocity = state.g;
  var foam = state.b;
  var phase = state.a;

  // ── Idea 1: branchless primary + sympathetic twin-pin Young interference dipper ──
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseRadius = 0.022 + audio.y * 0.006;
  let pinSpan = vec2<f32>(0.042, 0.0) * smoothstep(0.45, 0.95, u.zoom_params.z);
  let deltaA = (uv - u.zoom_config.yz + pinSpan * 0.5) * aspect;
  let deltaB = (uv - u.zoom_config.yz - pinSpan * 0.5) * aspect;
  let distSqA = dot(deltaA, deltaA);
  let distSqB = dot(deltaB, deltaB);
  let twinMix = smoothstep(0.45, 0.95, u.zoom_params.z) * 0.65;
  let shapeA = splash(distSqA, mouseRadius);
  let shapeB = splash(distSqB, mouseRadius * 0.92) * twinMix;
  let dipperShape = max(shapeA, shapeB);
  let activeDipper = f32(held > 0.0 && dipperShape > 0.0001);
  phase = select(phase, fract(phase + (0.055 + audio.z * 0.045)), activeDipper > 0.5);
  let drive = sin(phase * 6.283185) * sourceStrength * held * activeDipper;
  height += drive * dipperShape * 0.34;
  velocity += drive * dipperShape * 0.08;
  foam += abs(drive) * dipperShape * 0.06;

  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    let inTime = f32(age >= 0.0 && age < 0.14);
    let safeAge = clamp(age, 0.0, 0.14);
    let delta = (uv - event.xy) * aspect;
    let distanceSquared = dot(delta, delta);
    let radius = 0.026;
    let shape = splash(distanceSquared, radius) * inTime;
    let punch = (1.0 - safeAge / 0.14) * sourceStrength * 0.42;
    height -= punch * shape * 0.48;
    velocity -= punch * shape * 0.12;
    foam += punch * shape * 0.09;
  }

  let dripRate = 0.8 + audio.z * 1.55;
  for (var drop = 0; drop < 3; drop = drop + 1) {
    let clock = time * dripRate + f32(drop) * 0.37;
    let cell = floor(clock);
    let age = fract(clock) / dripRate;
    let inDrop = f32(age < 0.1);
    let safeDropAge = clamp(age, 0.0, 0.1);
    let position = hash21(cell * 7.31 + f32(drop) * 91.7) * 0.8 + vec2<f32>(0.1);
    let delta = (uv - position) * aspect;
    let distanceSquared = dot(delta, delta);
    let radius = 0.015 + audio.y * 0.004;
    let amplitude = sourceStrength * (0.1 + audio.y * 0.32 + audio.z * 0.14);
    let shape = splash(distanceSquared, radius) * (1.0 - safeDropAge / 0.1) * inDrop;
    height -= amplitude * shape;
    foam += amplitude * shape * 0.16;
  }

  textureStore(dataTextureA, pixel, vec4<f32>(
    clamp(height, -1.5, 1.5),
    clamp(velocity, -0.8, 0.8),
    clamp(foam, 0.0, 1.5),
    phase));
}
