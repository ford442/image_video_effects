// ═══════════════════════════════════════════════════════════════════
//  Digital Decay — Batch 61
//  Block corruption + ghost persistence: spring hotspot, held burst,
//  capped ripples, exact C ghost load, bit-flip, ACES + semantic alpha.
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

fn hash11(p: f32) -> f32 {
  var v = fract(p * 0.1031);
  v = fract(v + dot(vec2<f32>(v, v), vec2<f32>(v, v) + 33.33));
  return fract(v * v * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
  var v = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  v = fract(v + dot(v, v.yzx + 33.33));
  return fract((v.x + v.y) * v.z);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

fn bitFlip(v: f32, seed: f32) -> f32 {
  let quantized = floor(v * 255.0);
  let bitPos = floor(hash11(seed) * 8.0);
  let flipMask = exp2(bitPos);
  return clamp(fract((quantized + flipMask) / 256.0) * (256.0 / 255.0), 0.0, 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(gid.x) >= resolution.x || f32(gid.y) >= resolution.y) { return; }
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let uv = vec2<f32>(f32(gid.x) / resolution.x, f32(gid.y) / resolution.y);
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let corruptionRate = u.zoom_params.x;
  let rawBlock = u.zoom_params.y;
  let ghostDecay = 0.7 + u.zoom_params.z * 0.28;
  let depthInfluence = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  var effectiveCorruption = clamp(corruptionRate + bass * 0.35, 0.0, 1.0);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) { smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]); }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) { springPos = mouse; springVel = vec2<f32>(0.0); }
    else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let mouseBurst = smoothstep(0.16, 0.0, length((uv - smoothMouse) * vec2<f32>(aspect, 1.0))) * select(0.0, 1.0, held);
  effectiveCorruption = clamp(effectiveCorruption + mouseBurst * 0.55, 0.0, 1.0);

  var rippleBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      rippleBurst += smoothstep(0.12, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age);
    }
  }
  effectiveCorruption = clamp(effectiveCorruption + rippleBurst * 0.45, 0.0, 1.0);

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let depthCorrupt = effectiveCorruption * (1.0 + depth * depthInfluence);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let blockPx = floor(mix(4.0, 64.0, rawBlock));
  let blockUV = vec2<i32>(i32(floor(uv.x * resolution.x / blockPx)), i32(floor(uv.y * resolution.y / blockPx)));
  let blockId = f32((blockUV.x * 73856093) ^ (blockUV.y * 19349663));
  let blockTime = floor(time * (2.0 + bass * 3.0) * hash11(blockId + 1.0));
  let blockHash = hash21(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) + blockTime);

  var glitchUV = uv;
  if (blockHash < depthCorrupt * 0.55) {
    glitchUV += (hash22(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) * 99.0 + blockTime) - 0.5) * 0.35;
  }
  if (blockHash < depthCorrupt * 0.25) {
    glitchUV += (vec2<f32>(hash21(uv * 500.0 + time * 3.0), hash21(uv * 600.0)) - 0.5) / resolution * 18.0;
  }
  glitchUV = clamp(glitchUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let aberrStr = depthCorrupt * 0.012 * select(1.0, 3.0, blockHash < depthCorrupt * 0.4);
  let aberr = (hash22(uv + time * 0.07) - 0.5) * aberrStr;
  var outCol = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, glitchUV + aberr, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, glitchUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, glitchUV - aberr, 0.0).b
  );

  if (blockHash < depthCorrupt * 0.15) {
    outCol.r = bitFlip(outCol.r, blockId + time * 7.3);
    outCol.g = bitFlip(outCol.g, blockId + time * 5.1);
    outCol.b = bitFlip(outCol.b, blockId + time * 3.7);
  }

  outCol -= sin(uv.y * resolution.y * 1.5 + time * 2.0) * 0.05 * depthCorrupt;
  outCol += (hash11(dot(uv, vec2<f32>(12.9898, 78.233)) + time) - 0.5) * 0.12 * depthCorrupt;

  let ghost = textureLoad(dataTextureC, coord, 0).rgb;
  let ghostBlend = clamp(depthCorrupt * 0.6, 0.0, 0.8);
  outCol = mix(outCol, ghost * ghostDecay, ghostBlend);
  if (corruptionRate < 0.01) { outCol = src.rgb; }

  outCol = acesToneMap(outCol * (0.95 + bass * 0.08 + mids * 0.04));
  let luma = dot(outCol, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(0.5 + luma * 0.25 + depthCorrupt * 0.25, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(outCol, alpha));
  textureStore(writeTexture, coord, vec4<f32>(outCol, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
