// ═══════════════════════════════════════════════════════════════════
//  Warp Drive v2
//  Category: visual-effects
//  Features: audio-reactive, upgraded-rgba, radial-blur, mouse-driven
//  Complexity: High
//  Chunks From: warp_drive
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let k = vec2<f32>(0.3183099, 0.3678794);
  var h = fract(p * k);
  h = h - floor(h);
  return fract(h * 17.0);
}

fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
  let d = length(uv - 0.5);
  return 1.0 - smoothstep(0.3, 0.8, d) * strength;
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
  let mids = plasmaBuffer[0].y;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let warpFactor = mix(1.0, 10.0, u.zoom_params.x + bass * 0.4);
  let prismSplit = mix(0.0, 0.04, u.zoom_params.y);
  let coreGlow = mix(0.05, 1.0, u.zoom_params.z);
  let blurQuality = i32(mix(6.0, 18.0, u.zoom_params.w));
  let starDensity = mix(12.0, 40.0, depth);

  let center = mouse + vec2<f32>(sin(time * 0.3) * 0.04, cos(time * 0.25) * 0.03);
  let dir = uv - center;
  let dist = length(dir);
  let dirSafe = dir / max(dist, 1e-4);
  let angle = atan2(dirSafe.y, dirSafe.x);

  var accum = vec3<f32>(0.0);
  var weightSum = 0.0;
  var dopplerSum = 0.0;

  for (var i: i32 = 0; i < blurQuality; i = i + 1) {
    let t = f32(i) / max(f32(blurQuality - 1), 1.0);
    let alcubierre = select(-0.35 * warpFactor, 0.55 * warpFactor, t > 0.5);
    let offset = dir * (0.015 + warpFactor * 0.018) * t * (1.0 + dist * 2.0 + alcubierre * dist);
    let split = dirSafe * prismSplit * t * warpFactor;
    let sampleUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    let starN = hash22(vec2<f32>(f32(i) * 7.3 + time * 0.1, angle * starDensity));
    let star = smoothstep(0.97, 0.995, starN.x) * starN.y * (0.5 + bass * 0.5);
    let streak = star * pow(max(0.0, 1.0 - t), 2.0) * coreGlow;

    let doppler = select(vec3<f32>(1.0 + warpFactor * 0.08, 1.0 - warpFactor * 0.02, 0.85 - warpFactor * 0.05),
                         vec3<f32>(0.7 - warpFactor * 0.03, 0.9, 1.0 + warpFactor * 0.06), dirSafe.x > 0.0);
    let w = mix(1.0, 0.12, t);
    accum = accum + (vec3<f32>(r, g, b) + vec3<f32>(streak)) * doppler * w;
    weightSum = weightSum + w;
    dopplerSum = dopplerSum + length(doppler - vec3<f32>(1.0)) * w;
  }

  var finalColor = accum / max(weightSum, 1e-4);
  let velocity = warpFactor * (1.0 - dist * 1.4);
  let ca = smoothstep(2.0, 8.0, velocity);
  let caShift = dirSafe * ca * 0.012;
  let caR = textureSampleLevel(readTexture, u_sampler, clamp(uv + caShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let caB = textureSampleLevel(readTexture, u_sampler, clamp(uv - caShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  finalColor = vec3<f32>(mix(finalColor.r, caR, ca), finalColor.g, mix(finalColor.b, caB, ca));

  let starburst = pow(max(0.0, 1.0 - dist * 2.0), 3.0) * (coreGlow * 0.4 + mids * 0.3);
  let tint = mix(vec3<f32>(0.15, 0.55, 1.0), vec3<f32>(1.0, 0.35, 0.7), 0.5 + 0.5 * sin(time * 0.5));
  finalColor = finalColor + tint * starburst;
  finalColor = acesToneMap(finalColor * 1.2);
  finalColor = finalColor * vignette(uv, 0.25);

  let srcAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  let dopplerMag = dopplerSum / max(weightSum, 1e-4);
  let warpIntensity = smoothstep(1.0, 10.0, warpFactor);
  let finalAlpha = clamp(warpIntensity * dopplerMag * depth + srcAlpha * 0.2 + starburst * 0.3, 0.06, 0.98);
  let outDepth = clamp(mix(depth, 0.12 + starburst * 0.75, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(dist, warpFactor * 0.1, dopplerMag, finalAlpha));
}
