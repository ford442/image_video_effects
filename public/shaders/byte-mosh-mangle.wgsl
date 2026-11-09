// ═══════════════════════════════════════════════════════════════════
//  Byte Mosh — Mangle pass (graph node 1 of 2)
//  Category: retro-glitch
//  Features: audio-reactive, multi-pass, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-09
//  Ideas: motion-vector block copy; bit-plane severity; (render) macroblock seam ringing
//  A packing: moshed RGB (0..1) + corruption flag in .a (read by byte-mosh-render as C)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let mixOp = u.zoom_params.x;
  let shift = u32(mix(0.0, 12.0, u.zoom_params.y));
  let err = mix(0.0, 1.0, u.zoom_params.z + plasmaBuffer[0].x * 0.2);
  let block = max(1.0, mix(2.0, 32.0, u.zoom_params.w));
  let bx = floor(uv.x * block) / block;
  let by = floor(uv.y * block) / block;
  let h = hash12(vec2<f32>(bx, by) + u.config.x * 0.01);
  let corrupt = h < err;

  // Idea 1 — motion-vector block copy: a corrupted block reuses a whole block
  // from a hashed, block-quantised displacement (P-frame reuse without a keyframe).
  var srcUV = uv;
  if (corrupt) {
    let mv = floor((vec2<f32>(hash12(vec2<f32>(bx, by) * 7.3 + 1.7), hash12(vec2<f32>(by, bx) * 5.1 + 3.9)) - 0.5) * 4.0);
    srcUV = fract(uv + mv / block);
  }
  let src = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0).rgb;

  // HEAD rescue: work on an 8-bit RGB byte word, not IEEE-754 float bits.
  let b8 = vec3<u32>(round(clamp(src, vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0));
  var packed = b8.r | (b8.g << 8u) | (b8.b << 16u);
  if (corrupt) {
    let orig = packed;
    packed = packed ^ (u32(f32(pixel.x) * 13.0 + f32(pixel.y) * 7.0) & 0xFFFFFFu);
    if (shift > 0u) {
      packed = ((packed << shift) | (packed >> (24u - shift))) & 0xFFFFFFu;
    }
    let mask = u32(mix(16777215.0, 16711935.0, mixOp));
    packed = packed & mask;
    // Idea 2 — bit-plane severity: only the lowest N bits of each byte are
    // replaced; N grows with a per-block hash and Error Rate.
    let sev = hash12(vec2<f32>(by, bx) * 3.7 + floor(u.config.x * 4.0));
    let nBits = u32(clamp(1.0 + floor(sev * (2.0 + 6.0 * u.zoom_params.z)), 1.0, 8.0));
    let lowByte = (1u << nBits) - 1u;
    let lowMask = lowByte | (lowByte << 8u) | (lowByte << 16u);
    packed = (orig & ~lowMask) | (packed & lowMask);
  }
  let out = vec3<f32>(f32(packed & 255u), f32((packed >> 8u) & 255u), f32((packed >> 16u) & 255u)) / 255.0;
  textureStore(dataTextureA, pixel, vec4<f32>(out, select(0.0, 1.0, corrupt)));
}
