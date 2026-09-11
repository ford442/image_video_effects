// ═══════════════════════════════════════════════════════════════════
//  RGB Delay Brush
//  Category: interactive-mouse
//  Features: mouse-driven, click-reactive, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: bristle along stroke; wet C trail
//  A packing: delayed RGB (C is previous delayed color)
// ═══════════════════════════════════════════════════════════════════

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
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

const WAVELENGTH_RED:    f32 = 650.0;
const WAVELENGTH_GREEN:  f32 = 550.0;
const WAVELENGTH_BLUE:   f32 = 450.0;

fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / max(u.config.w, 1.0);
  let time = u.config.x;
  let rawMouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let hasSpringState = arrayLength(&extraBuffer) > 138u;
  var mouse = rawMouse;
  var springVel = vec2<f32>(0.0);
  if (hasSpringState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
    var springPos = mouse;
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

  let persistence = u.zoom_params.x;
  let split = u.zoom_params.y;
  let radius = u.zoom_params.z * 0.5;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let prev = textureLoad(dataTextureC, coord, 0);

  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = length(uv_corrected - mouse_corrected);
  let safeRadius = max(radius, 0.001);
  let mouseMask = smoothstep(safeRadius, safeRadius * 0.5, dist) * (1.0 + u.zoom_config.w * 0.15);

  var clickMask = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
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

  // Idea 1 — bristle along stroke (offset C perpendicular to spring vel).
  let velLen = max(length(springVel), 0.0001);
  let tangent = vec2<f32>(-springVel.y, springVel.x) / velLen;
  let bristleUV = clamp(uv + tangent * (0.006 + split * 0.008) * mask, vec2<f32>(0.0), vec2<f32>(1.0));
  let bristleCoord = clamp(vec2<i32>(bristleUV * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
  let bristle = textureLoad(dataTextureC, bristleCoord, 0);
  // Idea 2 — wet C trail under the mask.
  let wet = mix(prev, bristle, 0.35 * mask);

  let base_speed = (1.0 - persistence) * 2.0;
  let redVoice = plasmaBuffer[2].x;
  let greenVoice = plasmaBuffer[4].x;
  let blueVoice = plasmaBuffer[7].x;
  let s_r = base_speed * (1.0 + redVoice * 0.12);
  let s_g = max(0.005, base_speed - (mask * split * 0.05)) * (1.0 + greenVoice * 0.10);
  let s_b = max(0.001, base_speed - (mask * split * 0.1)) * (1.0 + blueVoice * 0.08);

  var delayed = vec3<f32>(
    mix(wet.r, current.r, clamp(s_r, 0.0, 1.0)),
    mix(wet.g, current.g, clamp(s_g, 0.0, 1.0)),
    mix(wet.b, current.b, clamp(s_b, 0.0, 1.0))
  );

  let temporalThickness = mask * split * mix(1.0, 10.0, u.zoom_params.w);
  let alphaR = calculateChannelAlpha(temporalThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(temporalThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(temporalThickness, WAVELENGTH_BLUE);
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  let finalAlpha = clamp(dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights) + mask * 0.15 + bass * 0.05, 0.0, 1.0);

  delayed *= vec3<f32>(alphaR, alphaG, alphaB);
  textureStore(dataTextureA, coord, vec4<f32>(delayed, finalAlpha));
  textureStore(writeTexture, coord, vec4<f32>(aces(max(delayed, vec3<f32>(0.0))), finalAlpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
