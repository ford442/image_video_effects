// ═══════════════════════════════════════════════════════════════════
//  Wave Tank — step
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: isotropic 9-point Laplacian (§12.2D); latch previous height
//  A packing: raw wave (height, velocity, previous height, phase)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn loadH(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0).r;
}

// Isotropic 9-point. On a wave that varies only in x this equals the old
// 5-point (L + R − 2C), so Wave Speed keeps its meaning.
fn lap9(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  let c = loadH(p, hi);
  let e = loadH(p + vec2<i32>(1, 0), hi) + loadH(p + vec2<i32>(-1, 0), hi)
        + loadH(p + vec2<i32>(0, 1), hi) + loadH(p + vec2<i32>(0, -1), hi);
  let q = loadH(p + vec2<i32>(1, 1), hi) + loadH(p + vec2<i32>(-1, 1), hi)
        + loadH(p + vec2<i32>(1, -1), hi) + loadH(p + vec2<i32>(-1, -1), hi);
  return (4.0 * e + q - 20.0 * c) / 6.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let pixel = vec2<i32>(coord);
  let hi = vec2<i32>(size) - vec2<i32>(1);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));

  let waveSpeed = mix(0.1, 0.5, u.zoom_params.x);
  let damping = mix(0.98, 0.999, u.zoom_params.y);
  let boundaryReflect = mix(0.0, 0.95, u.zoom_params.w);

  let state = textureLoad(dataTextureC, pixel, 0);
  let heightIn = state.r;
  var velocity = state.g;
  let phase = state.a;

  // ── Idea 1: isotropic 9-point Laplacian (§12.2D) ──────────────────
  let laplacian = lap9(pixel, hi);
  let c2 = waveSpeed * waveSpeed;
  velocity = (velocity + c2 * laplacian) * damping;
  let height = heightIn + velocity;

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeFade = smoothstep(0.0, 0.05, edgeDist);
  let absorb = mix(1.0, edgeFade, 1.0 - boundaryReflect);
  let heightOut = clamp(height * absorb, -2.0, 2.0);
  velocity = clamp(velocity * absorb, -1.0, 1.0);

  // ── Idea 2: .b is the height before this substep, for crest foam ──
  textureStore(dataTextureA, pixel, vec4<f32>(heightOut, velocity, heightIn, phase));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(0.5 - heightOut * 0.2, 0.0, 1.0), 0.0, 0.0, 0.0));
}
