// ═══════════════════════════════════════════════════════════════════
//  Engraving Stipple v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, line-art
//  Complexity: High
//  Chunks From: engraving-stipple
//  Created: 2026-05-31
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
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

  let lineDensity = mix(50.0, 280.0, u.zoom_params.x);
  let stippleScale = mix(3.0, 26.0, u.zoom_params.y);
  let contrast = mix(0.7, 3.2, u.zoom_params.z);
  let lightRotation = u.zoom_params.w * 6.28318 + time * 0.15;

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = pow(clamp(luminance(src.rgb), 0.0, 1.0), contrast);

  let gx = sampleLuma(uv + vec2<f32>(px.x, 0.0)) - sampleLuma(uv - vec2<f32>(px.x, 0.0));
  let gy = sampleLuma(uv + vec2<f32>(0.0, px.y)) - sampleLuma(uv - vec2<f32>(0.0, px.y));
  let gradMag = length(vec2<f32>(gx, gy));
  let gradDir = atan2(gy, gx);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let lineWidth = mix(1.0, 0.4, depth) * (1.0 + audio.x * 0.3);

  let contourDir = vec2<f32>(cos(gradDir), sin(gradDir));
  let hatchDir = vec2<f32>(cos(lightRotation), sin(lightRotation));
  let crossDir = vec2<f32>(-hatchDir.y, hatchDir.x);

  let contourLine = 0.5 + 0.5 * sin(dot(uv * vec2<f32>(aspect, 1.0), contourDir) * lineDensity * 0.6);
  let hatchLine = 0.5 + 0.5 * sin(dot(uv * vec2<f32>(aspect, 1.0), hatchDir) * lineDensity);
  let crossLine = 0.5 + 0.5 * sin(dot(uv * vec2<f32>(aspect, 1.0), crossDir) * lineDensity * 0.7);

  let densityMask = smoothstep(0.0, 0.35, gradMag);
  let hatchMix = mix(hatchLine, contourLine, densityMask);
  let combinedHatch = hatchMix * 0.55 + crossLine * 0.3;

  let burrUV = uv * stippleScale * 60.0;
  let stipple = hash12(floor(burrUV));
  let burr = smoothstep(0.45, 0.55, sin(dot(uv, hatchDir) * lineDensity * 2.0) * sin(dot(uv, crossDir) * lineDensity * 1.4));

  let pressure = 1.0 + audio.x * 0.5;
  let ink = clamp((1.0 - luma) * pressure * 1.15 + combinedHatch * 0.28 - stipple * 0.5 + burr * 0.08, 0.0, 1.0);

  let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let burin = 1.0 - smoothstep(0.0, 0.5, length(mouseDelta));
  let burinCut = burin * smoothstep(0.3, 0.7, hash12(floor(uv * 90.0) + vec2<f32>(time * 3.0, 0.0))) * 0.18;

  let paperNoise = hash12(floor(uv * 400.0)) * 0.04;
  let warmPaper = mix(vec3<f32>(0.95, 0.92, 0.85), vec3<f32>(0.88, 0.94, 0.98), audio.y * 0.2) + paperNoise;
  let inkColor = mix(vec3<f32>(0.10, 0.08, 0.06), vec3<f32>(0.04, 0.09, 0.16), audio.z * 0.3);
  let deepBlack = inkColor * 0.6 - vec3<f32>(0.02, 0.0, 0.01) * ink * 0.15;

  let poolInk = smoothstep(0.75, 1.0, ink) * 0.12;
  var finalColor = mix(warmPaper, inkColor, clamp(ink + burinCut, 0.0, 1.0));
  finalColor = mix(finalColor, deepBlack, poolInk);
  finalColor = acesToneMap(finalColor * 1.1);

  let lineDensityAlpha = clamp(ink * 0.85 + combinedHatch * 0.35 + burinCut * 0.5, 0.0, 1.0);
  let inkSat = length(inkColor);
  let finalAlpha = clamp(lineDensityAlpha * inkSat * depth + 0.06, 0.05, 0.95);

  let outDepth = clamp(mix(depth, 0.18 + ink * 0.75, 0.26), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ink, combinedHatch, burin, finalAlpha));
}
