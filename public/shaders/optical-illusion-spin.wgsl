// ═══════════════════════════════════════════════════════════════════
//  Optical Illusion Spin v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: optical-illusion-spin
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = fract(p * vec2<f32>(0.1031, 0.1030));
  return fract(h.x * h.y * 43758.5453);
}

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn snakePattern(coord: vec2<f32>, rings: f32, time: f32, dir: f32) -> f32 {
  let radius = length(coord);
  let angle = atan2(coord.y, coord.x);
  let ringIndex = floor(radius * rings);
  let ringPhase = fract(radius * rings);
  let alt = select(-1.0, 1.0, fract(ringIndex * 0.5) >= 0.5);
  let snakeAngle = angle + dir * time * 1.6 + ringIndex * 0.35 * alt;
  let wedge = fract(snakeAngle * 3.0 / 6.28318);
  let edge = 1.0 - smoothstep(0.38, 0.50, abs(wedge - 0.5));
  let ringEdge = 1.0 - smoothstep(0.42, 0.50, abs(ringPhase - 0.5));
  return edge * ringEdge;
}

fn moireInterference(a: f32, b: f32) -> f32 {
  return abs(a - b) * 2.0;
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

  let ringCount = 4.0 + u.zoom_params.x * 44.0;
  let speed = 0.15 + u.zoom_params.y * 5.0;
  let twistForce = u.zoom_params.z * 4.5;
  let alternating = u.zoom_params.w;

  let scale = 1.0 - depth * 0.3;
  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0) / scale;
  let radius = length(centered);
  let angle = atan2(centered.y, centered.x);

  let bassSpeed = speed * (1.0 + audio.x * 1.2);
  let dirA = mix(1.0, select(-1.0, 1.0, fract(floor(radius * ringCount) * 0.5) >= 0.5), alternating);
  let dirB = -dirA * 0.7;

  let twist = (1.0 - smoothstep(0.0, 1.1, radius)) * twistForce;
  let pulse = sin(time * bassSpeed * 2.0 + floor(radius * ringCount) * 0.7) * (0.35 + 0.65 * audio.x);
  let spun = rotate(centered, twist + pulse * 0.18);
  let sampleUV = clamp(spun / vec2<f32>(aspect, 1.0) + mouse, vec2<f32>(0.0), vec2<f32>(1.0));

  let patA = snakePattern(centered, ringCount, time * bassSpeed, dirA);
  let patB = snakePattern(centered * 1.03 + vec2<f32>(0.01, 0.0), ringCount, time * bassSpeed * 0.94, dirB);
  let moire = moireInterference(patA, patB);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let localWarp = sin(mouseDist * 20.0 - time * 3.0) * 0.015 * (1.0 - smoothstep(0.0, 0.3, mouseDist));
  let warpUV = clamp(sampleUV + vec2<f32>(localWarp, localWarp * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

  var baseColor = textureSampleLevel(readTexture, u_sampler, warpUV, 0.0).rgb;

  let opColorA = mix(vec3<f32>(0.05, 0.82, 0.95), vec3<f32>(0.95, 0.92, 0.05), 0.5 + 0.5 * sin(angle * 4.0 + time * bassSpeed));
  let opColorB = mix(vec3<f32>(0.95, 0.25, 0.05), vec3<f32>(0.15, 0.95, 0.42), 0.5 + 0.5 * cos(angle * 3.0 - time * bassSpeed * 0.8));
  let opArt = mix(opColorA, opColorB, moire) * (patA + patB + moire * 0.5);

  let afterimage = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(warpUV + vec2<f32>(0.008, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, warpUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(warpUV - vec2<f32>(0.008, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  var finalColor = mix(baseColor, opArt, clamp((patA + patB) * 0.35, 0.0, 0.65));
  finalColor = mix(finalColor, afterimage, 0.12 * (patA + patB));

  let dither = (hash21(vec2<f32>(f32(gid.x), f32(gid.y)) + fract(time * 17.0)) - 0.5) * 0.012;
  finalColor = finalColor + dither;

  let edgeHDR = (patA + patB) * (0.08 + 0.18 * audio.z);
  finalColor = finalColor + vec3<f32>(0.92, 0.78, 0.55) * edgeHDR;

  finalColor = acesFilm(finalColor * 1.12);

  let contrast = abs(patA - patB) * 2.0 + 0.2;
  let illusionStrength = clamp((patA + patB + moire) * 0.5, 0.0, 1.0);
  let finalAlpha = clamp(illusionStrength * contrast * depth * 1.6, 0.14, 0.95);

  let depthOut = clamp(mix(depth, 0.28 + edgeHDR * 0.65, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(patA, patB, moire, finalAlpha));
}
