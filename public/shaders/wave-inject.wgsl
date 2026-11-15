// ═══════════════════════════════════════════════════════════════════
//  Wave Tank — inject
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: (sources unchanged; crest latch passes through .b)
//  A packing: raw wave (height, velocity, previous height, phase)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let pixel = vec2<i32>(coord);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let sourceStrength = mix(0.1, 1.0, u.zoom_params.z) * (1.0 + bass * 0.35);

  let state = textureLoad(dataTextureC, pixel, 0);
  var height = state.r;
  let velocity = state.g;
  let prevHeight = state.b;
  var phase = state.a;

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDistSq = dot(uv - mouse, uv - mouse);
  let mouseRadius = 0.02;
  let inMouse = mouseDistSq < mouseRadius * mouseRadius;
  let wave = sin(time * 10.0) * sourceStrength * 0.5 * (1.0 - sqrt(mouseDistSq) / mouseRadius);
  height = select(height, height + wave, inMouse);
  phase = select(phase, phase + 0.02, inMouse);

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleAge = time - ripple.z;
    let distSq = dot(uv - ripple.xy, uv - ripple.xy);
    let radius = 0.015;
    let hit = ripple.z > 0.0 && rippleAge > 0.0 && rippleAge < 0.5 && distSq < radius * radius;
    let strength = (1.0 - rippleAge / 0.5) * sourceStrength * (1.0 - sqrt(max(distSq, 0.0)) / radius);
    height = select(height, height + strength, hit);
  }

  textureStore(dataTextureB, pixel, vec4<f32>(height, velocity, prevHeight, phase));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(0.5 - height * 0.2, 0.0, 1.0), 0.0, 0.0, 0.0));
}
