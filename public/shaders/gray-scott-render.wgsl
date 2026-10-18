// ═══ GRAY-SCOTT TANK — RENDER ══════════════════════════════════════════════
//  Upgraded: 2026-10-18
//  Ideas: iso-V threads
//  A packing: raw (U, V, age, seed mask). Display ACES is writeTexture only.

#include "_prelude.wgsl"

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let hp = fract(h) * 6.0;
  let x = c * (1.0 - abs(hp - 2.0 * floor(hp / 2.0) - 1.0));
  var rgb = vec3<f32>(0.0);
  if (hp < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (hp < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (hp < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (hp < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (hp < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let U = clamp(st.r, 0.0, 1.0);
  let V = clamp(st.g, 0.0, 1.0);
  let hue = 0.62 + V * 0.22 + st.b * 0.08 + plasmaBuffer[0].z * 0.05;
  var col = hsv2rgb(hue, mix(0.45, 0.95, V), mix(0.08, 1.05, V * 1.2 + (1.0 - U) * 0.25));
  col = mix(src.rgb * 0.12, col, 0.9);
  col += vec3<f32>(0.2, 0.55, 1.0) * plasmaBuffer[0].y * V * V * 0.2;
  // Idea: iso-V threads — hairlines where concentration crosses two fixed levels.
  let thread = exp(-abs(V - 0.36) * 48.0) + exp(-abs(V - 0.7) * 64.0);
  col += vec3<f32>(0.72, 0.9, 1.0) * thread * 0.42;
  let alpha = clamp(src.a * 0.2 + V * 0.72 + st.a * 0.12, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(col), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(U, V, st.b, st.a));
}
