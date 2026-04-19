// ═══════════════════════════════════════════════════════════════════
//  Byte Mosh Explosion
//  Category: advanced-hybrid
//  Features: bitwise-glitch, chromatic-explosion, mouse-driven, ripple
//  Complexity: Very High
//  Chunks From: byte-mosh.wgsl, mouse-chromatic-explosion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Bitwise pixel corruption meets chromatic prism explosion. XOR, AND,
//  shift and rotate operations are applied per-channel with spectral
//  displacement radiating from mouse and ripple shockwaves.
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
  var p3 = fract(p * 0.1031);
  p3 = p3 * (p3 + 33.33);
  return fract(p3 * (p3 + p3));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

const MAX_CHANNEL_VALUE: f32 = 255.0;

fn floatToU32(x: f32) -> u32 {
  return u32(clamp(x, 0.0, 1.0) * MAX_CHANNEL_VALUE);
}

fn u32ToFloat(x: u32) -> f32 {
  return f32(x & 0xFFu) / MAX_CHANNEL_VALUE;
}

fn packRGBA(r: f32, g: f32, b: f32, a: f32) -> u32 {
  return (floatToU32(a) << 24u) | (floatToU32(r) << 16u) | (floatToU32(g) << 8u) | floatToU32(b);
}

fn unpackRGBA(packed: u32) -> vec4<f32> {
  return vec4<f32>(
    f32((packed >> 16u) & 0xFFu) / 255.0,
    f32((packed >> 8u) & 0xFFu) / 255.0,
    f32(packed & 0xFFu) / 255.0,
    f32((packed >> 24u) & 0xFFu) / 255.0
  );
}

fn rotateLeft(x: u32, n: u32) -> u32 {
  return (x << n) | (x >> (32u - n));
}

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let aspect = f32(size.x) / f32(size.y);

  let operationMix = u.zoom_params.x;
  let bitShift = u32(mix(0.0, 8.0, u.zoom_params.y));
  let errorRate = mix(0.0, 0.5, u.zoom_params.z);
  let prismStrength = mix(0.02, 0.12, u.zoom_params.w);

  let blockSize = max(1.0, mix(1.0, 64.0, u.zoom_params.y));
  let blockCoord = vec2<u32>(u32(floor(f32(coord.x) / blockSize)), u32(floor(f32(coord.y) / blockSize)));
  let blockNoise = hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) + vec2<f32>(floor(time * 2.0)));
  let pixelNoise = hash21(uv * 1000.0 + vec2<f32>(time));

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ═══ CHROMATIC EXPLOSION SAMPLING ═══
  let rUV = prismDisplace(uv, mousePos, -1.0, prismStrength);
  let gUV = prismDisplace(uv, mousePos, 0.0, prismStrength);
  let bUV = prismDisplace(uv, mousePos, 1.0, prismStrength);

  // Ripple chromatic shockwaves
  let rippleCount = min(u32(u.config.y), 50u);
  var rOffset = vec2<f32>(0.0);
  var gOffset = vec2<f32>(0.0);
  var bOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let intensity = 1.0 + mouseDown * 1.5;
  let r = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * intensity, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * intensity, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * intensity, 0.0).b;

  var sourceColor = vec4<f32>(r, g, b, 1.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // ═══ BYTE MOSH ═══
  var packedColor = packRGBA(sourceColor.r, sourceColor.g, sourceColor.b, sourceColor.a);

  if (blockNoise < errorRate) {
    let opSelector = fract(blockNoise * 7.0);
    if (opSelector < 0.15) {
      let xorPattern = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 123.0) * 4294967295.0);
      packedColor = packedColor ^ xorPattern;
    } else if (opSelector < 0.3) {
      let andMask = 0xF0F0F0F0u << bitShift;
      packedColor = packedColor & andMask;
    } else if (opSelector < 0.45) {
      let orPattern = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 456.0) * 4294967295.0) & 0x7F7F7F7Fu;
      packedColor = packedColor | orPattern;
    } else if (opSelector < 0.6) {
      packedColor = packedColor << bitShift;
    } else if (opSelector < 0.75) {
      packedColor = packedColor >> bitShift;
    } else if (opSelector < 0.9) {
      let rotAmount = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 789.0) * 32.0);
      packedColor = rotateLeft(packedColor, rotAmount);
    } else {
      let a = (packedColor >> 24u) & 0xFFu;
      let r_ch = (packedColor >> 16u) & 0xFFu;
      let g_ch = (packedColor >> 8u) & 0xFFu;
      let b_ch = packedColor & 0xFFu;
      let swapType = u32(time * 3.0) % 8u;
      if (swapType == 0u) { packedColor = (a << 24u) | (g_ch << 16u) | (r_ch << 8u) | b_ch; }
      else if (swapType == 1u) { packedColor = (r_ch << 24u) | (a << 16u) | (g_ch << 8u) | b_ch; }
      else if (swapType == 2u) { packedColor = (b_ch << 24u) | (r_ch << 16u) | (a << 8u) | g_ch; }
      else if (swapType == 3u) { packedColor = (g_ch << 24u) | (b_ch << 16u) | (r_ch << 8u) | a; }
      else if (swapType == 4u) { packedColor = (a << 24u) | (b_ch << 16u) | (g_ch << 8u) | r_ch; }
      else if (swapType == 5u) { packedColor = (a << 24u) | (r_ch << 16u) | (b_ch << 8u) | g_ch; }
      else if (swapType == 6u) { packedColor = (g_ch << 24u) | (a << 16u) | (b_ch << 8u) | r_ch; }
    }
  }

  if (pixelNoise < errorRate * 0.3) {
    let flipMask = u32(pixelNoise * 4294967295.0) & (0xFFu << (bitShift * 4u));
    packedColor = packedColor ^ flipMask;
  }

  // Mouse glitch zone
  let mouseDist = length(uv - mousePos);
  let mouseInfluence = 0.15;
  if (mouseDist < mouseInfluence) {
    let strength = 1.0 - mouseDist / mouseInfluence;
    let mouseGlitch = u32(strength * 255.0);
    let distPattern = u32(mouseDist * 1000.0) * 0x11111111u;
    packedColor = packedColor ^ (distPattern & ((mouseGlitch << 24u) | (mouseGlitch << 16u) | (mouseGlitch << 8u) | mouseGlitch));
  }

  // Ripple bit rotations
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

  var finalColor = unpackRGBA(packedColor);
  let scanline = sin(uv.y * f32(size.y) * 3.14159) * 0.1 + 0.9;

  if (blockNoise < errorRate) {
    let flicker = hash11(time * 100.0 + f32(coord.x)) * 0.2 + 0.8;
    finalColor = vec4<f32>(finalColor.rgb * flicker * scanline, finalColor.a * (0.7 + flicker * 0.3));
  }

  // Spectral glow near mouse
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  finalColor = vec4<f32>(finalColor.rgb + vec3<f32>(0.5, 0.3, 0.8) * glow, finalColor.a);

  finalColor = clamp(finalColor, vec4<f32>(0.0), vec4<f32>(1.0));

  textureStore(writeTexture, vec2<i32>(coord), finalColor);
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
