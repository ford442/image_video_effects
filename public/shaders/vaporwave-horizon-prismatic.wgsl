// ═══════════════════════════════════════════════════════════════════
//  vaporwave-horizon-prismatic
//  Category: advanced-hybrid
//  Features: vaporwave-horizon, spectral-dispersion, physical-dispersion, mouse-driven
//  Complexity: Very High
//  Chunks From: vaporwave-horizon, spec-prismatic-dispersion
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Retro-futuristic vaporwave horizon combined with 4-band spectral
//  prismatic dispersion. The grid floor refracts light through a virtual
//  glass surface using Cauchy's equation, creating chromatic aberration
//  on the horizon reflection.
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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
  let toCenter = uv - center;
  let dist = length(toCenter);
  let lensStrength = curvature * 0.4;
  let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
  return uv + offset;
}

const SIGMA_T_ATMOSPHERE: f32 = 0.6;
const SIGMA_T_FOG: f32 = 1.2;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let gridSpeed = u.zoom_params.x;
  let glowIntensity = u.zoom_params.y;
  let gridScale = u.zoom_params.z;
  let warpAmt = u.zoom_params.w;

  let glassCurvature = mix(0.1, 1.2, u.zoom_params.x);
  let cauchyB = mix(0.01, 0.08, u.zoom_params.y);
  let glassThickness = mix(0.3, 1.5, u.zoom_params.z);
  let spectralSat = mix(0.3, 1.2, u.zoom_params.w);

  let mouse_y = u.zoom_config.z;
  let horizon = mouse_y;
  let mouse_x = u.zoom_config.y;
  let curve = (mouse_x - 0.5) * 4.0 * warpAmt;

  let lensCenter = vec2<f32>(0.5, horizon);
  var finalColor = vec3<f32>(0.0);
  var alpha = 0.0;

  if (uv.y < horizon) {
    // Sky with atmospheric haze
    let sky_uv_y = uv.y / max(horizon, 0.01);
    var sky_uv = vec2<f32>(uv.x, sky_uv_y);
    let img_color = textureSampleLevel(readTexture, u_sampler, sky_uv, 0.0).rgb;
    let gradient = smoothstep(0.0, 1.0, sky_uv_y);
    let sunset_color = vec3<f32>(0.8, 0.2, 0.5);
    let heightFactor = 1.0 - sky_uv_y;
    let opticalDepth = heightFactor * 0.5 * SIGMA_T_ATMOSPHERE;
    let transmittance = exp(-opticalDepth);
    finalColor = mix(img_color * transmittance, sunset_color, gradient * 0.3 * glowIntensity * (1.0 - transmittance));
    alpha = 0.95;
  } else {
    // Floor with prismatic dispersion
    let dy = uv.y - horizon;
    let z_depth = 1.0 / max(dy, 0.001);
    let x_offset = curve * dy * dy;
    let grid_u = (uv.x - 0.5 - x_offset) * z_depth * (0.5 + gridScale) + 0.5;
    let grid_v = z_depth * (0.5 + gridScale) + time * gridSpeed;

    let grid_x = abs(fract(grid_u) - 0.5);
    let grid_y = abs(fract(grid_v) - 0.5);
    let line_mask = step(0.45, grid_x) + step(0.45, grid_y);
    let grid_val = clamp(line_mask, 0.0, 1.0);

    // Reflection of sky with spectral dispersion
    let refl_y = horizon - dy;
    let refl_uv = vec2<f32>(uv.x, clamp(refl_y, 0.0, 1.0));

    // 4-band spectral refraction on reflection
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var reflColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
      let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
      let refractedUV = refractThroughSurface(refl_uv, lensCenter, ior, glassCurvature);
      let wrappedUV = fract(refractedUV);
      let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
      let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
      let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
      spectralResponse[i] = bandIntensity;
      reflColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    // Grid color with spectral tint
    let grid_col = vec3<f32>(0.0, 1.0, 1.0) * grid_val * glowIntensity * 2.0;
    let fade = smoothstep(0.0, 0.2, dy);
    var floor_color = mix(reflColor * 0.5, grid_col, grid_val * fade);

    // Volumetric distance fog
    let fogDensity = 0.15;
    let fogDistance = z_depth * 0.3;
    let fogOpticalDepth = fogDensity * fogDistance * SIGMA_T_FOG;
    let fogTransmittance = exp(-fogOpticalDepth);
    let fogColor = vec3<f32>(0.4, 0.1, 0.4);
    finalColor = mix(fogColor, floor_color, fogTransmittance);
    alpha = 0.8 + (1.0 - fogTransmittance) * 0.2;

    // Store spectral response
    textureStore(dataTextureA, global_id.xy, spectralResponse);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, alpha));
}
