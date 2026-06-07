// ═══════════════════════════════════════════════════════════════════
//  Voxel Depth Sort v2
//  Category: image
//  Features: audio-reactive, depth-aware, isometric-voxel, ao-shadows,
//            chromatic-subsurface, aces-tone-map
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelCoord = vec2<f32>(global_id.xy);
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;

  let blockPixels = 4.0 + u.zoom_params.x * 48.0;
  let extrusion = u.zoom_params.y;
  let bgDarken = u.zoom_params.z;
  let blockGap = u.zoom_params.w;

  let isoRot = (mouse.x - 0.5) * 1.2;
  let isoTilt = (mouse.y - 0.5) * 0.8;

  let cell = floor(pixelCoord / blockPixels);
  let local = fract(pixelCoord / blockPixels) - 0.5;
  let blockCenter = (cell + 0.5) * blockPixels;
  let blockUV = clamp(blockCenter / resolution, vec2<f32>(0.0), vec2<f32>(1.0));

  let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, blockUV, 0.0).r;
  let shiftedUV = clamp(blockUV + vec2<f32>(0.0, -(sourceDepth + bass * 0.15) * extrusion * 0.14), vec2<f32>(0.0), vec2<f32>(1.0));
  let blockColor = textureSampleLevel(readTexture, u_sampler, shiftedUV, 0.0).rgb;
  let luma = luminance(blockColor);
  let column = clamp(max(luma, sourceDepth), 0.0, 1.0);

  let rotLocal = vec2<f32>(
    local.x * cos(isoRot) - local.y * sin(isoRot),
    local.x * sin(isoRot) + local.y * cos(isoRot)
  );
  let perspective = 1.0 - isoTilt * 0.3;
  let projLocal = vec2<f32>(rotLocal.x * aspect * perspective, rotLocal.y * perspective);

  let inset = max(abs(projLocal.x), abs(projLocal.y));
  let topMask = 1.0 - smoothstep(0.5 - blockGap * 0.45, 0.5, inset);
  let shadowMask = (1.0 - topMask) * (0.35 + bgDarken * 0.45);

  let ao = 1.0 - smoothstep(0.2, 0.5, inset) * 0.35 * topMask;
  let softShadow = smoothstep(0.0, 0.5, sourceDepth) * 0.25 * topMask;

  let rim = smoothstep(0.30, 0.48, inset) * topMask;
  let spectral = mix(
    vec3<f32>(0.16, 0.60, 1.0),
    vec3<f32>(1.0, 0.45, 0.20),
    bass * 0.5 + audio.z * 0.25
  );

  let sss = vec3<f32>(0.25, 0.55, 0.90) * column * topMask * (0.15 + bass * 0.15);

  var backgroundColor = mix(blockColor * (1.0 - bgDarken * 0.80), vec3<f32>(0.02, 0.03, 0.05), bgDarken * 0.70);
  backgroundColor = backgroundColor * (1.0 - shadowMask);

  var topColor = blockColor * (0.65 + 0.60 * column) * ao;
  topColor = topColor + spectral * rim * (0.14 + audio.y * 0.24 + bass * 0.18);
  topColor = topColor + vec3<f32>(0.08, 0.10, 0.14) * extrusion * (1.0 + bass * 0.2);
  topColor = topColor + sss + softShadow;
  topColor = aces_tonemap(topColor);

  let finalColor = mix(backgroundColor, topColor, topMask);
  let depthConf = clamp(sourceDepth + column * 0.3, 0.0, 1.0);
  let occlusion = shadowMask * 0.5 + (1.0 - ao) * 0.3;
  let finalAlpha = clamp(depthConf * (1.0 - occlusion) * (0.5 + topMask * 0.45), 0.25, 0.98);
  let depthOut = clamp(mix(sourceDepth * (1.0 - bgDarken * 0.50), min(1.0, column + extrusion * 0.60 + bass * 0.12), topMask), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(luma, topMask, depthConf, finalAlpha));
}
