// ═══════════════════════════════════════════════════════════════════
//  Zoom Burst v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, radial-blur, starburst, film-grain
//  Complexity: High
//  Chunks From: zoom-burst
//  Created: 2026-05-31
//  By: 4-Agent Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  let c = x * 0.85 + 0.30;
  return clamp((a / b) * c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn filmGrain(uv: vec2<f32>, t: f32) -> f32 {
  return (fract(sin(dot(uv + t, vec2<f32>(127.1, 311.7))) * 43758.5453) - 0.5) * 0.035;
}

fn starburst(uv: vec2<f32>, center: vec2<f32>, time: f32, audio: vec3<f32>) -> vec3<f32> {
  let offset = uv - center;
  let dist = length(offset);
  let dir = offset / max(dist, 1e-4);
  var rayColor = vec3<f32>(0.0);
  for (var r: i32 = 0; r < 8; r = r + 1) {
    let angle = f32(r) * 0.785398;
    let rayDir = vec2<f32>(cos(angle), sin(angle));
    let align = max(dot(dir, rayDir), 0.0);
    let ray = pow(align, 18.0) * exp(-dist * 3.5) * (0.08 + audio.y * 0.18);
    let tint = mix(vec3<f32>(0.5, 0.85, 1.0), vec3<f32>(1.0, 0.55, 0.75), sin(time * 0.7 + f32(r)) * 0.5 + 0.5);
    rayColor = rayColor + tint * ray;
  }
  return rayColor;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let center = u.zoom_config.yz;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let aspect = dims.x / dims.y;

  // Param mapping: x=BurstLength, y=SampleQuality, z=Spin, w=Chroma
  let burstLength = mix(0.01, 0.30, u.zoom_params.x) * (1.0 + audio.x * 0.6);
  let quality = i32(mix(8.0, 28.0, u.zoom_params.y));
  let spin = (u.zoom_params.z - 0.5) * 2.8;
  let chroma = mix(0.0, 0.045, u.zoom_params.w);

  // Depth controls streak length perspective
  let depthStreak = mix(0.4, 1.6, depth);
  let bassAccel = 1.0 + audio.x * 0.8;
  let adjOffset = (uv - center) * vec2<f32>(aspect, 1.0);
  let dist = length(adjOffset);
  let dir = adjOffset / max(dist, 1e-4);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let timeWarp = time * bassAccel;

  // Source for boost mixing
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let srcLum = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let srcBoost = smoothstep(0.6, 1.0, srcLum) * 0.2;

  // Radial motion blur with exponential zoom trajectory
  var accum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var i: i32 = 0; i < quality; i = i + 1) {
    let t = f32(i) / max(f32(quality - 1), 1.0);
    let radius = pow(t, 1.7) * burstLength * depthStreak * (1.0 + dist * 2.0);
    let stepVec = rotate(dir, spin * t) * radius;
    let sampleUV = clamp(uv - stepVec / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic radial dispersion
    let split = dir * chroma * t * (1.0 + dist * 2.0);
    let r = sampleColor(sampleUV + split / aspectVec).r;
    let g = sampleColor(sampleUV).g;
    let b = sampleColor(sampleUV - split / aspectVec).b;

    // Starburst ray weighting: brighter along cardinal diagonals
    let rayAngle = abs(sin(atan2(dir.y, dir.x) * 4.0));
    let w = mix(1.0, 0.2, t) * (1.0 + rayAngle * 0.5) * bassAccel;

    accum = accum + vec3<f32>(r, g, b) * w;
    weightSum = weightSum + w;
  }

  let burst = accum / max(weightSum, 1e-4);

  // HDR bloom on bright streaks
  let lum = dot(burst, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = max(lum - 0.50, 0.0) * 0.6;
  let burstColor = burst + vec3<f32>(bloom);

  // Starburst light rays
  let rays = starburst(uv, center, timeWarp, audio);
  let flare = pow(max(0.0, 1.0 - dist * 1.5), 3.0) * (0.12 + audio.y * 0.24);
  let tint = mix(vec3<f32>(0.10, 0.8, 1.0), vec3<f32>(1.0, 0.50, 0.70), 0.5 + 0.5 * sin(timeWarp * 0.8));
  let radialGlow = exp(-dist * 5.0) * 0.2 * bassAccel;

  var finalColor = burstColor + rays + tint * flare + radialGlow + srcBoost;
  finalColor = mix(src.rgb, finalColor, 0.82);

  // Film grain and ACES tone mapping
  let grain = filmGrain(uv, time);
  finalColor = acesToneMap(finalColor + grain);

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.85, dist) * 0.25;
  finalColor = finalColor * vignette;

  let burstIntensity = clamp(length(burst) * 0.5, 0.0, 1.0);
  let radialDispersion = 1.0 + chroma * 4.0;
  let finalAlpha = clamp(burstIntensity * radialDispersion * depth, 0.08, 0.98);
  let outDepth = clamp(mix(depth, 0.2 + burstIntensity * 0.6, 0.2), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(dist, burstLength * 8.0, flare, finalAlpha));
}
