// ═══════════════════════════════════════════════════════════════════
//  Soft Vignette Bloom v2
//  Category: post-processing
//  Features: bloom, cinematic, audio-reactive, depth-aware
//  Complexity: High
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

// ═══ CHUNK: aces_approx ═══
fn aces_approx(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let texel = 1.0 / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let vignetteStrength = u.zoom_params.x;
  let bloomRadius = u.zoom_params.y;
  let hazeAmount = u.zoom_params.z;
  let bloomIntensity = u.zoom_params.w;

  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var col = base.rgb;
  let baseAlpha = base.a;

  // Multi-scale Gaussian bloom pyramid (3 scales)
  var bloom = vec3<f32>(0.0);
  var bloomEnergy = 0.0;
  let scales = array<f32, 3>(1.0, 2.5, 5.0);
  let weights = array<f32, 3>(0.5, 0.3, 0.2);

  for (var level: u32 = 0u; level < 3u; level = level + 1u) {
    let r = max(bloomRadius * scales[level], 1.0);
    var lvlBloom = vec3<f32>(0.0);
    var lvlWeight = 0.0;
    for (var dy = -2; dy <= 2; dy = dy + 1) {
      for (var dx = -2; dx <= 2; dx = dx + 1) {
        let off = vec2<f32>(f32(dx), f32(dy)) * texel * r;
        let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let luma = dot(samp, vec3<f32>(0.299, 0.587, 0.114));
        // Bass lowers bloom threshold
        let thresh = 0.5 - bass * 0.25;
        let brightMask = smoothstep(thresh, thresh + 0.2, luma);
        lvlBloom = lvlBloom + samp * brightMask;
        lvlWeight = lvlWeight + brightMask;
      }
    }
    if (lvlWeight > 0.0) {
      lvlBloom = lvlBloom / lvlWeight;
    }
    bloom = bloom + lvlBloom * weights[level];
    bloomEnergy = bloomEnergy + dot(lvlBloom, vec3<f32>(0.299, 0.587, 0.114)) * weights[level];
  }

  // Anamorphic streaks on bright highlights (horizontal stretch)
  var streak = vec3<f32>(0.0);
  let streakSamples = 8;
  for (var i = -streakSamples; i <= streakSamples; i = i + 1) {
    let off = vec2<f32>(f32(i) * texel.x * bloomRadius * 3.0, 0.0);
    let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let luma = dot(samp, vec3<f32>(0.299, 0.587, 0.114));
    let weight = smoothstep(0.6, 0.9, luma) * exp(-abs(f32(i)) * 0.3);
    streak = streak + samp * weight;
  }
  bloom = bloom + streak * 0.15 * bloomIntensity;

  col = col + bloom * bloomIntensity * 0.4;

  // Superellipse vignette with mouse center
  let vignetteCenter = mix(vec2<f32>(0.5), mouse, 0.5);
  let d = uv - vignetteCenter;
  let aspect = res.x / res.y;
  let dist = pow(pow(abs(d.x) * aspect, 2.5) + pow(abs(d.y), 2.5), 1.0 / 2.5);
  let vignette = smoothstep(0.8, 0.25, dist * (1.0 + vignetteStrength));

  // Depth-driven haze
  let haze = mix(vec3<f32>(0.6, 0.65, 0.75), vec3<f32>(1.0), depth);
  col = mix(col, col * haze, hazeAmount * (1.0 - depth));

  // Split-tone shadows
  let shadowMask = 1.0 - dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.15, 0.08, 0.25);
  col = col + shadowTint * shadowMask * 0.15;

  // Film grain
  let grain = hash12(uv * 43758.5453 + fract(time * 0.1)) * 0.04 - 0.02;
  col = col + grain * vignette;

  // Apply vignette and tone map
  col = col * vignette;
  col = aces_approx(max(col, vec3<f32>(0.0)));

  // Alpha: bloom energy × vignette factor
  let alpha = clamp(bloomEnergy * vignette * 2.0 + baseAlpha * 0.3, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
