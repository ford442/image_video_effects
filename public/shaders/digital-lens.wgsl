// ═══════════════════════════════════════════════════════════════════
//  Digital Lens v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            barrel-distortion, chromatic-dispersion, anamorphic
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-05-30
//  Chunks From: brown-conrady, aces-tonemap, film-grain
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = fract(p * vec2<f32>(0.1031, 0.1030));
  pp = pp + dot(pp, pp.yx + 33.33);
  return fract((pp.xx + pp.yx) * vec2<f32>(0.437585, 0.237585));
}

// Brown-Conrady lens distortion model
fn brownConrady(p: vec2<f32>, k1: f32, k2: f32, p1: f32, p2: f32) -> vec2<f32> {
  let r2 = dot(p, p);
  let r4 = r2 * r2;
  let radial = 1.0 + k1 * r2 + k2 * r4;
  let tangentialX = 2.0 * p1 * p.x * p.y + p2 * (r2 + 2.0 * p.x * p.x);
  let tangentialY = p1 * (r2 + 2.0 * p.y * p.y) + 2.0 * p2 * p.x * p.y;
  return vec2<f32>(p.x * radial + tangentialX, p.y * radial + tangentialY);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Bass drives lens breathing amplitude
  let breathe = bass * u.zoom_params.w * 0.3;
  let k1 = (u.zoom_params.x - 0.5) * 2.0 * (1.0 + breathe);
  let k2 = k1 * k1 * 0.5;
  let dispersion = u.zoom_params.y * 0.04 * (1.0 + mids * 0.8);
  let anamorphicSqueeze = u.zoom_params.z;

  // Mouse controls focus point
  let focusPoint = u.zoom_config.yz;
  let focusOffset = (focusPoint - 0.5) * 0.06;

  // Depth controls chromatic separation
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthSep = (1.0 - depth) * 0.5 + 0.5;

  // Centered normalized coords
  let center = vec2<f32>(0.5, 0.5);
  var p = (uv - center) * vec2<f32>(aspect, 1.0);

  // Anamorphic squeeze
  p.x = p.x * (1.0 + anamorphicSqueeze * 0.3);

  // Apply Brown-Conrady distortion
  let distortedP = brownConrady(p, k1, k2, k1 * 0.05, k1 * 0.03);
  let sampleCenter = center + distortedP / vec2<f32>(aspect, 1.0) + focusOffset;

  // Chromatic aberration per RGB channel with different refractive indices
  let r = length(p);
  let radial = select(vec2<f32>(0.0), p / max(r, 0.0001), r > 0.0001);
  let radialUV = radial / vec2<f32>(aspect, 1.0);

  let rDisp = dispersion * 1.4 * depthSep * (1.0 + r * 1.5);
  let gDisp = dispersion * 0.7 * depthSep * r;
  let bDisp = dispersion * 1.1 * depthSep * (1.0 + r * 0.8);

  let rUV = clamp(sampleCenter + radialUV * rDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(sampleCenter + radialUV * gDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(sampleCenter - radialUV * bDisp, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  // Film grain
  let grain = hash22(uv * 800.0 + time * 60.0).x - 0.5;
  color += grain * 0.03 * (1.0 + treble * 0.5);

  // ACES tone mapping
  color = acesToneMap(color * 1.1);

  // Alpha: distortion_strength × chromatic_separation × depth
  let distStrength = abs(k1) * 0.5 + 0.3;
  let chromSep = dispersion * depthSep * 2.0;
  let alpha = clamp(distStrength * chromSep * (0.3 + depth * 0.7), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
