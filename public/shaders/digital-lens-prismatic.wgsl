// ═══════════════════════════════════════════════════════════════════
//  digital-lens-prismatic
//  Category: advanced-hybrid
//  Features: mouse-driven, spectral-rendering, pixelation, physical-dispersion
//  Complexity: Very High
//  Chunks From: digital-lens.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  A digital lens that pixelates the image and refracts light
//  through a virtual glass prism. Inside the lens, each pixel block
//  undergoes 4-band spectral dispersion via Cauchy's equation.
//  The digital grid bounds the prismatic regions.
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let block_size = max(2.0, u.zoom_params.x * 50.0 + 2.0);
  let radius = u.zoom_params.y * 0.4 + 0.05;
  let grid_opacity = u.zoom_params.z;
  let cauchyB = mix(0.01, 0.08, u.zoom_params.w);

  var mouse = u.zoom_config.yz;
  let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);

  let mask = 1.0 - smoothstep(radius, radius + 0.05, dist);

  var color: vec4<f32>;

  if (mask > 0.001) {
    // Pixelate inside lens
    let blocks = resolution / block_size;
    let uv_quantized = floor(uv * blocks) / blocks + (0.5 / blocks);

    // Prismatic dispersion at pixel-block center
    let lensCenter = mouse;
    let glassCurvature = 0.8;
    let glassThickness = 0.8;
    let spectralSat = 0.9;

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
      let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
      let refractedUV = refractThroughSurface(uv_quantized, lensCenter, ior, glassCurvature);
      let wrappedUV = fract(refractedUV);
      let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
      let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
      let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
      spectralResponse[i] = bandIntensity;
      finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    finalColor = finalColor / (1.0 + finalColor * 0.3);

    // Grid lines
    let uv_pixel = uv * resolution;
    let grid_x = step(block_size - 1.0, uv_pixel.x % block_size);
    let grid_y = step(block_size - 1.0, uv_pixel.y % block_size);
    let grid_line = max(grid_x, grid_y);

    var lens_color = vec4<f32>(finalColor, spectralResponse.w);

    // Digital tint
    let tint = vec4<f32>(0.0, 1.0, 0.2, 1.0);
    lens_color = mix(lens_color, lens_color * tint * 1.5, 0.3);

    // Add grid
    lens_color = mix(lens_color, vec4<f32>(0.0, 0.0, 0.0, 1.0), grid_line * grid_opacity);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    color = mix(original, lens_color, mask);
  } else {
    color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
