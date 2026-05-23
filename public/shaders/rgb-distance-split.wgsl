// ═══════════════════════════════════════════════════════════════════
//  RGB Distance Split
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//
//  Distance-based RGB separation with wavelength-dependent Beer-Lambert alpha.
//  Red (650nm): lowest absorption; Blue (450nm): highest absorption.
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
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
  var uv = vec2<f32>(global_id.xy) / resolution;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  var mousePos = u.zoom_config.yz;

  // Bass widens the chromatic split; mids rotate the dispersion angle
  let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.5);
  let angleOffset = u.zoom_params.y * 6.28 + mids * 0.5;
  let blur = u.zoom_params.z;
  let deadzone = u.zoom_params.w;

  // Calculate vector from mouse to current pixel
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Direction
  var dir = vec2<f32>(0.0, 0.0);
  if (dist > 0.001) {
      dir = normalize(dVec);
  }

  // Calculate separation amount based on distance
  let effectFactor = smoothstep(deadzone, 1.0, dist);

  let separation = dir * strength * effectFactor;

  // Rotate separation vector by angleOffset
  let c = cos(angleOffset);
  let s = sin(angleOffset);
  let rotSeparation = vec2<f32>(
      separation.x * c - separation.y * s,
      separation.x * s + separation.y * c
  );

  // Sample
  let rUV = clamp(uv + rotSeparation, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = uv;
  let bUV = clamp(uv - rotSeparation, vec2<f32>(0.0), vec2<f32>(1.0));

  var r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  // Branchless blur: apply only when blur param is active
  let bOffset = rotSeparation * blur * 0.5;
  let doBlur = select(0.0, 1.0, blur > 0.0);
  r = mix(r, (r + textureSampleLevel(readTexture, u_sampler, rUV + bOffset, 0.0).r) * 0.5, doBlur);
  g = mix(g, (g + textureSampleLevel(readTexture, u_sampler, gUV + bOffset, 0.0).g) * 0.5, doBlur);
  b = mix(b, (b + textureSampleLevel(readTexture, u_sampler, bUV + bOffset, 0.0).b) * 0.5, doBlur);

  // ═══════════════════════════════════════════════════════════════
  //  WAVELENGTH-DEPENDENT ALPHA
  //  Thickness derived from separation distance
  // ═══════════════════════════════════════════════════════════════
  let separationLength = length(rotSeparation);
  let dispersionThickness = separationLength * 20.0 + effectFactor * 2.0;
  
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

  let finalOut = vec4<f32>(finalColor, clamp(finalAlpha, 0.0, 1.0));
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
