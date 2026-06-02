// ═══════════════════════════════════════════════════════════════════
//  Tone Histogram v2
//  Category: post-processing
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: tone-histogram
//  Upgraded: 2026-05-30
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

fn acesTone(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn filmCurve(x: f32, toe: f32, shoulder: f32) -> f32 {
  let t = toe * 0.3;
  let s = shoulder * 0.3;
  let shadow = mix(x * (1.0 + t), x, smoothstep(0.0, 0.25, x));
  let highlight = mix(shadow, 1.0 - (1.0 - shadow) * (1.0 - s), smoothstep(0.75, 1.0, shadow));
  return clamp(highlight, 0.0, 1.0);
}

fn grain(uv: vec2<f32>, time: f32) -> f32 {
  let n = fract(sin(dot(uv + time * 0.01, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  return (n - 0.5) * 0.04;
}

fn localStats(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  var sum = 0.0;
  var sumSq = 0.0;
  for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
    for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * texel;
      let c = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
      let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
      sum = sum + l;
      sumSq = sumSq + l * l;
    }
  }
  let mean = sum / 9.0;
  let variance = max(0.0, sumSq / 9.0 - mean * mean);
  return vec2<f32>(mean, sqrt(variance));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let texel = 1.0 / resolution;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let stretchAmount = u.zoom_params.x;
  let toeStrength = u.zoom_params.y;
  let shoulderStrength = u.zoom_params.z;
  let hazeRemoval = u.zoom_params.w;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Per-pixel local histogram equalization via sliding-window statistics
  let stats = localStats(uv, texel);
  let localMean = stats.x;
  let localStd = stats.y;

  // Adaptive contrast stretch driven by parameter and bass intensity
  let targetStd = mix(0.12, 0.28, stretchAmount + bass * 0.12);
  let adaptGain = select(targetStd / max(localStd, 0.01), 1.0, localStd < 0.001);
  let adaptGainClamped = clamp(adaptGain, 0.5, 2.5);

  let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let chroma = src.rgb - vec3<f32>(luma);

  // Apply local adaptive stretch
  var stretchedLuma = (luma - localMean) * adaptGainClamped + localMean;
  stretchedLuma = clamp(stretchedLuma, 0.0, 1.0);

  // Film-like tonal curve with toe and shoulder rolloff
  let curvedLuma = filmCurve(stretchedLuma, toeStrength, shoulderStrength);

  // Split-tone shadows (cool blue) and highlights (warm amber)
  let shadowTint = vec3<f32>(0.06, 0.05, 0.10) * (1.0 - smoothstep(0.0, 0.3, curvedLuma));
  let highlightTint = vec3<f32>(0.10, 0.07, 0.03) * smoothstep(0.7, 1.0, curvedLuma);
  let splitTone = shadowTint + highlightTint;

  // Recombine luma with saturation-adjusted chroma
  var color = vec3<f32>(curvedLuma) + chroma * mix(0.8, 1.4, stretchAmount) + splitTone * 0.3;

  // Grain texture layered for filmic feel
  let g1 = grain(uv, time) * (1.0 + mids * 0.5);
  let g2 = grain(uv * 1.7 + 0.3, time * 0.7) * 0.5;
  color = color + vec3<f32>(g1 + g2);

  // Mouse creates local exposure zones (dodge/burn)
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let exposureZone = smoothstep(0.25, 0.0, mouseDist) * mouseDown;
  color = color * (1.0 + exposureZone * 0.4);

  // Depth controls haze removal strength
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let haze = (1.0 - depth) * hazeRemoval * 0.3;
  let hazeColor = vec3<f32>(0.75, 0.78, 0.82);
  color = mix(color, hazeColor, haze);

  // ACES tone mapping for cinematic output
  let finalColor = acesTone(max(color, vec3<f32>(0.0)));

  // Alpha: tonal confidence × local_contrast × depth
  let tonalConfidence = smoothstep(0.0, 0.15, abs(curvedLuma - localMean) + localStd);
  let localContrast = smoothstep(0.0, 0.2, localStd) * 0.5 + 0.5;
  let alpha = clamp(tonalConfidence * localContrast * depth + 0.18, 0.15, 0.9);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(localMean, localStd, curvedLuma, alpha));
}
