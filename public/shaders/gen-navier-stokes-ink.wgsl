// ═══════════════════════════════════════════════════════════════════
//  Navier-Stokes Ink - 2D fluid simulation with ink injection
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, temporal, mouse-driven
//  Complexity: High
//  Created: 2026-05-30
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

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = step(0.5, u.zoom_config.w);

  let injectionRate = mix(0.3, 1.2, u.zoom_params.x) * (1.0 + bass * 0.5);
  let viscosity = mix(0.92, 0.65, u.zoom_params.y);
  let dispersion = u.zoom_params.z;
  let vorticityScale = u.zoom_params.w;

  let texel = 1.0 / resolution;
  let dt = 0.7;

  let c = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let vel = c.rg;

  let backUV = uv - vel * texel * dt;
  let advected = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0);
  var newVel = advected.rg;
  var newInk = advected.b;

  let mouseForce = (mouseUV - uv) * mouseDown * 4.0;
  newVel = newVel + mouseForce * dt;

  let vn = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0);
  let vs = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0);
  let ve = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0);
  let vw = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0);

  let avgVel = (vn.rg + vs.rg + ve.rg + vw.rg) * 0.25;
  newVel = mix(newVel, avgVel, 1.0 - viscosity);

  let div = (ve.r - vw.r + vn.g - vs.g) * 0.5;
  newVel.x = newVel.x - div * 0.5;
  newVel.y = newVel.y - div * 0.5;

  let source = exp(-length(uv - mouseUV) * length(uv - mouseUV) * 600.0) * mouseDown * injectionRate;
  newInk = newInk + source * dt;
  newInk = newInk * (0.992 - dispersion * 0.02);

  let curl = (ve.g - vw.g) - (vn.r - vs.r);
  let vorticity = abs(curl) * vorticityScale;

  let inkColor = vec3<f32>(0.05, 0.08, 0.2);
  let deepInk = vec3<f32>(0.02, 0.03, 0.12);
  let eddyColor = vec3<f32>(0.3, 0.5, 1.0);

  var col = mix(deepInk, inkColor, newInk * 3.0);
  col = col + eddyColor * vorticity * newInk * 2.0;
  col = col + vec3<f32>(0.6, 0.7, 1.0) * vorticity * vorticity * 0.3;

  let shear = length(newVel) * 2.0;
  let chromaR = newInk * (1.0 + shear * 0.5);
  let chromaB = newInk * (1.0 - shear * 0.3);
  col = col + vec3<f32>(chromaR * 0.15, 0.0, chromaB * 0.2) * shear;

  col = acesToneMapping(col * 1.5);

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  let alpha = clamp(newInk * depth * 1.5 + vorticity * depth * 0.3, 0.0, 0.9);

  let finalColor = mix(inputColor.rgb, col, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(newInk * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(newVel.x, newVel.y, newInk, alpha));
}
