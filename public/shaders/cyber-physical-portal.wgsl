// ═══════════════════════════════════════════════════════════════════
//  Cyber Physical Portal v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, portal
//  Complexity: High
//  Chunks From: cyber-physical-portal
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

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
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

  let portalRadius = mix(0.05, 0.42, u.zoom_params.x);
  let lensingStrength = mix(0.0, 4.5, u.zoom_params.y);
  let gridDensity = mix(5.0, 48.0, u.zoom_params.z);
  let glow = mix(0.06, 0.8, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let lensingScale = mix(0.6, 1.5, depth);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let angle = atan2(centered.y, centered.x);

  let eventHorizon = portalRadius * 0.85;
  let rimStart = portalRadius;
  let rimEnd = portalRadius + 0.04;

  let mask = 1.0 - smoothstep(rimStart, rimEnd, dist);
  let coreMask = 1.0 - smoothstep(0.0, eventHorizon, dist);
  let rimMask = smoothstep(rimStart, rimEnd, dist) * (1.0 - smoothstep(rimEnd, rimEnd + 0.08, dist));

  let spinSpeed = 1.5 + audio.x * 3.0;
  let frameDrag = lensingStrength * mask * (1.0 - dist / max(portalRadius, 1e-4)) * lensingScale;
  let draggedAngle = angle + frameDrag * (1.0 + audio.x * 0.5);
  let draggedCentered = vec2<f32>(cos(draggedAngle), sin(draggedAngle)) * dist;

  let lensedDist = dist + frameDrag * 0.015;
  let lensedCentered = vec2<f32>(cos(angle), sin(angle)) * lensedDist;
  let lensedUV = clamp(mouse + lensedCentered / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lensedSrc = textureSampleLevel(readTexture, u_sampler, lensedUV, 0.0).rgb;

  let gridUV = vec2<f32>(angle * 2.5, dist * gridDensity) + vec2<f32>(time * spinSpeed * 0.3, -time * spinSpeed * 0.7);
  let grid = abs(fract(gridUV) - 0.5);
  let ring = 1.0 - smoothstep(0.0, 0.035, min(grid.x, grid.y));

  var accretion = 0.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let bandR = eventHorizon + f32(i) * 0.018 + sin(time * 2.0 + f32(i) * 1.7) * 0.008;
    accretion = accretion + smoothstep(0.015, 0.0, abs(dist - bandR)) * (0.6 + hash12(vec2<f32>(bandR, time)) * 0.4);
  }

  let rimHue = 0.5 + 0.5 * sin(time * 1.4 + dist * 18.0 + audio.x * 2.0);
  let cyanMagenta = mix(vec3<f32>(0.08, 0.92, 1.0), vec3<f32>(1.0, 0.15, 0.85), rimHue);
  let hologram = cyanMagenta * (ring * 0.35 + coreMask * (glow + audio.x * 0.25) + accretion * 0.5);

  let chromaR = textureSampleLevel(readTexture, u_sampler, clamp(lensedUV + vec2<f32>(0.003 * frameDrag, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let chromaB = textureSampleLevel(readTexture, u_sampler, clamp(lensedUV - vec2<f32>(0.003 * frameDrag, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaticLensed = vec3<f32>(chromaR, lensedSrc.g, chromaB);

  var portalColor = mix(chromaticLensed, chromaticLensed * vec3<f32>(0.3, 0.95, 0.55) + cyanMagenta * 0.4, 0.5);
  portalColor = portalColor + hologram;
  portalColor = portalColor + cyanMagenta * rimMask * glow * 0.6;

  let bloom = pow(max(max(portalColor.r, portalColor.g), portalColor.b), 2.0) * 1.8 * mask;
  portalColor = portalColor + vec3<f32>(bloom * 0.5, bloom * 0.3, bloom * 0.6);

  let finalColor = acesToneMap(mix(src.rgb, portalColor, mask));
  let rimIntensity = rimMask * glow + ring * 0.4 + coreMask * glow + accretion * 0.3;
  let lensingConfidence = clamp(frameDrag / 4.5, 0.0, 1.0);
  let finalAlpha = clamp(rimIntensity * lensingConfidence * depth + mask * 0.15, 0.06, 0.96);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, lensedUV, 0.0).r;
  let outDepth = clamp(mix(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, baseDepth * 0.3, mask), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(mask, rimIntensity, lensingConfidence, finalAlpha));
}
