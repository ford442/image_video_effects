// ═══════════════════════════════════════════════════════════════════
//  Digital Lens — Batch D Upgrade
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, barrel-distortion,
//            chromatic-dispersion, vignette
//  Complexity: Medium
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * vec2<f32>(0.1031, 0.1030);
  let a = dot(pp, vec2<f32>(127.1, 311.7));
  let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
  let c = sin(vec2<f32>(a, b));
  return fract(c * 43758.5453 + pp);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;

  // Parameters
  let k1 = (u.zoom_params.x - 0.5) * 2.0 * (1.0 + bass * 0.3);
  let dispersion = u.zoom_params.y * 0.04;
  let vignetteStrength = u.zoom_params.z;
  let focusPoint = u.zoom_params.w;

  // Normalized centered coords with aspect correction
  let center = vec2<f32>(0.5, 0.5);
  let p = (uv - center) * vec2<f32>(aspect, 1.0);
  let r = length(p);
  let r2 = r * r;
  let r4 = r2 * r2;

  // Barrel / pincushion distortion
  let distortionFactor = 1.0 + k1 * r2 + k1 * k1 * r4 * 0.5;
  let distortedP = p * distortionFactor;

  // Focus point shifts the distortion center slightly
  let focusOffset = (vec2<f32>(u.zoom_config.yz) - 0.5) * focusPoint * 0.1;
  let sampleCenter = center + distortedP / vec2<f32>(aspect, 1.0) + focusOffset;

  // Spectral chromatic dispersion: 3-sample RGB split along radial direction
  let radial = select(vec2<f32>(0.0), p / max(r, 0.0001), r > 0.0001);
  let radialUV = radial / vec2<f32>(aspect, 1.0);

  let rUV = sampleCenter + radialUV * dispersion * (1.0 + r * 2.0);
  let gUV = sampleCenter + radialUV * dispersion * 0.5 * r;
  let bUV = sampleCenter - radialUV * dispersion * (1.0 + r * 1.5);

  let rCol = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(rCol, gCol, bCol);

  // Vignette: darkens + alpha reduces at edges
  let edgeDist = length(uv - 0.5);
  let vignette = 1.0 - smoothstep(0.3, 0.7, edgeDist) * vignetteStrength;
  color = color * vignette;

  let alpha = mix(0.6, 1.0, vignette);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
