// ═══════════════════════════════════════════════════════════════════
//  Infinite Zoom Lens v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: High
//  Chunks From: infinite-zoom-lens
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn drosteUV(uv: vec2<f32>, center: vec2<f32>, spiralZoom: f32, twist: f32) -> vec2<f32> {
  let offset = uv - center;
  let aspect = 1.0;
  let p = vec2<f32>(offset.x * aspect, offset.y);
  let r = length(p);
  let theta = atan2(p.y, p.x);
  let logR = log(max(r, 1e-5));
  let spiralAngle = logR * twist + spiralZoom;
  let newR = exp(logR * 0.72);
  let newTheta = theta + spiralAngle;
  let rotated = vec2<f32>(cos(newTheta), sin(newTheta)) * newR;
  return center + vec2<f32>(rotated.x / aspect, rotated.y);
}

fn grain(uv: vec2<f32>, t: f32) -> f32 {
  return fract(sin(dot(uv + t, vec2<f32>(12.9898, 78.233))) * 43758.5453) * 0.04 - 0.02;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let zoomSpeed = mix(0.3, 2.5, u.zoom_params.x + bass * 0.35);
  let radius = mix(0.06, 0.55, u.zoom_params.y);
  let persistence = mix(0.4, 0.95, u.zoom_params.z);
  let twistAmt = (u.zoom_params.w - 0.5) * 2.2 + bass * 0.35;
  let recursionDepth = i32(mix(2.0, 7.0, depth));

  let centered = (uv - mouse) * vec2<f32>(dims.x / dims.y, 1.0);
  let dist = length(centered);
  let lensMask = 1.0 - smoothstep(radius, radius + 0.03, dist);

  var accum = vec3<f32>(0.0);
  var totalW = 0.0;
  var recursionConfidence = 0.0;

  for (var i: i32 = 0; i < recursionDepth; i = i + 1) {
    let fi = f32(i);
    let scale = pow(0.78, fi) * (1.0 + bass * 0.12);
    let angle = time * zoomSpeed * 0.15 + fi * twistAmt * 0.4;
    let spiralCenter = mouse + vec2<f32>(sin(time * 0.2 + fi * 1.3) * 0.02, cos(time * 0.17 + fi * 1.1) * 0.02);
    var sampleUV = drosteUV(uv, spiralCenter, angle, twistAmt * 0.6);
    sampleUV = (sampleUV - spiralCenter) / scale + spiralCenter;
    sampleUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let w = pow(persistence, fi);
    let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let hist = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);
    let mixed = mix(src.rgb, hist.rgb, persistence * 0.55);

    let armShift = (sampleUV - spiralCenter) * 0.025 * (1.0 + fi * 0.3) * lensMask;
    let chromaR = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + armShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let chromaB = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - armShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let chroma = vec3<f32>(chromaR, mixed.g, chromaB);

    accum = accum + chroma * w;
    totalW = totalW + w;
    recursionConfidence = recursionConfidence + w * (1.0 - abs(scale - 1.0));
  }

  var finalColor = accum / max(totalW, 1e-4);
  let focalBloom = pow(max(0.0, 1.0 - dist / radius), 4.0) * (0.15 + bass * 0.2);
  let escherTint = mix(vec3<f32>(0.15, 0.75, 1.0), vec3<f32>(1.0, 0.4, 0.85), 0.5 + 0.5 * sin(time * 0.5 + dist * 10.0));
  finalColor = finalColor + escherTint * focalBloom;

  let innerGlow = pow(max(0.0, 1.0 - dist / (radius * 0.5)), 6.0) * 0.12;
  finalColor = finalColor + vec3<f32>(innerGlow);
  finalColor = acesToneMap(finalColor * 1.1);
  finalColor = finalColor + vec3<f32>(grain(uv, time));

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  finalColor = mix(current.rgb, finalColor, lensMask);
  let spiralIntensity = smoothstep(0.1, 0.5, abs(twistAmt));
  let finalAlpha = clamp(recursionConfidence * 0.08 * spiralIntensity * depth + lensMask * 0.55 + current.a * 0.2, 0.04, 0.98);
  let outDepth = clamp(mix(depth, 0.15 + lensMask * 0.7, 0.25), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lensMask, zoomSpeed * 0.3, recursionConfidence, finalAlpha));
}
