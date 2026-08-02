// ═══════════════════════════════════════════════════════════════════
//  Moiré Interference
//  Category: interactive-mouse
//  Features: [mouse-driven, audio-reactive, upgraded-rgba]
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Upgraded: 2026-07-31 (Batch 21 - swarm)
//    - Removed dead `dir` variable; depth write alpha normalized to 0.0.
//    - Mouse emitter is eased through a critically-damped spring
//      (extraBuffer[133..136] = pos.xy/vel.xy, [137] = init flag) so the
//      second interference source glides instead of snapping; the raw
//      cursor remains the spring target and aspect correction is applied
//      to the SPRUNG position.
//    - Click ripples act as temporary THIRD wave emitters (same
//      sin(d * freq - time * 2.0) form, exp(-age * 2.0) fade ~2s).
//    - Per-emitter FFT gain: center emitter -> bin 1, mouse emitter
//      -> bin 5 (extraBuffer[5..132] = engine FFT bins; [0..4] reserved).
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Frequency, y=Distortion, z=Aberration, w=Complexity
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// Engine FFT bins live in extraBuffer[5..132] (bin i -> slot i + 5).
fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

// Critically-damped spring step toward the raw cursor position.
// State lives in extraBuffer[133..136] (pos.xy, vel.xy), init flag [137].
fn springStep(pos: vec2<f32>, vel: vec2<f32>, aim: vec2<f32>, omega: f32, dt: f32) -> vec4<f32> {
  let accel = omega * omega * (aim - pos) - 2.0 * omega * vel;
  let newVel = vel + accel * dt;
  let newPos = pos + newVel * dt;
  return vec4<f32>(newPos, newVel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let freq = mix(20.0, 200.0, u.zoom_params.x) * (1.0 + bass * 0.1 + mids * 0.05);
  let strength = u.zoom_params.y * 0.05 * (1.0 + treble * 0.1);
  let abb = u.zoom_params.z * 0.02;
  let complexity = u.zoom_params.w;

  // ── Spring-damper second emitter ─────────────────────────────────
  // The mouse emitter glides toward the raw cursor through a critically
  // damped spring so the interference field morphs fluidly. The spring
  // integrates in uncorrected uv space; aspect is applied AFTER springing.
  let rawMouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) {
    // First contact: snap the spring onto the cursor, zero velocity.
    springPos = rawMouse;
    springVel = vec2<f32>(0.0, 0.0);
  }
  let springState = springStep(springPos, springVel, rawMouse, 6.0, 0.016);
  let sprungMouse = springState.xy;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = springState.x;
    extraBuffer[134] = springState.y;
    extraBuffer[135] = springState.z;
    extraBuffer[136] = springState.w;
    extraBuffer[137] = 1.0;
  }

  // Points
  var center = vec2<f32>(0.5 * aspect, 0.5);
  var mouse = vec2<f32>(sprungMouse.x * aspect, sprungMouse.y);
  let current_uv = vec2<f32>(uv.x * aspect, uv.y);

  // Distances
  let d1 = distance(current_uv, center);
  let d2 = distance(current_uv, mouse);

  // Wave functions
  let w1 = sin(d1 * freq - time * 2.0);
  let w2 = sin(d2 * freq - time * 2.0);

  // Per-emitter audio gain: the two sources listen to different bands.
  let gain1 = 1.0 + fftBin(1u) * 0.8;  // center emitter  -> FFT bin 1
  let gain2 = 1.0 + fftBin(5u) * 0.8;  // mouse emitter   -> FFT bin 5

  // Basic Interference
  var interference = w1 * gain1 + w2 * gain2;

  // Complexity adds a third point or modulates freq
  if (complexity > 0.0) {
      let d3 = distance(current_uv, mix(center, mouse, 0.5));
      let w3 = sin(d3 * freq * 1.5 + time);
      interference += w3 * complexity;
  }

  // ── Click interference bursts ────────────────────────────────────
  // Each live ripple drops a temporary third wave emitter at its click
  // point (same sin form as the two fixed sources), fading with
  // exp(-age * 2.0) over ~2 seconds like a stone in the pond.
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleWave = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age > 0.0 && age < 2.0) {
      let ripplePos = vec2<f32>(ripple.x * aspect, ripple.y);
      let dR = distance(current_uv, ripplePos);
      let wR = sin(dR * freq - time * 2.0);
      rippleWave += wR * exp(-age * 2.0);
    }
  }
  interference += rippleWave;

  // Normalize roughly
  interference = interference * 0.5;

  // Distortion Vector
  let displacement = vec2<f32>(cos(interference * 3.14), sin(interference * 3.14)) * strength;

  // Sample with Aberration
  let r_uv = uv + displacement * (1.0 + abb * 10.0);
  let g_uv = uv + displacement;
  let b_uv = uv + displacement * (1.0 - abb * 10.0);

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Alpha: preserve input transparency, blend to opaque based on effect intensity
  let dispMag = length(displacement);
  let effectIntensity = clamp(dispMag * 10.0 + abs(interference) * 0.2, 0.0, 1.0);
  let finalAlpha = mix(baseColor.a, 1.0, effectIntensity);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
