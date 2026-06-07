// ═══════════════════════════════════════════════════════════════
//  Digital Glitch – Pass 1: Glitch Field Generation
//  Category: image
//  Features: multi-pass-1, block displacement, corruption seeds, bit masks
//  Outputs: dataTextureA (displacedUV.x, displacedUV.y, corruptionIntensity, blockSeed)
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

fn bitRotateLeft(b: u32, n: u32) -> u32 {
  let shift = n % 8u;
  return ((b << shift) | (b >> (8u - shift))) & 0xFFu;
}

fn xorCorrupt(b: u32, mask: u32) -> u32 {
  return (b ^ mask) & 0xFFu;
}

fn bitFlip(b: u32, pos: u32) -> u32 {
  return b ^ (1u << (pos % 8u));
}

fn randomBitFlip(b: u32, seed: f32, probability: f32) -> u32 {
  if (seed < probability) {
    let bitPos = u32(seed * 1000.0) % 8u;
    return bitFlip(b, bitPos);
  }
  return b;
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

fn reduceBitDepth(b: u32, bits: u32) -> u32 {
  let shift = clamp(8u - bits, 0u, 8u);
  return (b >> shift) << shift;
}

fn getCorruptionMask(uv: vec2<f32>, time: f32, patternType: f32, intensity: f32) -> u32 {
  var mask = 0u;
  let t = time * 0.5;
  let stripe = floor(uv.x * 32.0 + sin(t * 2.0) * 4.0);
  let stripeMask = u32(stripe) % 255u;
  let blockCoord = floor(uv * vec2<f32>(16.0));
  let blockSeed = hash21(blockCoord + vec2<f32>(floor(t), 0.0));
  let blockMask = u32(blockSeed * 255.0);
  let scanLine = abs(uv.y - fract(t * 0.2));
  let scanActive = step(scanLine, 0.02);
  let scanMask = select(0u, 0xAAu, scanActive > 0.5);
  let noiseVal = hash21(uv * 1000.0 + t);
  let noiseMask = u32(noiseVal * 255.0);
  let patternSelect = fract(patternType * 4.0 + t * 0.1);

  if (patternSelect < 0.25) { mask = stripeMask; }
  else if (patternSelect < 0.5) { mask = blockMask; }
  else if (patternSelect < 0.75) { mask = scanMask; }
  else { mask = noiseMask; }

  if (intensity < 0.5) { mask = mask & 0x0Fu; }
  return mask;
}

fn corruptByte(b: u32, corruptionType: f32, seed: f32, intensity: f32) -> u32 {
  var result = b;
  let typeIdx = u32(corruptionType * 5.0) % 6u;
  switch(typeIdx) {
    case 0u: { result = bitRotateRight(b, u32(seed * 8.0)); }
    case 1u: { result = xorCorrupt(b, u32(seed * 255.0)); }
    case 2u: { result = randomBitFlip(b, seed, intensity * 0.3); }
    case 3u: { result = nibbleSwap(b); }
    case 4u: { result = bitReverse(b); }
    case 5u: { result = bitRotateLeft(b, 2u); result = xorCorrupt(result, u32(seed * 128.0)); }
    default: {}
  }
  return result & 0xFFu;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let texelCoord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let corruptionIntensity = clamp(u.zoom_params.x, 0.0, 1.0);
  let bitManipulationType = u.zoom_params.y;
  let mousePos = u.zoom_config.yz;
  let mouseDist = distance(uv, mousePos);
  let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);
  let effectiveIntensity = clamp(corruptionIntensity + mouseInfluence * 0.3, 0.0, 1.0);

  // Block displacement
  let blockSize = mix(8.0, 64.0, effectiveIntensity);
  let blockCoord = floor(uv * blockSize);
  let blockSeed = hash21(blockCoord + vec2<f32>(time * 0.1, 0.0));
  let maxShift = mix(0.0, 0.05, effectiveIntensity);
  let xShift = (blockSeed - 0.5) * maxShift;
  let yShift = (hash21(blockCoord + vec2<f32>(7.0, 3.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;
  var displacedUV = uv + vec2<f32>(xShift, yShift);

  let row = floor(uv.y * blockSize);
  let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
  let tear = step(0.95, scanSeed);
  displacedUV.x = displacedUV.x + tear * 0.15 * (blockSeed - 0.5) * effectiveIntensity;

  // Sample base image at displaced UV
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  var color = baseColor.rgb;

  // Bitwise corruption
  if (effectiveIntensity > 0.01) {
    let pixelSeed = hash33(vec3<f32>(uv * 1000.0, time));
    let corruptionMask = getCorruptionMask(uv, time, blockSeed, effectiveIntensity);
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
      var byteVal = floatToByte(color[channel]);
      let channelSeed = hash21(uv + vec2<f32>(f32(channel) * 100.0, time));
      let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
      byteVal = randomBitFlip(byteVal, channelSeed, flipProb);
      if (blockSeed > (0.7 - effectiveIntensity * 0.4)) {
        let patternIntensity = (blockSeed - 0.7 + effectiveIntensity * 0.4) / (0.3 + effectiveIntensity * 0.4);
        let typeVar = bitManipulationType + f32(channel) * 0.1;
        byteVal = corruptByte(byteVal, typeVar, channelSeed, patternIntensity);
        if (patternIntensity > 0.5) {
          byteVal = xorCorrupt(byteVal, corruptionMask);
        }
      }
      let temporalSeed = hash21(uv + vec2<f32>(floor(time * 2.0)));
      if (temporalSeed < effectiveIntensity * 0.15) {
        byteVal = bitRotateRight(byteVal, u32(temporalSeed * 8.0));
      }
      color[channel] = byteToFloat(byteVal);
    }
  }

  // Pass-through original to writeTexture
  textureStore(writeTexture, texelCoord, baseColor);

  // Store glitch field: displaced UV + corruption intensity + block seed
  textureStore(dataTextureA, texelCoord,
    vec4<f32>(displacedUV.x, displacedUV.y, effectiveIntensity, blockSeed));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
