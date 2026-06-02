// ═══════════════════════════════════════════════════════════════════
//  Ink Diffusion v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal-ink-spread, organic-growth,
//            upgraded-rgba, navier-stokes, vorticity-confinement, surface-tension
//  Complexity: Very High
//  Chunks From: ink-diffusion.wgsl v1
//  Created: 2026-05-31
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
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn curlNoise(uv: vec2<f32>, time: f32) -> vec2<f32> {
  let eps = 0.01;
  let n = hash21(uv * 30.0 + time * 0.3);
  let nx = hash21((uv + vec2<f32>(eps, 0.0)) * 30.0 + time * 0.3);
  let ny = hash21((uv + vec2<f32>(0.0, eps)) * 30.0 + time * 0.3);
  return vec2<f32>(-(ny - n) / eps, (nx - n) / eps);
}

fn sampleInk(uv: vec2<f32>, px: vec2<f32>) -> f32 {
  return textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
}

fn paperFiber(uv: vec2<f32>) -> f32 {
  let f1 = hash21(uv * 200.0);
  let f2 = hash21(uv * 500.0 + vec2<f32>(13.7));
  return 0.94 + (f1 - 0.5) * 0.04 + (f2 - 0.5) * 0.02;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let spreadRate = u.zoom_params.x * 0.015;
  let decay = 0.9 + u.zoom_params.y * 0.08;
  let turbulence = u.zoom_params.z;
  let inkDensity = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let diffusionCoeff = spreadRate * (1.0 + (1.0 - depth) * 0.5);

  let px = 1.0 / resolution;
  let coord = vec2<i32>(global_id.xy);

  let prevInk = sampleInk(uv, px);

  let e = sampleInk(uv + vec2<f32>(px.x, 0.0), px);
  let w = sampleInk(uv - vec2<f32>(px.x, 0.0), px);
  let n = sampleInk(uv + vec2<f32>(0.0, px.y), px);
  let s_ = sampleInk(uv - vec2<f32>(0.0, px.y), px);
  let laplacian = (e + w + n + s_) * 0.25 - prevInk;

  let vel = curlNoise(uv, time) * turbulence * (1.0 + bass * 0.4);
  let advUV = uv - vel * px * 2.0;
  let advected = sampleInk(advUV, px);

  let vorticity = ((e - w) - (n - s_)) * 0.5;
  let vortForce = vec2<f32>(abs(n - s_), abs(e - w)) * sign(vorticity) * turbulence * 0.3;
  let vortUV = uv + vortForce * px;
  let vortInk = sampleInk(vortUV, px);

  let diffused = mix(prevInk, advected * 0.7 + vortInk * 0.3, diffusionCoeff);
  let diffused2 = diffused + laplacian * diffusionCoeff * 0.5;

  let dist = length(uv - mousePos);
  let brush = smoothstep(0.12, 0.0, dist) * mouseDown * inkDensity;
  let pellet = smoothstep(0.04, 0.0, dist) * mouseDown * inkDensity * 2.0;

  let splatter = hash21(uv * 120.0 + time * 15.0) * bass * 0.25 * turbulence;
  let injection = bass * 0.08 * turbulence * inkDensity;

  var newInk = clamp(diffused2 * decay + brush + pellet + splatter + injection, 0.0, 1.0);

  let gradX = e - w;
  let gradY = n - s_;
  let gradMag = sqrt(gradX * gradX + gradY * gradY);
  let surfaceTension = smoothstep(0.05, 0.2, gradMag) * (1.0 - smoothstep(0.2, 0.5, gradMag));
  newInk = newInk + surfaceTension * 0.03 * (1.0 - depth);

  let paperBase = vec3<f32>(0.94, 0.92, 0.88);
  let fiber = paperFiber(uv);
  let paperColor = paperBase * fiber;

  let inkColor = vec3<f32>(0.04, 0.04, 0.07) + vec3<f32>(0.03, 0.0, 0.04) * mids;
  let wetInk = inkColor + vec3<f32>(0.01, 0.01, 0.02) * bass;

  let wetEdge = smoothstep(0.08, 0.25, newInk) * (1.0 - smoothstep(0.25, 0.55, newInk));
  let edgeDarken = vec3<f32>(0.06) * wetEdge;

  let specAngle = sin(time * 2.0 + uv.x * 20.0) * 0.5 + 0.5;
  let wetSpec = vec3<f32>(0.08, 0.09, 0.1) * wetEdge * specAngle * (1.0 + bass * 0.5);

  var finalRGB = mix(paperColor, wetInk, newInk) - edgeDarken + wetSpec;

  let chromEdge = vec3<f32>(0.02, 0.0, -0.02) * wetEdge * mids;
  finalRGB = finalRGB + chromEdge;

  finalRGB = acesToneMap(finalRGB * 1.1);

  let waterClarity = 1.0 - newInk * 0.7;
  let alpha = clamp(newInk * (1.0 - waterClarity) * depth + newInk * 0.15 + bass * 0.03, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(newInk, vel.x, vel.y, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(newInk, 0.0, 0.0, 0.0));
}
