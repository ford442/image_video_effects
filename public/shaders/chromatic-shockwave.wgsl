// ═══════════════════════════════════════════════════════════════
//  Chromatic Shockwave - Wave-based chromatic aberration with wavelength-alpha
//  Category: distortion
//  Features: shockwave, chromatic-dispersion, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Shockwave dispersion affects both position AND alpha per channel
//  - Beer-Lambert law: alpha = exp(-thickness * absorption)
//  - Red (650nm): lowest absorption, highest transmission
//  - Blue (450nm): highest absorption, lowest transmission
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

// ═══════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;  // nm
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  var mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Params
  let speed = u.zoom_params.x * 10.0;
  let freq = 10.0 + u.zoom_params.y * 50.0;
  let aberr = u.zoom_params.z * 0.1;

  let diff = uv - mouse;
  let distSq = dot(diff, diff);

  var dir = vec2<f32>(1.0, 0.0);
  if (distSq > 0.000001) {
    dir = normalize(diff);
  }

  let dist = sqrt(dot(diff * vec2<f32>(aspect, 1.0), diff * vec2<f32>(aspect, 1.0)));

  // Wave function
  let wave = sin(dist * freq - time * speed);

  // Chromatic Aberration Offsets
  let offsetR = dir * wave * aberr;
  let offsetB = -dir * wave * aberr;
  let offsetG = dir * wave * aberr * 0.3;

  let r = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

  // ═══════════════════════════════════════════════════════════════
  //  WAVELENGTH-DEPENDENT ALPHA
  //  Thickness derived from wave amplitude
  // ═══════════════════════════════════════════════════════════════
  let waveThickness = abs(wave) * aberr * 10.0;
  let dispersionThickness = waveThickness + dist * 0.5;
  
  let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
  
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
  
  let finalColor = vec3<f32>(
      r * alphaR,
      g * alphaG,
      b * alphaB
  );

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
}
