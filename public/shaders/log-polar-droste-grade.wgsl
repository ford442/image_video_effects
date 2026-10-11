// ═══ LOG-POLAR DROSTE — GRADE ═════════════════════════════════════════════
//  Pass 2 of 2. Ideas: see log-polar-droste-remap.wgsl (Idea 2 integer
//  branches, Idea 3 recursion grading live here).
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-05
//  Input: dataTextureC = remap's A this frame: (linear rgb, ring level / 6).
//  A packing: ACES display RGBA (alpha = recursion visibility).
// ══════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let st = textureLoad(dataTextureC, pixel, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Same aspect-correct, mouse-following centre as remap.
  let aspectV = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let cz = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0 * aspectV;
  let z = (uv - vec2<f32>(0.5)) * 2.0 * aspectV - cz;

  // Idea 2: integer branch count -> the angular shading wraps cleanly at
  // atan2's cut (HEAD used a fractional count and tore there).
  let branches = round(mix(2.0, 8.0, u.zoom_params.w));
  let vortex = sin(atan2(z.y, z.x) * branches + u.config.x) * 0.04;
  var col = st.rgb * (1.0 + vortex + plasmaBuffer[0].z * 0.08);

  // Idea 3: recursion grading — each nested generation is a little dimmer
  // and cooler, like light lost down a hall of picture frames.
  let level = st.a * 6.0;
  let tint = max(vec3<f32>(1.0 - 0.07 * level, 1.0 - 0.035 * level, 1.0 + 0.04 * level), vec3<f32>(0.0));
  col = col * tint * exp(-0.1 * level);

  col = pow(clamp(col, vec3<f32>(0.0), vec3<f32>(1.5)), vec3<f32>(0.92));
  let display = acesToneMap(col);
  // Semantic alpha: outer frame opaque, deeper recursion more transparent.
  let alpha = clamp(1.0 - st.a * 0.5, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(display, alpha));
}
