// ═══════════════════════════════════════════════════════════════════
//  Solarize Warp v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: solarize-warp
//  Created: 2026-05-30
//  By: 4-Agent Shader Upgrade Swarm
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

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = fract(p * vec2<f32>(0.1031, 0.1030));
  return fract(h * (h + 33.19) * vec2<f32>(43758.5453, 43758.5453));
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var shift = vec2<f32>(100.0, 100.0);
  var pp = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * (sin(pp.x * 2.7 + pp.y * 1.3) * cos(pp.x * 1.1 - pp.y * 3.2));
    pp = pp * 2.1 + shift;
    a = a * 0.48;
  }
  return v;
}

fn sabattier(tone: vec3<f32>, threshold: f32, strength: f32) -> vec3<f32> {
  let luma = dot(tone, vec3<f32>(0.299, 0.587, 0.114));
  let edge = abs(luma - threshold);
  let invertMask = smoothstep(0.0, 0.12, edge) * step(threshold, luma);
  let inverted = 1.0 - tone;
  var out = mix(tone, inverted, invertMask * strength);
  let mackie = smoothstep(0.08, 0.0, edge) * strength * 0.55;
  out = out + vec3<f32>(0.85, 0.90, 0.75) * mackie;
  return out;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let twistStrength = u.zoom_params.x * 4.5;
  let solarizeThreshold = mix(0.15, 0.85, u.zoom_params.y);
  let effectRadius = mix(0.08, 0.80, u.zoom_params.z);
  let effectIntensity = mix(0.05, 1.0, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let influence = 1.0 - smoothstep(0.0, effectRadius, dist);

  let bassOsc = sin(time * 1.8) * audio.x * 0.18;
  let threshold = clamp(solarizeThreshold + bassOsc * influence, 0.05, 0.95);

  let warpNoise = fbm(uv * 3.0 + time * 0.25 + audio.y * 0.5);
  let warpAngle = twistStrength * influence * (1.0 + audio.x * 0.7)
                  + warpNoise * 0.35
                  + sin(time * 2.0 + dist * 18.0) * 0.15;
  let s = sin(warpAngle);
  let c = cos(warpAngle);
  let rotated = vec2<f32>(
    centered.x * c - centered.y * s,
    centered.x * s + centered.y * c
  );
  let warpedUV = clamp(rotated / vec2<f32>(aspect, 1.0) + mouse, vec2<f32>(0.0), vec2<f32>(1.0));

  let parallax = depth * 0.04 * influence;
  let layerUV = clamp(warpedUV + vec2<f32>(parallax, parallax * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

  let source = textureSampleLevel(readTexture, u_sampler, layerUV, 0.0).rgb;
  let solarized = sabattier(source, threshold, effectIntensity);

  let shadowTint = mix(vec3<f32>(0.95, 0.42, 0.15), vec3<f32>(0.12, 0.62, 0.92), 0.5 + 0.5 * sin(time * 0.6 + dist * 14.0));
  let highlightTint = mix(vec3<f32>(1.0, 0.78, 0.35), vec3<f32>(0.55, 0.88, 1.0), 0.5 + 0.5 * cos(time * 0.4 + dist * 10.0));
  let luma = dot(solarized, vec3<f32>(0.299, 0.587, 0.114));
  let splitTone = mix(shadowTint * solarized, highlightTint * solarized, smoothstep(0.35, 0.65, luma));

  let grain = hash22(uv * dims + fract(time * 73.0)).x - 0.5;
  var finalColor = mix(solarized, splitTone, influence * 0.45) + grain * 0.018;

  finalColor = acesFilm(finalColor * 1.1);

  let edgeDensity = smoothstep(0.0, 0.12, abs(luma - threshold));
  let finalAlpha = clamp(effectIntensity * edgeDensity * depth * 1.8, 0.12, 0.95);

  let depthOut = clamp(mix(depth, 0.20 + influence * 0.72, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, edgeDensity, threshold, finalAlpha));
}
