// ═══ GRAY-SCOTT TANK — STEP (Jacobi / Gray–Scott) ══════════════════════════
//  A/C packing: .r = U, .g = V, .b = age, .a = seed-mask
//  zoom_params: .x feed, .y kill, .z diffusion, .w seed strength

#include "_prelude.wgsl"

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let uv = (vec2<f32>(pixel) + 0.5) / res;

  // Classic Gray–Scott ranges (spots / stripes), sliders 0–1.
  let F = mix(0.022, 0.058, u.zoom_params.x) + bass * 0.004;
  let K = mix(0.051, 0.065, u.zoom_params.y) + (mouse.x - 0.5) * 0.004 + treble * 0.002;
  let Du = mix(0.12, 0.22, u.zoom_params.z) * (1.0 + mids * 0.12);
  let Dv = Du * 0.5;
  let dt = 0.85;

  var st = load(pixel, resI);
  if (time < 0.08 && st.r + st.g < 0.05) {
    st = vec4<f32>(1.0, 0.0, 0.0, 0.0);
  }

  let n = load(pixel + vec2<i32>(0, 1), resI);
  let s = load(pixel + vec2<i32>(0, -1), resI);
  let e = load(pixel + vec2<i32>(1, 0), resI);
  let w = load(pixel + vec2<i32>(-1, 0), resI);
  let lapU = (n.r + s.r + e.r + w.r) * 0.25 - st.r;
  let lapV = (n.g + s.g + e.g + w.g) * 0.25 - st.g;
  let uvv = st.r * st.g * st.g;
  var U = st.r + (Du * lapU - uvv + F * (1.0 - st.r)) * dt;
  var V = st.g + (Dv * lapV + uvv - (F + K) * st.g) * dt;
  U = clamp(U, 0.0, 1.0);
  V = clamp(V, 0.0, 1.0);
  let age = clamp(st.b + V * 0.01, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(U, V, age, st.a));
}
