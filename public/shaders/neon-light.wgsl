// ═══════════════════════════════════════════════════════════════
//  Neon Light - Interactive Edge Glow with Alpha Emission
//  Category: lighting-effects
//  Physics: Emissive edge glow with mouse light falloff
//  Alpha: Core edge = 0.3, Glow = 0.0 (additive)
// ═══════════════════════════════════════════════════════════════

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

// Inverse square law for physical light falloff
fn inverseSquareFalloff(dist: f32, maxDist: f32) -> f32 {
    let d = max(dist, 0.001);
    return 1.0 / (1.0 + d * d * 4.0) * smoothstep(maxDist, 0.0, dist);
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Parameters
  // x: edgeThreshold, y: lightRadius, z: glowIntensity, w: occlusionBalance
  let edgeThreshold = u.zoom_params.x;
  let lightRadius = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z;
  let colorCycle = u.zoom_params.w;
  let occlusionBalance = 0.5; // Fixed for this shader

  // Mouse Position
  var mousePos = u.zoom_config.yz;

  // Aspect Ratio Correction for distance
  let aspect = resolution.x / resolution.y;
  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);

  // Sobel Edge Detection
  let texelSize = 1.0 / resolution;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb;

  let lum = vec3<f32>(0.299, 0.587, 0.114);
  let gx = dot(r - l, lum);
  let gy = dot(b - t, lum);
  let edge = sqrt(gx*gx + gy*gy);

  // Threshold
  let isEdge = smoothstep(edgeThreshold, edgeThreshold + 0.05, edge);

  // Light falloff with inverse square law
  let light = inverseSquareFalloff(dist, lightRadius);

  // Edge Color - Rainbow cycle based on time/colorCycle param + angle
  let angle = atan2(distVec.y, distVec.x);
  let hue = u.config.x * colorCycle + angle * 0.5;
  let rgb = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
  );

  // Emission calculation - HDR capable
  let edgeGlow = rgb * isEdge * glowIntensity * 2.0 * (light + 0.2);

  // Calculate alpha based on emission intensity
  let emissionStrength = length(edgeGlow);
  let finalAlpha = calculateEmissiveAlpha(emissionStrength, occlusionBalance);

  // Output RGBA: RGB = emission (HDR), A = physical occlusion
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(edgeGlow, finalAlpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
