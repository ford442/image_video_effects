// ═══════════════════════════════════════════════════════════════════
//  Data Moshing v2
//  Category: retro-glitch
//  Features: temporal, audio-reactive, mouse-driven, depth-aware
//  Complexity: High
//  Upgraded: 2026-05-30
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hash22 ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let smearStrength = u.zoom_params.x;
  let blockSize = 0.01 + u.zoom_params.y * 0.05;
  let corruption = u.zoom_params.z;
  let quantize = u.zoom_params.w;

  // Structure tensor for optical flow estimation
  var gx = vec3<f32>(0.0);
  var gy = vec3<f32>(0.0);
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let cxp = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
  let cxm = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb;
  let cyp = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
  let cym = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb;
  gx = (cxp - cxm) * 0.5;
  gy = (cyp - cym) * 0.5;

  let gxx = dot(gx, gx);
  let gyy = dot(gy, gy);
  let gxy = dot(gx, gy);
  let flowMag = sqrt(gxx + gyy + 0.0001);
  let flowDir = vec2<f32>(-gxy, gxx) / (flowMag + 0.001);

  // Read previous UV offset from history
  let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var offset = prevData.xy;

  // Mouse scrub through temporal buffer
  let mouseDist = distance(uv, mouse);
  if (mouseDist < 0.15) {
    let scrub = (mouse.x - 0.5) * 0.04;
    offset = offset + vec2<f32>(scrub, 0.0);
  }

  // Motion-compensated smearing along flow
  offset = offset + flowDir * smearStrength * 0.015 * (1.0 + bass);

  // Bass triggers I-frame corruption events
  let corruptionEvent = step(0.65, bass * corruption);
  let blockId = floor(uv / blockSize);
  let blockHash = hash12(blockId + floor(time * 3.0));
  if (corruptionEvent > 0.5 && blockHash > 0.7) {
    let jump = (hash22(blockId) - 0.5) * 0.15;
    offset = offset + jump * corruption;
  }

  // Decay: depth controls compression quality (lower depth = faster heal)
  let quality = 0.85 + 0.14 * depth;
  offset = offset * quality;
  offset = clamp(offset, vec2<f32>(-0.4), vec2<f32>(0.4));

  // Sample with offset
  let distortedUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

  // MPEG macro-blocking artifact
  let macroBlock = floor(distortedUV / blockSize) * blockSize + blockSize * 0.5;
  let blockEdge = abs(fract(distortedUV / blockSize) - 0.5) * 2.0;
  let edgeStrength = smoothstep(0.8, 1.0, max(blockEdge.x, blockEdge.y));

  // DCT ringing simulation: banding near edges
  let ringUV = (distortedUV - macroBlock) / blockSize;
  let ring = sin(ringUV.x * 3.14159 * 8.0) * sin(ringUV.y * 3.14159 * 8.0);
  color = color + ring * 0.03 * corruption * edgeStrength;

  // Chroma subsampling error: offset UV channels
  let chromaOffset = vec2<f32>(blockSize * 0.5, 0.0);
  let y = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let cb = dot(textureSampleLevel(readTexture, u_sampler, clamp(distortedUV - chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(-0.1687, -0.3313, 0.5));
  let cr = dot(textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.5, -0.4187, -0.0813));
  let yuvMat = mat3x3<f32>(
    1.0,  0.0,       1.402,
    1.0, -0.344136, -0.714136,
    1.0,  1.772,     0.0
  );
  color = vec4<f32>(yuvMat * vec3<f32>(y, cb, cr), color.a);

  // VHS head switching band
  let bandY = fract(uv.y * 8.0 + time * 0.3);
  let bandNoise = hash12(vec2<f32>(uv.x * 100.0, floor(bandY * 8.0))) * 0.08;
  color = color + bandNoise * corruption;

  // Color quantization (Glitch effect)
  if (quantize > 0.0) {
    let q = 16.0 * (1.0 - quantize) + 2.0;
    color = floor(color * q) / q;
  }

  // Alpha: corruption confidence × block edge strength
  let corruptionConfidence = length(offset) * 2.5 + corruptionEvent;
  let alpha = clamp(corruptionConfidence * edgeStrength + color.a * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color.rgb, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(offset, 0.0, 0.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
