// ═══════════════════════════════════════════════════════════════
//  Digital Glitch Pass 2 — Batch 60
//  Error propagation compositing: exact C field load, depth tears,
//  held intensify, capped ripples, ACES + semantic alpha.
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

fn floatToByte(v: f32) -> u32 {
  return u32(clamp(v, 0.0, 1.0) * 255.0);
}

fn byteToFloat(b: u32) -> f32 {
  return f32(b & 0xFFu) / 255.0;
}

fn reduceBitDepth(b: u32, bits: u32) -> u32 {
  let shift = clamp(8u - bits, 0u, 8u);
  return (b >> shift) << shift;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let texelCoord = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let errorPropagation = u.zoom_params.z;
  let decayRate = u.zoom_params.w;

  let field = textureLoad(dataTextureC, texelCoord, 0);
  let displacedUV = clamp(field.rg, vec2<f32>(0.0), vec2<f32>(1.0));
  var effectiveIntensity = field.b;
  let blockSeed = field.a;

  let mouseDist = distance(uv, mouse);
  let mouseInfluence = smoothstep(0.35, 0.0, mouseDist);
  effectiveIntensity = clamp(effectiveIntensity + mouseInfluence * 0.25, 0.0, 1.0);
  effectiveIntensity = clamp(effectiveIntensity * select(1.0, 1.3, held), 0.0, 1.0);

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
  effectiveIntensity = clamp(effectiveIntensity + rippleBurst * 0.35, 0.0, 1.0);

  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  var color = baseColor.rgb;

  if (effectiveIntensity > 0.01) {
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
      var byteVal = floatToByte(color[channel]);
      let channelSeed = hash21(uv + vec2<f32>(f32(channel) * 100.0, time));
      let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
      byteVal = select(byteVal, byteVal ^ (1u << (u32(channelSeed * 1000.0) % 8u)), channelSeed < flipProb);
      color[channel] = byteToFloat(byteVal);
    }
  }

  if (errorPropagation > 0.01) {
    let offsets = array<vec2<i32>, 4>(
      vec2<i32>(-1, 0), vec2<i32>(1, 0), vec2<i32>(0, -1), vec2<i32>(0, 1)
    );
    for (var i: i32 = 0; i < 4; i = i + 1) {
      let nCoord = clamp(texelCoord + offsets[i], vec2<i32>(0), dims - vec2<i32>(1));
      let neighborColor = textureSampleLevel(readTexture, u_sampler, vec2<f32>(nCoord) / resolution, 0.0).rgb;
      let neighborHash = hash21(vec2<f32>(nCoord) / resolution * 500.0 + time);
      if (neighborHash < errorPropagation * 0.3) {
        color = mix(color, neighborColor, 0.25 * errorPropagation);
      }
    }
  }

  if (decayRate > 0.01) {
    let baseBits = 8.0;
    let timeDecay = time * decayRate * 0.5;
    let spatialDecay = hash21(floor(uv * 32.0) + time * 0.1) * decayRate * 2.0;
    let targetBits = max(1.0, baseBits - timeDecay - spatialDecay);
    let bits = u32(targetBits);
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
      color[channel] = byteToFloat(reduceBitDepth(floatToByte(color[channel]), bits));
    }
    if (decayRate > 0.5) {
      let levels = max(2.0, 16.0 - timeDecay * 2.0);
      color = floor(color * levels) / levels;
    }
  }

  let chromaStrength = effectiveIntensity * 0.035 * (1.0 + bass * 0.2);
  let rOffset = vec2<f32>(chromaStrength * (1.0 + sin(time * 2.0) * 0.5), 0.0);
  let bOffset = vec2<f32>(-chromaStrength * (1.0 + cos(time * 1.5) * 0.5), 0.0);
  color.r = mix(color.r, textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r, 0.5 + effectiveIntensity * 0.3);
  color.b = mix(color.b, textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b, 0.5 + effectiveIntensity * 0.3);

  let blockCoord = floor(uv * mix(8.0, 64.0, effectiveIntensity));
  let invertSeed = hash21(blockCoord + vec2<f32>(time * 0.5, 100.0));
  if (invertSeed > (0.9 - effectiveIntensity * 0.4)) {
    let invertStrength = (invertSeed - 0.9 + effectiveIntensity * 0.4) / max(0.1 + effectiveIntensity * 0.4, 0.0001);
    color = mix(color, 1.0 - color, invertStrength * 0.7);
  }

  let scanlineY = floor(uv.y * resolution.y);
  let scanlinePattern = step(0.5, fract(scanlineY * 0.5));
  color = mix(color, color * 0.88, scanlinePattern * effectiveIntensity * 0.35);

  let dist = length(uv - 0.5);
  color = color * (1.0 - smoothstep(0.7, 1.0, dist) * 0.5);

  let depth = textureLoad(readDepthTexture, texelCoord, 0).r;
  let depthTear = step(0.92, hash21(vec2<f32>(floor(uv.y * 40.0), floor(time * 8.0)))) * effectiveIntensity * 0.15;
  let tornDepth = mix(depth, fract(depth + blockSeed * 0.3), depthTear);

  color = acesToneMap(color * (0.95 + bass * 0.1));
  let glitchLuma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(0.5 + glitchLuma * 0.3 + effectiveIntensity * 0.25 + mouseInfluence * 0.1, 0.0, 1.0);

  textureStore(writeTexture, texelCoord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, texelCoord, vec4<f32>(tornDepth, 0.0, 0.0, 0.0));
}
