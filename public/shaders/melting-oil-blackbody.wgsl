// ═══════════════════════════════════════════════════════════════════
//  melting-oil-blackbody
//  Category: advanced-hybrid
//  Features: melting-oil, blackbody-radiation, HDR, gradient-flow
//  Complexity: High
//  Chunks From: melting-oil.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Oil paint melts along Sobel gradient flows while its luminance
//  is mapped to blackbody temperature, creating physically-based
//  thermal colors that flow like heated liquid metal.
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

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
  let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
  var r: f32;
  var g: f32;
  var b: f32;
  if (t <= 6.5) {
    r = 1.0;
    g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
    b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
  } else {
    r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
    g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
    b = 1.0;
  }
  let radiance = pow(t / 6.5, 4.0);
  return vec3<f32>(r, g, b) * radiance;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let id = vec2<u32>(global_id.xy);
  let coord = vec2<i32>(i32(id.x), i32(id.y));
  let dim = textureDimensions(readTexture);
  var uv = vec2<f32>(f32(id.x), f32(id.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;

  let viscosity = mix(0.85, 0.99, u.zoom_params.x);
  let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.y);
  let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.y);
  let thermalIntensity = mix(0.5, 3.0, u.zoom_params.z);
  let glowAmount = mix(0.0, 0.8, u.zoom_params.w);

  // === SOBEL GRADIENT FLOW (from melting-oil) ===
  var h: array<f32, 9>;
  var k: u32 = 0u;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let sample = textureLoad(readTexture, coord + vec2<i32>(x, y), 0).r;
      h[k] = sample;
      k = k + 1u;
    }
  }
  let gx = (h[2] + 2.0*h[5] + h[8]) - (h[0] + 2.0*h[3] + h[6]);
  let gy = (h[6] + 2.0*h[7] + h[8]) - (h[0] + 2.0*h[1] + h[2]);
  var flow_dir = normalize(vec2<f32>(gx, gy));

  // Mouse influence on drag center
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_mouse = mouse_pos - uv;
  let dist_to_mouse = length(to_mouse);
  if (dist_to_mouse < 0.3) {
    let mouse_force = normalize(to_mouse) * (1.0 - dist_to_mouse / 0.3);
    flow_dir = normalize(flow_dir + mouse_force * 0.5);
  }

  // Ripples stir the flow
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 3.0) {
        let to_ripple = uv - ripple.xy;
        let dist_to_ripple = length(to_ripple);
        if (dist_to_ripple < 0.15) {
          let ripple_force = vec2<f32>(-to_ripple.y, to_ripple.x) * 0.3 * (1.0 - ripple_age / 3.0);
          flow_dir = normalize(flow_dir + ripple_force);
        }
      }
    }
  }

  // Viscosity drag
  let last_pos = vec2<f32>(f32(coord.x), f32(coord.y)) - flow_dir * viscosity * 3.0;
  let color = textureSampleLevel(readTexture, u_sampler, last_pos / vec2<f32>(f32(dim.x), f32(dim.y)), 0.0);
  let flow_speed = length(vec2<f32>(gx, gy));

  // === BLACKBODY THERMAL (from spec-blackbody-thermal) ===
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Map luminance + flow speed to temperature
  var temperature = mix(tempRangeLow, tempRangeHigh, luma + flow_speed * 0.05);

  // Mouse creates local hotspots
  let isMouseDown = u.zoom_config.w > 0.5;
  if (isMouseDown) {
    let mouseDist = length(uv - mouse_pos);
    let mouseHeat = exp(-mouseDist * mouseDist * 400.0);
    temperature += mouseHeat * tempRangeHigh * 0.5;
  }

  var thermalColor = blackbodyColor(temperature) * thermalIntensity;

  // Ember glow around bright/flowing regions
  if (glowAmount > 0.01) {
    let glowRadius = 0.03;
    var glowAccum = vec3<f32>(0.0);
    let glowSamples = 16;
    for (var i: i32 = 0; i < glowSamples; i = i + 1) {
      let angle = f32(i) * 0.392699 + time * 0.3;
      let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
      let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
      let sLuma = dot(s, vec3<f32>(0.299, 0.587, 0.114));
      let sTemp = mix(tempRangeLow, tempRangeHigh, sLuma);
      glowAccum += blackbodyColor(sTemp) * thermalIntensity;
    }
    glowAccum /= f32(glowSamples);
    thermalColor = mix(thermalColor, glowAccum, glowAmount * 0.4);
  }

  let displayColor = toneMapACES(thermalColor);

  // Melting hue shift based on flow
  let hue_shift = flow_speed * 0.1 + time * 0.01;
  let shifted = vec3<f32>(
    displayColor.r * (0.8 + 0.2 * sin(hue_shift)),
    displayColor.g * (0.8 + 0.2 * cos(hue_shift)),
    displayColor.b * (0.8 + 0.2 * sin(hue_shift + 1.57))
  );

  // Alpha based on flow speed (more flow = more opaque)
  let alpha = clamp(0.5 + flow_speed * 2.0 + luma * 0.3, 0.0, 1.0);

  textureStore(dataTextureB, coord, vec4<f32>(shifted, alpha));
  textureStore(writeTexture, id, vec4<f32>(shifted, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
