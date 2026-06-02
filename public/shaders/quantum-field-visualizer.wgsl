// ═══════════════════════════════════════════════════════════════════
//  Quantum Field Visualizer v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: quantum-field-visualizer
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv_to_rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / resolution;

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let obsStrength = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let energy = u.zoom_params.z;
  let uncertainty = u.zoom_params.w * (1.0 + depth * 0.5);

  let aspect = resolution.x / max(resolution.y, 1.0);
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

  // Gaussian wave packet parameters
  let k0 = 8.0 + energy * 12.0;
  let sigma = 0.08 + uncertainty * 0.25;
  let spreadRate = 0.15 * speed;
  let t = time * (0.5 + speed * 1.5) + bass * 0.3;

  // Two-slit interference with packet spreading
  let slitA = p - vec2<f32>(-0.12, 0.0);
  let slitB = p - vec2<f32>(0.12, 0.0);
  let spread = 1.0 + spreadRate * t;

  let gaussA = exp(-dot(slitA, slitA) / (sigma * sigma * spread));
  let gaussB = exp(-dot(slitB, slitB) / (sigma * sigma * spread));

  // Real and imaginary wavefunction components
  let phaseA = k0 * slitA.x - t * 3.0;
  let phaseB = k0 * slitB.x - t * 3.0;
  let realPsi = gaussA * cos(phaseA) + gaussB * cos(phaseB);
  let imagPsi = gaussA * sin(phaseA) + gaussB * sin(phaseB);

  // Probability density and phase
  let probDensity = realPsi * realPsi + imagPsi * imagPsi;
  let phase = atan2(imagPsi, realPsi) / 6.28318;

  // Mouse measurement collapse
  let mouseVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(mouseVec);
  let measureRadius = mix(0.05, 0.4, obsStrength);
  let measureCertainty = 1.0 - smoothstep(measureRadius * 0.3, measureRadius, mouseDist);

  // Collapse localizes probability
  let collapseBoost = exp(-mouseDist * mouseDist / (measureRadius * measureRadius * 0.5));
  let collapsedProb = mix(probDensity, collapseBoost * 2.0, measureCertainty);

  // Hue from phase, saturation from contrast, brightness from probability
  let hue = fract(phase + 0.5);
  let sat = clamp(0.4 + collapsedProb * 0.6, 0.0, 1.0);
  let bri = clamp(pow(collapsedProb * 0.8, 0.7) * (1.0 + bass * 0.3), 0.0, 2.0);
  var quantumColor = hsv_to_rgb(vec3<f32>(hue, sat, min(bri, 1.0)));

  // HDR bloom on high-probability regions
  let bloom = max(bri - 1.0, 0.0) * 0.6;
  quantumColor += vec3<f32>(0.4, 0.7, 1.0) * bloom;

  // Sample base image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgba;

  // Mix quantum visualization with base image based on measurement
  let mixFactor = (1.0 - measureCertainty) * (0.3 + energy * 0.5);
  var finalColor = mix(baseColor.rgb, quantumColor, mixFactor);
  finalColor = mix(finalColor, baseColor.rgb, measureCertainty * 0.7);

  // ACES tone mapping
  finalColor = aces_tone_map(finalColor * (0.8 + energy * 0.4));

  // Alpha: Probability density * measurement certainty * depth
  let alpha = clamp(collapsedProb * 0.5 + measureCertainty * 0.3 + depth * 0.2, 0.05, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
