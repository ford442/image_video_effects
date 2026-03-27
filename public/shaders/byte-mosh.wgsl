// ═══════════════════════════════════════════════════════════════
//  Byte-Mosh - Bitwise Pixel Glitching with Alpha Corruption
//  Category: retro-glitch
//
//  XOR, AND, shift and rotate operations on pixel data:
//  - Bit-level corruption on all channels including alpha
//  - Block-based coherent glitches
//  - Mouse interaction creates glitch zones
//  - Ripple glitches with bit rotation
//  - Alpha bit corruption creates transparency artifacts
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=OperationMix, y=BitShift, z=ErrorRate, w=BlockSize
  ripples: array<vec4<f32>, 50>,
};

// Random functions
fn hash11(p: f32) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 * (p3 + 33.33);
  return fract(p3 * (p3 + p3));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

// Maximum value for 8-bit color channel (255)
const MAX_CHANNEL_VALUE: f32 = 255.0;

// Convert float (0-1) to u32 representation for 8-bit channel
fn floatToU32(x: f32) -> u32 {
  return u32(clamp(x, 0.0, 1.0) * MAX_CHANNEL_VALUE);
}

// Convert u32 back to float (0-1 range)
fn u32ToFloat(x: u32) -> f32 {
  return f32(x & 0xFFu) / MAX_CHANNEL_VALUE;
}

// Pack RGBA to single u32 (ARGB format for bit manipulation)
fn packRGBA(r: f32, g: f32, b: f32, a: f32) -> u32 {
  return (floatToU32(a) << 24u) | (floatToU32(r) << 16u) | (floatToU32(g) << 8u) | floatToU32(b);
}

// Unpack u32 to RGBA
fn unpackRGBA(packed: u32) -> vec4<f32> {
  return vec4<f32>(
    f32((packed >> 16u) & 0xFFu) / 255.0,
    f32((packed >> 8u) & 0xFFu) / 255.0,
    f32(packed & 0xFFu) / 255.0,
    f32((packed >> 24u) & 0xFFu) / 255.0
  );
}

// Rotate bits left
fn rotateLeft(x: u32, n: u32) -> u32 {
  return (x << n) | (x >> (32u - n));
}

