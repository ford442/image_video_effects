// ═══ GRAY-SCOTT TANK — INJECT ══════════════════════════════════════════════
//  Upgraded: 2026-10-18
//  Ideas: paint comet behind the pointer
//  A packing: raw (U, V, age, seed mask)
//  Hold paints V; clicks seed spots; seed-mask in .a

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
  let held = u.zoom_config.w > 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let aspect = res.x / res.y;
  let seed = mix(0.2, 1.0, u.zoom_params.w);
  var st = textureLoad(dataTextureC, pixel, 0);
  var U = st.r;
  var V = st.g;
  var mask = st.a;

  let md = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let hover = smoothstep(0.07, 0.0, md);
  V = clamp(V + hover * 0.002 * (1.0 + mids), 0.0, 1.0);
  // Idea: paint comet — the held brush stretches behind the pointer.
  var brushVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) { brushVel = vec2<f32>(0.0); }
  let brushSpeed = length(brushVel);
  let brushAxis = brushVel / max(brushSpeed, 0.0001);
  let rel = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let along = dot(rel, brushAxis);
  let across = length(rel - brushAxis * along);
  let stretch = clamp(brushSpeed * 28.0, 0.0, 1.0);
  let disk = smoothstep(0.045, 0.0, md);
  let comet = smoothstep(0.018, 0.0, across) * smoothstep(0.01, -0.09, along);
  let brush = mix(disk, max(disk, comet), stretch);
  if (held && brush > 0.001) {
    let w = brush * seed;
    V = clamp(V + w * 0.55, 0.0, 1.0);
    U = clamp(U - w * 0.25, 0.0, 1.0);
    mask = max(mask, w);
  }
  if (gid.x == 0u && gid.y == 0u && arrayLength(&extraBuffer) > 137u) {
    let prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let primed = extraBuffer[137] > 0.5;
    let delta = select(vec2<f32>(0.0), mouse - prevMouse, primed);
    extraBuffer[133] = mouse.x;
    extraBuffer[134] = mouse.y;
    extraBuffer[135] = delta.x;
    extraBuffer[136] = delta.y;
    extraBuffer[137] = 1.0;
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 0.55) {
      let d = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let punch = smoothstep(0.045 + treble * 0.015, 0.0, d) * seed * (1.0 - age / 0.55) * (1.0 + bass * 0.25);
      V = clamp(V + punch * 0.8, 0.0, 1.0);
      U = clamp(U * (1.0 - punch * 0.4), 0.0, 1.0);
    }
  }

  // Sparse spontaneous seeds so the tank never dies. Slow cell pulses, not a floor(time) teleport.
  let cellId = floor(uv * 36.0);
  let cellHash = hash21(cellId);
  let pulse = fract(time * 0.11 + cellHash);
  let spark = smoothstep(0.0, 0.03, pulse) * smoothstep(0.1, 0.04, pulse);
  if (cellHash > 0.992) {
    V = clamp(V + spark * 0.35 * seed, 0.0, 1.0);
  }

  textureStore(dataTextureA, pixel, vec4<f32>(clamp(U, 0.0, 1.0), clamp(V, 0.0, 1.0), st.b, clamp(mask * 0.96, 0.0, 1.0)));
}
