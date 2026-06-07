// ================================================================
//  Glass Brick Wall
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Chunks From: glass-brick-wall
//  Created: 2026-05-31
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=BrickSize, y=Distortion, z=MortarSize, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

fn safeNormalize3(v: vec3<f32>) -> vec3<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let brickSize = mix(10.0, 54.0, u.zoom_params.x);
  let distortion = mix(0.0, 0.12, u.zoom_params.y);
  let mortarSize = mix(0.01, 0.12, u.zoom_params.z);
  let glassDensity = mix(0.6, 2.6, u.zoom_params.w);

  let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
  let cellId = floor(gridUV);
  let cell = fract(gridUV) - 0.5;
  let r2 = dot(cell, cell) * 4.0;

  let normalXY = cell * -2.0;
  let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
  let normal = safeNormalize3(vec3<f32>(normalXY, normalZ));
  let mortarMask = smoothstep(0.48 - mortarSize, 0.5, max(abs(cell.x), abs(cell.y)));

  let refractOffset = normal.xy * distortion * (1.0 - mortarMask) * (1.0 + audio.x * 0.35);
  let finalUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  let lightPos = vec3<f32>(mouse * vec2<f32>(aspect, 1.0), 0.55);
  let pixelPos = vec3<f32>(uv * vec2<f32>(aspect, 1.0), 0.0);
  let lightDir = safeNormalize3(lightPos - pixelPos);
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = safeNormalize3(lightDir + viewDir);

  var transmission = 0.45;
  if (mortarMask < 0.5) {
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let fresnel = 0.04 + (1.0 - 0.04) * pow(1.0 - cosTheta, 5.0);
    let thickness = 0.08 + r2 * 0.16;
    let glassTint = mix(vec3<f32>(0.94, 0.97, 1.0), vec3<f32>(0.98, 0.85, 1.0), 0.5 + 0.5 * sin(time * 0.35 + cellId.x * 0.4));
    let absorption = exp(-(1.0 - glassTint) * thickness * glassDensity);
    transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    let specular = pow(max(dot(normal, halfDir), 0.0), 18.0) * (0.22 + audio.y * 0.45);
    let refLight = refract(-lightDir, normal, 1.0 / 1.52);
    let focal = pow(max(refLight.z, 0.0), 6.0);
    let curvature = smoothstep(0.0, 0.6, r2);
    let phase = sin(r2 * 22.0 - time * (2.0 + audio.x * 2.0) + cellId.x * 1.3 + cellId.y * 0.7);
    let caustic = focal * (0.5 + 0.5 * phase) * (0.35 + curvature * 0.85) * (1.0 + audio.z * 0.5);
    let causticColor = vec3<f32>(1.0, 0.9, 0.7) + vec3<f32>(-0.2, 0.0, 0.4) * phase;

    color = vec4<f32>(color.rgb * glassTint * transmission + specular + causticColor * caustic * 1.2, transmission);
  } else {
    color = vec4<f32>(color.rgb * 0.42, 0.42);
  }

  let finalAlpha = clamp(color.a + (1.0 - mortarMask) * 0.10, 0.15, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
  let outDepth = clamp(mix(baseDepth, baseDepth * 0.45 + (1.0 - mortarMask) * 0.45, 0.25), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color.rgb, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(1.0 - mortarMask, transmission, abs(refractOffset.x) + abs(refractOffset.y), finalAlpha));
}
