// ═══════════════════════════════════════════════════════════════
//  Digital Glitch Pass 1 — Batch 60
//  Glitch field generation: spring hotspot, capped ripples, held
//  intensify, bitwise seeds, exact C error mask, audio bands.
//  Outputs: dataTextureA (displacedUV.xy, intensity, blockSeed)
// ═══════════════════════════════════════════════════════════════

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

fn hash21(p: vec2<f32>) -> f32 {
  var n = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(n) * 43758.5453123);
}

fn hash33(p: vec3<f32>) -> f32 {
  var n = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(n) * 43758.5453123);
}

fn floatToByte(v: f32) -> u32 {
  return u32(clamp(v, 0.0, 1.0) * 255.0);
}

fn byteToFloat(b: u32) -> f32 {
  return f32(b & 0xFFu) / 255.0;
}

fn bitRotateRight(b: u32, n: u32) -> u32 {
  let shift = n % 8u;
  return ((b >> shift) | (b << (8u - shift))) & 0xFFu;
}

fn xorCorrupt(b: u32, mask: u32) -> u32 {
  return (b ^ mask) & 0xFFu;
}

fn bitFlip(b: u32, pos: u32) -> u32 {
  return b ^ (1u << (pos % 8u));
}

fn randomBitFlip(b: u32, seed: f32, probability: f32) -> u32 {
  let bitPos = u32(seed * 1000.0) % 8u;
  return select(b, bitFlip(b, bitPos), seed < probability);
}

fn nibbleSwap(b: u32) -> u32 {
  return ((b & 0x0Fu) << 4u) | ((b & 0xF0u) >> 4u);
}

fn bitReverse(b: u32) -> u32 {
  var result = 0u;
  result = result | ((b & 0x01u) << 7u);
  result = result | ((b & 0x02u) << 5u);
  result = result | ((b & 0x04u) << 3u);
  result = result | ((b & 0x08u) << 1u);
  result = result | ((b & 0x10u) >> 1u);
  result = result | ((b & 0x20u) >> 3u);
  result = result | ((b & 0x40u) >> 5u);
  result = result | ((b & 0x80u) >> 7u);
  return result;
}

fn corruptByte(b: u32, corruptionType: f32, seed: f32, intensity: f32) -> u32 {
  let typeIdx = u32(corruptionType * 5.0) % 6u;
  let rotAmt = u32(seed * 8.0);
  let case0 = bitRotateRight(b, rotAmt);
  let case1 = xorCorrupt(b, u32(seed * 255.0));
  let case2 = randomBitFlip(b, seed, intensity * 0.3);
  let case3 = nibbleSwap(b);
  let case4 = bitReverse(b);
  let case5 = xorCorrupt(bitRotateRight(b, 2u), u32(seed * 128.0));
  var result = select(0u, case0, typeIdx == 0u);
  result = select(result, case1, typeIdx == 1u);
  result = select(result, case2, typeIdx == 2u);
  result = select(result, case3, typeIdx == 3u);
  result = select(result, case4, typeIdx == 4u);
  result = select(result, case5, typeIdx == 5u);
  return result & 0xFFu;
}

