// ═══════════════════════════════════════════════════════════════════
//  Holographic Interference v2
//  Category: generative
//  Features: generative, laser-interference, speckle, depth-aware, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: holographic_interference, interference-sim, aces-tonemap
//  Upgraded: 2026-05-31
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

const PI: f32 = 3.14159265358979323846;

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

fn speckleNoise(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let h1 = hash12(p);
  let h2 = hash12(p + vec2(53.1, 17.3));
  return h1 * h2 * 2.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let filmThickness = u.zoom_params.x * 2.5 + 0.2;
  let waveScale = u.zoom_params.y * 5.0 + 0.8;
  let depthWeight = u.zoom_params.z;
  let chromaAberr = u.zoom_params.w * 0.025;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.25, 1.0, depth);

  // Virtual object controlled by mouse, with depth parallax
  let objectPos = mouse * 2.0 - 1.0;
  let aspect = resolution.x / resolution.y;
  let aspectUV = (uv - 0.5) * vec2(aspect, 1.0);
  let objDist = length(aspectUV - objectPos * 0.4);

  // Reference beam angle modulated by bass
  let refAngle = (0.25 + bass * 0.25) * PI;
  let k = waveScale * 25.0;

  // Multi-source laser interference with object and reference beams
  var interference = 0.0;
  var speckleCoherence = 0.0;
  let sourceCount = 3;
  for (var i = 0; i < sourceCount; i = i + 1) {
    let fi = f32(i);
    let srcAngle = fi * PI * 0.67 + time * 0.12;
    let srcPos = vec2(cos(srcAngle) * 0.35, sin(srcAngle) * 0.35);
    // Object beam: spherical wave from virtual object
    let objPath = sqrt(objDist * objDist + filmThickness * filmThickness);
    let objPhase = k * objPath;
    // Reference beam: planar wavefront at angle
    let refPath = (aspectUV.x - srcPos.x) * cos(refAngle + fi * 0.15) + (aspectUV.y - srcPos.y) * sin(refAngle + fi * 0.15);
    let refPhase = k * refPath;
    // Phase accumulation from interference
    let phaseAccum = objPhase - refPhase + time * 0.3;
    interference = interference + cos(phaseAccum);
    // Speckle from coherent source interference
    speckleCoherence = speckleCoherence + speckleNoise(uv + fi * 4.1, 600.0 + fi * 300.0);
  }
  interference = interference / f32(sourceCount);
  speckleCoherence = speckleCoherence / f32(sourceCount);

  // Interference contrast envelope
  let contrast = 0.5 + 0.5 * interference;

  // Chromatic dispersion: different wavelengths have different fringe spacing
  let rPhase = contrast * (1.0 + chromaAberr) * 12.0;
  let gPhase = contrast * 12.0;
  let bPhase = contrast * (1.0 - chromaAberr) * 12.0;
  let rFringe = cos(rPhase + time * 0.2) * 0.5 + 0.5;
  let gFringe = cos(gPhase + time * 0.15) * 0.5 + 0.5;
  let bFringe = cos(bPhase + time * 0.25) * 0.5 + 0.5;

  var color = vec3(rFringe, gFringe, bFringe) * (0.6 + contrast * 0.8);

  // Speckle pattern modulates amplitude
  color = color * (0.65 + speckleCoherence * 0.5);

  // HDR bloom on constructive interference zones
  let construct = smoothstep(0.65, 0.95, contrast);
  color = color + vec3(construct * 0.5, construct * 0.35, construct * 0.55) * (1.0 + bass * 0.5);

  // ACES tone mapping
  color = aces(color * 1.25);

  // Depth-scaled holographic parallax attenuation
  let parallaxAtten = mix(0.4, 1.0, depthFactor);
  color = color * parallaxAtten;

  // Alpha: interference_contrast * speckle_coherence * depth
  let alpha = clamp(contrast * speckleCoherence * depthFactor, 0.03, 0.94);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4(color, alpha));
}
