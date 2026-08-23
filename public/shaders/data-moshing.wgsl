// Data Moshing v3 — Batch 58D raw-offset feedback upgrade
// A packs accumulated offset.xy, corruption confidence, and age; B is unwritten.

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

const PI: f32 = 3.14159265359;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> { return vec2<f32>(hash12(p), hash12(p + vec2<f32>(17.0, 31.0))); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let texel = 1.0 / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: smear strength, block size, corruption, quantization.
  let smearStrength = u.zoom_params.x;
  let blockSize = 0.01 + u.zoom_params.y * 0.05;
  let corruption = u.zoom_params.z;
  let quantize = u.zoom_params.w;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 10.0; let decay = exp(-omega * dt); let delta = springPos - rawMouse; let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let left = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let down = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let up = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let gx = right - left; let gy = down - up;
  let gxx = dot(gx, gx); let gxy = dot(gx, gy); let flowMag = sqrt(gxx + dot(gy, gy) + 0.0001);
  let flowDir = vec2<f32>(-gxy, gxx) / (flowMag + 0.001);

  // Exact C is authoritative raw state, never display color.
  let previous = textureLoad(dataTextureC, pixel, 0);
  var offset = previous.xy;
  var confidence = previous.z * 0.965;
  var age = min(previous.w + 0.01, 1.0);
  offset += flowDir * smearStrength * 0.015 * (1.0 + bass * 0.8);

  let pointerDelta = (uv - springPos) * aspectVec; let pointerDist = length(pointerDelta);
  let scrubMask = exp(-pointerDist * 10.0) * select(0.25, 1.0, u.zoom_config.w > 0.5);
  offset += springVel * scrubMask * (0.8 + smearStrength);
  confidence += scrubMask * 0.25;

  var clickCorruption = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let rippleAge = time - ripple.z;
    if (rippleAge < 0.0 || rippleAge > 1.4) { continue; }
    let deltaR = (uv - ripple.xy) * aspectVec; let dist = length(deltaR);
    let front = exp(-pow((dist - rippleAge * 0.24) * 20.0, 2.0)) * (1.0 - rippleAge / 1.4);
    offset += (hash22(floor(uv / blockSize) + ripple.xy) - 0.5) * front * corruption * 0.12;
    clickCorruption += front;
  }

  let blockId = floor(uv / blockSize);
  let blockHash = hash12(blockId + floor(time * (2.0 + treble * 5.0)));
  let corruptionEvent = step(0.62, bass * corruption + clickCorruption * 0.8) * step(0.68, blockHash);
  offset += (hash22(blockId + floor(time * 3.0)) - 0.5) * corruptionEvent * corruption * 0.15;
  confidence = clamp(confidence + corruptionEvent * 0.6 + clickCorruption * 0.35 + mids * 0.03, 0.0, 1.0);
  age = mix(age, 0.0, clamp(corruptionEvent + clickCorruption, 0.0, 1.0));
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  offset *= 0.85 + 0.14 * depth;
  offset = clamp(offset, vec2<f32>(-0.4), vec2<f32>(0.4));
  textureStore(dataTextureA, pixel, vec4<f32>(offset, confidence, age));

  let distortedUv = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  var sample = textureSampleLevel(readTexture, u_sampler, distortedUv, 0.0);
  let cellUv = fract(distortedUv / blockSize) - vec2<f32>(0.5);
  let edge = smoothstep(0.34, 0.49, max(abs(cellUv.x), abs(cellUv.y)));
  let ring = sin(cellUv.x * PI * 8.0) * sin(cellUv.y * PI * 8.0);
  var hdr = sample.rgb + ring * corruption * edge * 0.04;
  let chromaOffset = vec2<f32>(blockSize * 0.5, 0.0);
  hdr.r = textureSampleLevel(readTexture, u_sampler, clamp(distortedUv + chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  hdr.b = textureSampleLevel(readTexture, u_sampler, clamp(distortedUv - chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  if (quantize > 0.0) { let levels = 18.0 - quantize * 16.0; hdr = floor(hdr * levels) / levels; }
  hdr += vec3<f32>(0.03, 0.015, 0.05) * treble * hash12(vec2<f32>(uv.x * 100.0, floor(uv.y * 8.0 + time)));
  let effectEnergy = clamp(confidence * (0.45 + edge * 0.35) + length(offset) * 1.8 + clickCorruption * 0.3, 0.0, 1.0);
  let alpha = clamp(sample.a + (1.0 - sample.a) * effectEnergy, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