// Rotate bits right
fn rotateRight(x: u32, n: u32) -> u32 {
  return (x >> n) | (x << (32u - n));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u32(u.config.y);
  
  // Parameters
  let operationMix = u.zoom_params.x;
  let bitShift = u32(mix(0.0, 8.0, u.zoom_params.y));
  let errorRate = mix(0.0, 0.5, u.zoom_params.z);
  let blockSize = max(1.0, mix(1.0, 64.0, u.zoom_params.w));
  
  // Block coordinates for coherent glitches
  let blockCoord = vec2<u32>(
    u32(floor(f32(coord.x) / blockSize)),
    u32(floor(f32(coord.y) / blockSize))
  );
  
  // Noise for block-based decisions
  let blockNoise = hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) + vec2<f32>(floor(time * 2.0)));
  let pixelNoise = hash21(uv * 1000.0 + vec2<f32>(time));
  
  // Sample source with alpha
  var sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Pack color to u32 including alpha
  var packedColor = packRGBA(sourceColor.r, sourceColor.g, sourceColor.b, sourceColor.a);
  
  // Apply operations based on block noise and error rate
  if (blockNoise < errorRate) {
    // Choose operation based on operationMix
    let opSelector = fract(blockNoise * 7.0);
    
    if (opSelector < 0.15) {
      // XOR with noise pattern - affects ALL channels including alpha
      let xorPattern = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 123.0) * 4294967295.0);
      packedColor = packedColor ^ xorPattern;
    }
    else if (opSelector < 0.3) {
      // AND mask - creates color reduction and alpha holes
      let andMask = 0xF0F0F0F0u << bitShift;
      packedColor = packedColor & andMask;
    }
    else if (opSelector < 0.45) {
      // OR with color - creates bright glitches and opaque artifacts
      let orPattern = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 456.0) * 4294967295.0) & 0x7F7F7F7Fu;
      packedColor = packedColor | orPattern;
    }
    else if (opSelector < 0.6) {
      // Bit shift left - color bleeding and alpha shift
      packedColor = packedColor << bitShift;
    }
    else if (opSelector < 0.75) {
      // Bit shift right - darkening and transparency
      packedColor = packedColor >> bitShift;
    }
    else if (opSelector < 0.9) {
      // Rotate bits - psychedelic color swap with alpha rotation
      let rotAmount = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 789.0) * 32.0);
      packedColor = rotateLeft(packedColor, rotAmount);
    }
    else {
      // Channel swap via bit manipulation - includes alpha in swaps
      let a = (packedColor >> 24u) & 0xFFu;
      let r = (packedColor >> 16u) & 0xFFu;
      let g = (packedColor >> 8u) & 0xFFu;
      let b = packedColor & 0xFFu;
      // Swap based on time - now including alpha channel
      let swapType = u32(time * 3.0) % 8u;
      if (swapType == 0u) { packedColor = (a << 24u) | (g << 16u) | (r << 8u) | b; }
      else if (swapType == 1u) { packedColor = (r << 24u) | (a << 16u) | (g << 8u) | b; }
      else if (swapType == 2u) { packedColor = (b << 24u) | (r << 16u) | (a << 8u) | g; }
      else if (swapType == 3u) { packedColor = (g << 24u) | (b << 16u) | (r << 8u) | a; }
      else if (swapType == 4u) { packedColor = (a << 24u) | (b << 16u) | (g << 8u) | r; }
      else if (swapType == 5u) { packedColor = (a << 24u) | (r << 16u) | (b << 8u) | g; }
      else if (swapType == 6u) { packedColor = (g << 24u) | (a << 16u) | (b << 8u) | r; }
      else { /* keep original */ }
    }
  }
  
  // Additional per-pixel noise corruption
  if (pixelNoise < errorRate * 0.3) {
    // Flip random bits - can corrupt alpha at bit level
    let flipMask = u32(pixelNoise * 4294967295.0) & (0xFFu << (bitShift * 4u));
    packedColor = packedColor ^ flipMask;
  }
  
  // Mouse interaction - create glitch zone
  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(uv - mouse);
  let mouseInfluence = 0.15;
  
  if (mouseDist < mouseInfluence) {
    let strength = 1.0 - mouseDist / mouseInfluence;
    let mouseGlitch = u32(strength * 255.0);
    
    // XOR with distance-based pattern - affects alpha too
    let distPattern = u32(mouseDist * 1000.0) * 0x11111111u;
    packedColor = packedColor ^ (distPattern & ((mouseGlitch << 24u) | (mouseGlitch << 16u) | (mouseGlitch << 8u) | mouseGlitch));
  }
  
  // Ripple glitches
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 1.5) {
        let dist = length(uv - ripple.xy);
        let ring = abs(dist - rippleAge * 0.3);
        if (ring < 0.02) {
          let rippleStrength = (1.0 - rippleAge / 1.5);
          let rippleShift = u32(rippleStrength * 8.0);
          packedColor = rotateLeft(packedColor, rippleShift);
        }
      }
    }
  }
  
  // Unpack result including alpha
  var finalColor = unpackRGBA(packedColor);
  
  // Scanline effect for retro feel
  let scanline = sin(uv.y * u.config.w * 3.14159) * 0.1 + 0.9;
  
  // Add temporal flicker in glitched areas
  if (blockNoise < errorRate) {
    let flicker = hash11(time * 100.0 + f32(coord.x)) * 0.2 + 0.8;
    let newRGB = finalColor.rgb * flicker * scanline;
    let newA = finalColor.a * (0.7 + flicker * 0.3);
    finalColor = vec4<f32>(newRGB, newA);
  }
  
  // Chromatic aberration in glitched blocks
  if (blockNoise < errorRate * 0.5) {
    let offset = (blockNoise - errorRate * 0.25) * 0.02;
    let rSample = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(offset, 0.0), 0.0).b;
    // Preserve alpha during chromatic aberration
    let originalAlpha = finalColor.a;
    finalColor = vec4<f32>(rSample, finalColor.g, bSample, originalAlpha);
  }
  
  // Clamp final color and alpha
  finalColor = clamp(finalColor, vec4<f32>(0.0), vec4<f32>(1.0));
  
  // Output RGBA with corrupted/preserved alpha
  textureStore(writeTexture, vec2<i32>(coord), finalColor);
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
