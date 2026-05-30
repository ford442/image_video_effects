// ═══════════════════════════════════════════════════════════════════
//  Ripple Bloom
//  Category: hybrid
//  Features: ripple, bloom, audio-reactive, mouse-interactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: ripple-bloom
//  Created: 2026-05-30
//  By: 4-Agent Upgrade Swarm
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let rippleAmount = u.zoom_params.x * (0.8 + bass * 0.7);
  let bloomAmount = u.zoom_params.y * (0.9 + treble * 0.6);
  let mouseInfluence = u.zoom_params.z;
  let colorShift = u.zoom_params.w;

  // Depth controls water depth (affects ripple speed)
  let waterDepth = mix(0.3, 1.0, 1.0 - depth);
  let rippleSpeed = 3.5 * waterDepth;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Huygens wavelet construction: multiple frequency ripples with dispersion
  let distToMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  var ripple = 0.0;
  var rippleHeight = 0.0;
  for (var f: i32 = 0; f < 3; f = f + 1) {
    let freq = 8.0 + f32(f) * 10.0;
    let phase = distToMouse * freq - time * rippleSpeed * (1.0 + f32(f) * 0.15);
    let decay = exp(-distToMouse * (3.0 + f32(f) * 0.8));
    let wave = sin(phase) * decay;
    ripple = ripple + wave * (1.0 - f32(f) * 0.2);
    rippleHeight = rippleHeight + abs(wave) * (1.0 - f32(f) * 0.15);
  }
  ripple = ripple * rippleAmount * 0.4;
  rippleHeight = rippleHeight * rippleAmount;

  let displacedUV = clamp(uv + vec2<f32>(ripple * 0.02, ripple * 0.015), vec2<f32>(0.0), vec2<f32>(1.0));
  var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Chromatic dispersion on ripple crests
  let crest = smoothstep(0.2, 0.8, rippleHeight);
  let caOffset = crest * 0.004 * colorShift;
  let rSamp = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(caOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSamp = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - vec2<f32>(caOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  color = vec3<f32>(rSamp, color.g, bSamp);

  // HDR bloom on constructive interference
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = smoothstep(0.5, 0.92, luma) * bloomAmount;
  color = color + bloom * vec3<f32>(0.5, 0.75, 1.0) * (0.6 + mids * 0.5);

  // Subsurface scattering in ripple troughs
  let trough = 1.0 - crest;
  let sss = trough * rippleHeight * 0.15 * vec3<f32>(0.4, 0.6, 0.9);
  color = color + sss;

  // Mouse light tint (stone drop)
  let mouseLight = (1.0 - smoothstep(0.0, 0.45, distToMouse)) * mouseInfluence * 0.5;
  color = color + mouseLight * vec3<f32>(0.8, 0.9, 1.0);

  // Color shift from audio
  let hueShift = colorShift * 0.15 + mids * 0.08;
  color = mix(color, color * vec3<f32>(1.0 + hueShift, 1.0 - hueShift * 0.5, 1.0 - hueShift), 0.2);

  // ACES tone mapping
  color = acesToneMap(color * 1.2);

  // Semantic alpha: ripple_height * dispersion_intensity * depth
  let dispersionIntensity = crest + bloom * 0.5 + rippleHeight * 0.3;
  let semanticAlpha = clamp(rippleHeight * dispersionIntensity * depth * 2.0, 0.15, 0.95);

  let depthOut = clamp(mix(depth, 0.25 + rippleHeight * 0.6, 0.2), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, semanticAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ripple, rippleHeight, bloom, semanticAlpha));
}
