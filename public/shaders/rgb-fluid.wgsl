// ═══════════════════════════════════════════════════════════════════
//  RGB Fluid
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-26
//  Ideas: wavelength advection; display-only Beer-Lambert
//  A packing: linear advected pigment RGB + transmission alpha
// ═══════════════════════════════════════════════════════════════════
//  Flow velocity affects dispersion and alpha per channel.
//  Beer-Lambert: alpha = exp(-thickness * absorption).
//  Red (650nm) transmits most. Blue (450nm) absorbs most.
//  Absorption is applied on writeTexture only, so it does not compound.

#include "_prelude.wgsl"

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

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let v = max(x, vec3<f32>(0.0));
    return clamp((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, dims: vec2<i32>) -> vec3<f32> {
    let p = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(dims) - vec2<f32>(0.5);
    let base = vec2<i32>(floor(p));
    let f = fract(p);
    let hi = dims - vec2<i32>(1);
    let s00 = textureLoad(dataTextureC, clamp(base, vec2<i32>(0), hi), 0).rgb;
    let s10 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1, 0), vec2<i32>(0), hi), 0).rgb;
    let s01 = textureLoad(dataTextureC, clamp(base + vec2<i32>(0, 1), vec2<i32>(0), hi), 0).rgb;
    let s11 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1, 1), vec2<i32>(0), hi), 0).rgb;
    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
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

  // Audio: bass quickens flow, mids pushes the fluid, treble shifts color
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let flow_speed = u.zoom_params.x * 0.01 * (1.0 + bass * 0.6);
  let decay = u.zoom_params.y;
  let mouse_force = u.zoom_params.z * (1.0 + mids * 0.5);
  let color_shift = u.zoom_params.w + treble * 0.2;

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

  // ── Idea: wavelength advection ─────────────────────────────────
  // Red lags, blue leads. Color Shift scales the split. At 0 all
  // three channels share one path. History is four exact loads.
  let shift = clamp(color_shift, 0.0, 1.0);
  let advR = clamp(uv - velocity * mix(1.0, 0.82, shift), vec2<f32>(0.0), vec2<f32>(1.0));
  let advG = clamp(uv - velocity, vec2<f32>(0.0), vec2<f32>(1.0));
  let advB = clamp(uv - velocity * mix(1.0, 1.22, shift), vec2<f32>(0.0), vec2<f32>(1.0));
  let dimsI = vec2<i32>(resolution);
  let histR = historyAt(advR, dimsI);
  let histG = historyAt(advG, dimsI);
  let histB = historyAt(advB, dimsI);
  let history = vec3<f32>(histR.r, histG.g, histB.b);

  // Current input
  let inputTex = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let input = inputTex.rgb;

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
  
  // ── Idea: display-only Beer-Lambert ────────────────────────────
  // Channel transmission tints the picture. A keeps the pigment so
  // the absorption does not compound next frame.
  let absorbed = vec3<f32>(
      new_color.r * alphaR,
      new_color.g * alphaG,
      new_color.b * alphaB
  );
  let alpha = clamp(finalAlpha * 0.82 + inputTex.a * 0.18, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesFilm(absorbed), alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(new_color, alpha));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