fn getCorruptionMask(uv: vec2<f32>, time: f32, patternType: f32, intensity: f32) -> u32 {
  let t = time * 0.5;
  let stripe = floor(uv.x * 32.0 + sin(t * 2.0) * 4.0);
  let stripeMask = u32(stripe) % 255u;
  let blockCoord = floor(uv * vec2<f32>(16.0));
  let blockSeed = hash21(blockCoord + vec2<f32>(floor(t), 0.0));
  let blockMask = u32(blockSeed * 255.0);
  let scanLine = abs(uv.y - fract(t * 0.2));
  let scanMask = select(0u, 0xAAu, scanLine < 0.02);
  let noiseMask = u32(hash21(uv * 1000.0 + t) * 255.0);
  let patternSelect = fract(patternType * 4.0 + t * 0.1);
  let s0 = step(patternSelect, 0.25);
  let s1 = step(0.25, patternSelect) * step(patternSelect, 0.5);
  let s2 = step(0.5, patternSelect) * step(patternSelect, 0.75);
  let s3 = step(0.75, patternSelect);
  var mask = select(0u, stripeMask, s0 > 0.0);
  mask = select(mask, blockMask, s1 > 0.0);
  mask = select(mask, scanMask, s2 > 0.0);
  mask = select(mask, noiseMask, s3 > 0.0);
  return select(mask, mask & 0x0Fu, intensity < 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let texelCoord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let corruptionIntensity = clamp(u.zoom_params.x * (1.0 + bass * 0.35), 0.0, 1.0);
  let bitManipulationType = u.zoom_params.y;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let mouseDist = distance(uv, smoothMouse);
  let mouseInfluence = smoothstep(0.35, 0.0, mouseDist);
  var effectiveIntensity = clamp(corruptionIntensity + mouseInfluence * 0.35, 0.0, 1.0);
  effectiveIntensity = clamp(effectiveIntensity * select(1.0, 1.4, held), 0.0, 1.0);

  let prevMask = textureLoad(dataTextureC, texelCoord, 0).b;
  var rippleBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      rippleBurst += smoothstep(0.12, 0.0, rDist) * (1.0 - age);
    }
  }
  effectiveIntensity = clamp(effectiveIntensity + rippleBurst * 0.45 + prevMask * 0.12, 0.0, 1.0);

  let blockSize = mix(8.0, 64.0, effectiveIntensity);
  let blockCoord = floor(uv * blockSize);
  let blockSeed = hash21(blockCoord + vec2<f32>(time * 0.1, 0.0));
  let maxShift = mix(0.0, 0.06, effectiveIntensity);
  let xShift = (blockSeed - 0.5) * maxShift;
  let yShift = (hash21(blockCoord + vec2<f32>(7.0, 3.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;
  var displacedUV = clamp(uv + vec2<f32>(xShift, yShift), vec2<f32>(0.0), vec2<f32>(1.0));

  let row = floor(uv.y * blockSize);
  let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
  let tear = step(0.94, scanSeed);
  displacedUV.x = displacedUV.x + tear * 0.16 * (blockSeed - 0.5) * effectiveIntensity;
  displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  var color = baseColor.rgb;

  if (effectiveIntensity > 0.01) {
    let corruptionMask = getCorruptionMask(uv, time, blockSeed, effectiveIntensity);
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
      var byteVal = floatToByte(color[channel]);
      let channelSeed = hash21(uv + vec2<f32>(f32(channel) * 100.0, time));
      let flipProb = effectiveIntensity * 0.22 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
      byteVal = randomBitFlip(byteVal, channelSeed, flipProb);
      let patternCondition = step(0.7 - effectiveIntensity * 0.4, blockSeed);
      let patternIntensity = (blockSeed - 0.7 + effectiveIntensity * 0.4) / max(0.3 + effectiveIntensity * 0.4, 0.0001);
      let typeVar = bitManipulationType + f32(channel) * 0.1;
      byteVal = select(byteVal, corruptByte(byteVal, typeVar, channelSeed, patternIntensity), patternCondition > 0.0);
      let xorCondition = step(0.5, patternIntensity) * patternCondition;
      byteVal = select(byteVal, xorCorrupt(byteVal, corruptionMask), xorCondition > 0.0);
      color[channel] = byteToFloat(byteVal);
    }
  }

  let band = min(u32(uv.x * 8.0), 7u);
  effectiveIntensity = clamp(effectiveIntensity + plasmaBuffer[band + 1u].x * 0.07, 0.0, 1.0);
  color = mix(baseColor.rgb, color, 0.5 + mids * 0.3);

  textureStore(writeTexture, texelCoord, vec4<f32>(color, baseColor.a));
  textureStore(dataTextureA, texelCoord, vec4<f32>(displacedUV.x, displacedUV.y, effectiveIntensity, blockSeed));

  let depth = textureLoad(readDepthTexture, texelCoord, 0).r;
  textureStore(writeDepthTexture, texelCoord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
