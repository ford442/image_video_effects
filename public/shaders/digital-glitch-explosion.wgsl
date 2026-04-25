// ═══════════════════════════════════════════════════════════════════
//  digital-glitch-explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, digital-glitch, chromatic-explosion, bit-corruption
//  Complexity: Very High
//  Chunks From: digital-glitch.wgsl, mouse-chromatic-explosion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  Bitwise corruption meets prismatic chromatic explosion. Glitch
//  blocks are split into R/G/B channels displaced by pseudo-wavelength.
//  Mouse acts as a prism amplifying corruption. Click ripples launch
//  chromatic shockwaves through corrupted data.
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

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let corruptionIntensity = clamp(u.zoom_params.x, 0.0, 1.0);
  let prismStrength = mix(0.02, 0.12, u.zoom_params.y);
  let dispersion = mix(0.5, 3.0, u.zoom_params.z);
  let decayRate = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = distance(uv, mousePos);
  let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);
  let effectiveIntensity = clamp(corruptionIntensity + mouseInfluence * 0.3, 0.0, 1.0);

  // Glitch block displacement
  let blockSize = mix(8.0, 64.0, effectiveIntensity);
  let blockCoord = floor(uv * blockSize);
  let blockSeed = hash21(blockCoord + vec2<f32>(time * 0.1, 0.0));
  let maxShift = mix(0.0, 0.05, effectiveIntensity);
  let xShift = (blockSeed - 0.5) * maxShift;
  let yShift = (hash21(blockCoord + vec2<f32>(7.0, 3.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;

  var displacedUV = uv + vec2<f32>(xShift, yShift);

  // Scanline tearing
  let row = floor(uv.y * blockSize);
  let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
  let tear = step(0.95, scanSeed);
  displacedUV.x += tear * 0.15 * (blockSeed - 0.5) * effectiveIntensity;

  // Prism chromatic split on displaced UV
  let rUV = prismDisplace(displacedUV, mousePos, -1.0 * dispersion, prismStrength);
  let gUV = prismDisplace(displacedUV, mousePos, 0.0, prismStrength);
  let bUV = prismDisplace(displacedUV, mousePos, 1.0 * dispersion, prismStrength);

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
      let rDist = length((displacedUV - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((displacedUV - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let intensity = 1.0 + mouseDown * 1.5;
  var r = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * intensity, 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * intensity, 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * intensity, 0.0).b;

  // Bitwise corruption per channel
  if (effectiveIntensity > 0.01) {
    let pixelSeed = hash33(vec3<f32>(uv * 1000.0, time));
    let channels = array<f32, 3>(r, g, b);
    for (var ch: i32 = 0; ch < 3; ch = ch + 1) {
      var byteVal = floatToByte(channels[ch]);
      let channelSeed = hash21(uv + vec2<f32>(f32(ch) * 100.0, time));
      let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
      byteVal = randomBitFlip(byteVal, channelSeed, flipProb);
      channels[ch] = byteToFloat(byteVal);
    }
    r = channels[0]; g = channels[1]; b = channels[2];
  }

  var color = vec3<f32>(r, g, b);

  // Digital decay
  if (decayRate > 0.01) {
    let timeDecay = time * decayRate * 0.5;
    let spatialDecay = hash21(floor(uv * 32.0) + time * 0.1) * decayRate * 2.0;
    let targetBits = max(1.0, 8.0 - timeDecay - spatialDecay);
    let levels = max(2.0, 16.0 - timeDecay * 2.0);
    color = floor(color * levels) / levels;
  }

  // Saturation boost
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.2);

  // Spectral glow near mouse
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  color = color + vec3<f32>(0.5, 0.3, 0.8) * glow;

  let totalDisp = length(rUV - gUV) + length(gUV - bUV);
  let alpha = clamp(totalDisp * 5.0 + effectiveIntensity, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

  let corruptionState = vec4<f32>(effectiveIntensity, blockSeed, fract(time * 0.1), hash21(uv + time));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), corruptionState);
}
