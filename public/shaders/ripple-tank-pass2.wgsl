// ═══════════════════════════════════════════════════════════════════
//  Ripple Tank — Node 3: Isotropic Capillary Dispersion & Foam Gather
//  Category: simulation
//  Features: multi-pass, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: isotropic 9-tap capillary curvature & crest-steepening whitecap gather; Jacobian focal caustics & tank optics (Node 4)
//  A packing: raw (height, velocity, foam energy, oscillator phase)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let state = stateAt(pixel, dims);
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims);
  let right = stateAt(pixel + vec2<i32>(1, 0), dims);
  let top = stateAt(pixel + vec2<i32>(0, -1), dims);
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims);
  let ul = stateAt(pixel + vec2<i32>(-1, -1), dims);
  let ur = stateAt(pixel + vec2<i32>(1, -1), dims);
  let dl = stateAt(pixel + vec2<i32>(-1, 1), dims);
  let dr = stateAt(pixel + vec2<i32>(1, 1), dims);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  // Isotropic 9-tap capillary curvature matching Node 1's isotropy
  let curvature = (10.0 / 3.0) * (
    0.20 * (left.r + right.r + top.r + bottom.r) +
    0.05 * (ul.r + ur.r + dl.r + dr.r) - state.r
  );
  let velocityCurvature = left.g + right.g + top.g + bottom.g - 4.0 * state.g;
  let surfaceTension = mix(0.006, 0.035, u.zoom_params.x) * (1.0 + audio.z * 0.35);
  let velocity = clamp(state.g - curvature * surfaceTension + velocityCurvature * 0.004, -0.8, 0.8);

  let foamNeighbor = 0.20 * (left.b + right.b + top.b + bottom.b) + 0.05 * (ul.b + ur.b + dl.b + dr.b);
  let crestBreak = max(-curvature - 0.06, 0.0) * smoothstep(0.04, 0.32, state.r);
  let foam = clamp(
    mix(state.b, foamNeighbor, 0.14) + abs(curvature) * (0.065 + audio.y * 0.05) + crestBreak * 0.22,
    0.0,
    1.5
  );

  textureStore(dataTextureA, pixel, vec4<f32>(state.r, velocity, foam, state.a));
}
