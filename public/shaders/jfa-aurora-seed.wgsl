// ═══════════════════════════════════════════════════════════════════
//  JFA Aurora Voronoi — seed
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: reset the halving jump counter
//  A packing: raw seed (xy, dist², id)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let seedStr = mix(0.05, 0.35, u.zoom_params.w + plasmaBuffer[0].x * 0.1);

  var seed = vec2<f32>(-1.0, -1.0);
  var dist2 = 1e6;
  var sid = -1.0;

  let onMouse = length(uv - mouse) < seedStr;
  seed = select(seed, mouse, onMouse);
  dist2 = select(dist2, 0.0, onMouse);
  sid = select(sid, 0.0, onMouse);

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let hit = age > 0.0 && age < 0.6 && length(uv - rp.xy) < seedStr * 1.2;
    seed = select(seed, rp.xy, hit);
    dist2 = select(dist2, 0.0, hit);
    sid = select(sid, f32(i) / 50.0, hit);
  }

  let h = hash21(uv * 97.0 + vec2<f32>(time * 0.02));
  let spawn = seed.x < 0.0 && h < mix(0.002, 0.02, u.zoom_params.z);
  seed = select(seed, uv, spawn);
  dist2 = select(dist2, 0.0, spawn);
  sid = select(sid, h, spawn);

  textureStore(dataTextureA, pixel, vec4<f32>(seed, dist2, sid));

  // ── Idea 1: the seed pass restarts the flood's step counter ───────
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = 0.0;
  }
}
