// ═══════════════════════════════════════════════════════════════════
//  Phosphor Magnifier v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: phosphor-magnifier
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

fn hash31(p: f32) -> vec3<f32> {
  let h = fract(vec3<f32>(p, p + 127.1, p + 311.7) * 0.1031);
  return fract(h * (h + 33.19) * 43758.5453);
}

fn shadowMask(uv: vec2<f32>, pixelSize: f32) -> vec3<f32> {
  let local = fract(uv * pixelSize);
  let r = smoothstep(0.32, 0.38, local.x) * smoothstep(0.62, 0.56, local.x);
  let g = smoothstep(0.32, 0.38, abs(local.x - 0.5)) * smoothstep(0.62, 0.56, abs(local.x - 0.5));
  let b = smoothstep(0.32, 0.38, 1.0 - local.x) * smoothstep(0.62, 0.56, 1.0 - local.x);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bassExcite = 1.0 + audio.x * 1.2;

  let zoomLevel = mix(1.0, 10.0, u.zoom_params.x);
  let pixelSize = mix(20.0, 320.0, u.zoom_params.y);
  let glow = mix(0.05, 0.65, u.zoom_params.z);
  let lensSize = mix(0.08, 0.50, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let lensMask = 1.0 - smoothstep(lensSize * 0.85, lensSize, dist);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthMag = mix(1.0, 1.0 + depth * 2.5, lensMask);

  let barrel = centered * (1.0 + 0.18 * lensMask * length(centered) * length(centered));
  let displaced = barrel / vec2<f32>(aspect, 1.0) + mouse;

  let caStrength = 0.004 * lensMask * zoomLevel;
  let sampleR = clamp(displaced + vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleG = clamp(displaced, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleB = clamp(displaced - vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let zoomedR = clamp(mouse + (sampleR - mouse) / (zoomLevel * depthMag), vec2<f32>(0.0), vec2<f32>(1.0));
  let zoomedG = clamp(mouse + (sampleG - mouse) / (zoomLevel * depthMag), vec2<f32>(0.0), vec2<f32>(1.0));
  let zoomedB = clamp(mouse + (sampleB - mouse) / (zoomLevel * depthMag), vec2<f32>(0.0), vec2<f32>(1.0));

  let snappedR = floor(zoomedR * pixelSize) / pixelSize;
  let snappedG = floor(zoomedG * pixelSize) / pixelSize;
  let snappedB = floor(zoomedB * pixelSize) / pixelSize;

  let colR = textureSampleLevel(readTexture, u_sampler, snappedR, 0.0).r;
  let colG = textureSampleLevel(readTexture, u_sampler, snappedG, 0.0).g;
  let colB = textureSampleLevel(readTexture, u_sampler, snappedB, 0.0).b;
  var sampleColor = vec3<f32>(colR, colG, colB);

  let mask = shadowMask(snappedG, pixelSize);
  let phosphorDecay = vec3<f32>(0.92, 0.88, 0.95);
  let decayFactor = exp(-time * vec3<f32>(1.2, 0.8, 1.6) * (1.0 - phosphorDecay));
  let excitation = 0.55 + 0.45 * bassExcite * decayFactor;

  let scanLine = 0.55 + 0.45 * sin(snappedG.y * dims.y * 0.55 + time * 6.0);
  let scanBeat = 1.0 + audio.z * 0.3 * sin(snappedG.y * 40.0 + time * 12.0);
  let phosphor = sampleColor * mask * excitation * scanLine * scanBeat;

  let brightness = dot(phosphor, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = glow * lensMask * brightness * brightness * (0.6 + audio.x + audio.y * 0.5);
  var finalColor = phosphor + vec3<f32>(0.18, 0.92, 0.42) * bloom;

  let afterimage = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let trail = mix(afterimage, finalColor, 0.12);
  finalColor = mix(finalColor, trail, 0.22 * lensMask);

  finalColor = acesFilm(finalColor * 1.15);

  let magnification = lensMask * zoomLevel * 0.1;
  let exciteAlpha = clamp(dot(excitation, vec3<f32>(0.333)), 0.0, 1.0);
  let finalAlpha = clamp(exciteAlpha * magnification * depth * 3.5, 0.15, 0.96);

  let depthOut = clamp(mix(depth, 0.18 + lensMask * 0.74, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lensMask, scanLine, bloom, finalAlpha));
}
