// ═══════════════════════════════════════════════════════════════════
//  Byte Mosh — Render pass (graph node 2 of 2)
//  Category: retro-glitch
//  Features: audio-reactive, multi-pass, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-09
//  Ideas: macroblock seam ringing; treble seam chroma slip
//  A packing: ACES display RGBA (alpha = corruption coverage); overwritten by mangle next frame
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let m = textureLoad(dataTextureC, pixel, 0);
  let mosh = m.rgb;
  let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let treble = plasmaBuffer[0].z;
  var col = mix(orig, mosh, 0.85 + treble * 0.1);

  // Idea 3 — macroblock seam ringing: where the mangle's corruption flag
  // changes between neighbours, a decaying DCT-style overshoot rings the seam.
  let maxI = resI - vec2<i32>(1);
  var ring = 0.0;
  var dirX = 0.0;
  for (var k = 1; k <= 3; k = k + 1) {
    let fl = textureLoad(dataTextureC, clamp(pixel - vec2<i32>(k, 0), vec2<i32>(0), maxI), 0).a;
    let fr = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(k, 0), vec2<i32>(0), maxI), 0).a;
    let fu = textureLoad(dataTextureC, clamp(pixel - vec2<i32>(0, k), vec2<i32>(0), maxI), 0).a;
    let fd = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, k), vec2<i32>(0), maxI), 0).a;
    let edge = abs(fl - m.a) + abs(fr - m.a) + abs(fu - m.a) + abs(fd - m.a);
    let sgn = select(-1.0, 1.0, (k & 1) == 1);
    ring += edge * sgn * exp(-f32(k) * 0.7);
    dirX += (fr - fl) * exp(-f32(k) * 0.7);
  }
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  col += vec3<f32>(ring * 0.09 * (0.4 + luma));
  // Treble seam chroma slip: red/blue sheared across the seam direction.
  let slip = dirX * treble * 0.03;
  let rS = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(i32(slip * res.x), 0), vec2<i32>(0), maxI), 0).r;
  col.r = mix(col.r, rS, min(abs(dirX), 1.0) * 0.6);

  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.2));
  let disp = aces(col * 1.25);
  let alpha = mix(0.88, 1.0, m.a);
  textureStore(writeTexture, pixel, vec4<f32>(disp, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(disp, alpha));
}
