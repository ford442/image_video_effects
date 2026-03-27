// ═══════════════════════════════════════════════════════════════
//  RGB Fluid - Advection-based RGB flow with wavelength-alpha
//  Category: simulation
//  Features: fluid-advection, flow-dispersion, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Flow velocity affects dispersion and alpha per channel
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
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  var mouse = u.zoom_config.yz;

  // Params
  let flow_speed = u.zoom_params.x * 0.01;
  let decay = u.zoom_params.y;
  let mouse_force = u.zoom_params.z;
  let color_shift = u.zoom_params.w;

  // Generate flow field
  let scale = 5.0;
  let field_x = sin(uv.y * scale + time) + cos(uv.x * scale * 2.0);
  let field_y = cos(uv.x * scale + time) + sin(uv.y * scale * 2.0);
  var velocity = vec2<f32>(field_x, field_y) * flow_speed;

  // Mouse Repulsion
  var uv_corrected = uv;
  uv_corrected.x *= aspect;
  var mouse_corrected = mouse;
  mouse_corrected.x *= aspect;

  let dist = distance(uv_corrected, mouse_corrected);
  let to_pixel = normalize(uv_corrected - mouse_corrected);

  let push = to_pixel * smoothstep(0.4, 0.0, dist) * mouse_force * 0.05;

  if (dist > 0.001) {
    velocity += push;
  }

  // Advection
  let advect_uv = uv - velocity;
  let history = textureSampleLevel(dataTextureC, u_sampler, advect_uv, 0.0).rgb;

  // Current input
  let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Mix input into history
  let persistence = 0.9 + (decay * 0.09);
  var new_color = mix(input, history, persistence);

  // Color Shift
  if (color_shift > 0.0) {
      let shift_amt = color_shift * 0.01;
      var r = new_color.r;
      var g = new_color.g;
      var b = new_color.b;
      new_color.r = r * cos(shift_amt) - g * sin(shift_amt) + 0.001;
      new_color.g = g * cos(shift_amt) - b * sin(shift_amt) + 0.001;
      new_color.b = b * cos(shift_amt) - r * sin(shift_amt) + 0.001;
      new_color = abs(new_color);
  }

  // ═══════════════════════════════════════════════════════════════
  //  WAVELENGTH-DEPENDENT ALPHA
  //  Thickness derived from flow velocity magnitude
  // ═══════════════════════════════════════════════════════════════
  let velocityMag = length(velocity);
  let dispersionThickness = velocityMag * 100.0 + mouse_force * 0.5;
  
  let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
  
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
  
  let finalColor = vec3<f32>(
      new_color.r * alphaR,
      new_color.g * alphaG,
      new_color.b * alphaB
  );

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, finalAlpha));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
