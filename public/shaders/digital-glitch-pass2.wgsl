// ═══════════════════════════════════════════════════════════════
//  Digital Glitch – Pass 2: Error Propagation, Decay & Compositing
//  Category: image
//  Features: multi-pass-2, error propagation, digital decay, chromatic aberration
//  Inputs: dataTextureC (glitch field from Pass 1), readTexture
//  Outputs: writeTexture (final RGBA), writeDepthTexture
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let texelCoord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let errorPropagation = u.zoom_params.z;
  let decayRate = u.zoom_params.w;

  let field = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let displacedUV = field.rg;
  let effectiveIntensity = field.b;
  let blockSeed = field.a;

  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  var color = baseColor.rgb;

  // Re-apply bitwise corruption so Pass 2 has the corrupted base
  if (effectiveIntensity > 0.01) {
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
      var byteVal = floatToByte(color[channel]);
      let channelSeed = hash21(uv + vec2<f32>(f32(channel) * 100.0, time));
      let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
      if (channelSeed < flipProb) {
        byteVal = byteVal ^ (1u << (u32(channelSeed * 1000.0) % 8u));
      }
      color[channel] = byteToFloat(byteVal);
    }
  }

  // Error Propagation
  if (errorPropagation > 0.01) {
    let texelSize = 1.0 / resolution;
    let offsets = array<vec2<f32>, 4>(
      vec2<f32>(-1.0, 0.0),
      vec2<f32>(1.0, 0.0),
      vec2<f32>(0.0, -1.0),
      vec2<f32>(0.0, 1.0)
    );
    for (var i: i32 = 0; i < 4; i = i + 1) {
      let neighborUV = uv + offsets[i] * texelSize;
      let neighborColor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
      let neighborHash = hash21(neighborUV * 500.0 + time);
      if (neighborHash < errorPropagation * 0.3) {
        let weight = 0.25 * errorPropagation;
        color = mix(color, neighborColor, weight);
      }
    }
  }

  // Digital Decay
  if (decayRate > 0.01) {
    let baseBits = 8.0;
    let timeDecay = time * decayRate * 0.5;
    let spatialDecay = hash21(floor(uv * 32.0) + time * 0.1) * decayRate * 2.0;
    let targetBits = max(1.0, baseBits - timeDecay - spatialDecay);
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
      let byteVal = floatToByte(color[channel]);
      let reduced = reduceBitDepth(byteVal, u32(targetBits));
      color[channel] = byteToFloat(reduced);
    }
    if (decayRate > 0.5) {
      let levels = max(2.0, 16.0 - timeDecay * 2.0);
      color = floor(color * levels) / levels;
    }
  }

  // Chromatic Aberration
  let chromaStrength = effectiveIntensity * 0.03;
  let rOffset = vec2<f32>(chromaStrength * (1.0 + sin(time * 2.0) * 0.5), 0.0);
  let bOffset = vec2<f32>(-chromaStrength * (1.0 + cos(time * 1.5) * 0.5), 0.0);
  let rSample = textureSampleLevel(readTexture, u_sampler, displacedUV + rOffset, 0.0).r;
  let bSample = textureSampleLevel(readTexture, u_sampler, displacedUV + bOffset, 0.0).b;
  color.r = mix(color.r, rSample, 0.5 + effectiveIntensity * 0.3);
  color.b = mix(color.b, bSample, 0.5 + effectiveIntensity * 0.3);

  // Block Color Inversion
  let blockCoord = floor(uv * mix(8.0, 64.0, effectiveIntensity));
  let invertSeed = hash21(blockCoord + vec2<f32>(time * 0.5, 100.0));
  if (invertSeed > (0.9 - effectiveIntensity * 0.4)) {
    let invertStrength = (invertSeed - 0.9 + effectiveIntensity * 0.4) / (0.1 + effectiveIntensity * 0.4);
    color = mix(color, 1.0 - color, invertStrength * 0.7);
  }

  // Scanline Artifacts
  let scanlineY = floor(uv.y * resolution.y);
  let scanlinePattern = step(0.5, fract(scanlineY * 0.5));
  color = mix(color, color * 0.9, scanlinePattern * effectiveIntensity * 0.3);

  // Vignette
  let dist = length(uv - 0.5);
  color = color * (1.0 - smoothstep(0.7, 1.0, dist) * 0.5);

  textureStore(writeTexture, texelCoord, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
