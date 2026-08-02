// ═══════════════════════════════════════════════════════════════
//  RGB Delay Brush - Temporal RGB splitting with stylized wavelength-alpha
//  Category: interactive-mouse
//  Features: brush, temporal-delay, wavelength-dependent-alpha
//
//  MODEL SCOPE: art-directed Beer-Lambert-inspired channel absorption. The
//  wavelength constants organize the RGB response but are not a calibrated
//  optical-material simulation.
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

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
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / u.config.w;

  let time = u.config.x;
  let rawMouse = u.zoom_config.yz;

  // Weighted brush tracking in persistent-safe state slots [133..138].
  let hasSpringState = arrayLength(&extraBuffer) > 138u;
  var mouse = rawMouse;
  if (hasSpringState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
    var springPos = mouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 7.5;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Params
  let persistence = u.zoom_params.x;
  let split = u.zoom_params.y;
  let radius = u.zoom_params.z * 0.5;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Calculate Brush Mask
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = length(uv_corrected - mouse_corrected);

  let safeRadius = max(radius, 0.001);
  let mouseMask = smoothstep(safeRadius, safeRadius * 0.5, dist) * (1.0 + u.zoom_config.w * 0.15);

  // Click stamps create independent, fading temporal-delay brushes.
  var clickMask = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.7, age));
    let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    let stampRadius = safeRadius * (0.8 + safeAge * 0.35);
    let stamp = smoothstep(stampRadius, stampRadius * 0.55, rd) * exp(-safeAge * 1.3) * live;
    clickMask = max(clickMask, stamp);
  }
  let mask = clamp(max(mouseMask, clickMask), 0.0, 1.0);

  // Calculate reaction speeds for each channel
  let base_speed = (1.0 - persistence) * 2.0;

  // Apply RGB split based on mask
  let redVoice = plasmaBuffer[2].x;
  let greenVoice = plasmaBuffer[4].x;
  let blueVoice = plasmaBuffer[7].x;
  let s_r = base_speed * (1.0 + redVoice * 0.12);
  let s_g = max(0.005, base_speed - (mask * split * 0.05)) * (1.0 + greenVoice * 0.10);
  let s_b = max(0.001, base_speed - (mask * split * 0.1)) * (1.0 + blueVoice * 0.08);

  var new_color = vec4<f32>(0.0);
  new_color.r = mix(prev.r, current.r, clamp(s_r, 0.0, 1.0));
  new_color.g = mix(prev.g, current.g, clamp(s_g, 0.0, 1.0));
  new_color.b = mix(prev.b, current.b, clamp(s_b, 0.0, 1.0));

  // ═══════════════════════════════════════════════════════════════
  //  WAVELENGTH-DEPENDENT ALPHA
  //  Thickness derived from temporal split (delay) amount
  // ═══════════════════════════════════════════════════════════════
  let temporalThickness = mask * split * mix(1.0, 10.0, u.zoom_params.w);
  
  let alphaR = calculateChannelAlpha(temporalThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(temporalThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(temporalThickness, WAVELENGTH_BLUE);
  
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
  
  new_color.r = new_color.r * alphaR;
  new_color.g = new_color.g * alphaG;
  new_color.b = new_color.b * alphaB;
  new_color.a = finalAlpha;

  textureStore(dataTextureA, coord, new_color);
  textureStore(writeTexture, coord, new_color);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
