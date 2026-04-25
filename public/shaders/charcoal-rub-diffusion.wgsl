// ═══════════════════════════════════════════════════════════════════
//  Charcoal Rub + Anisotropic Diffusion
//  Category: advanced-hybrid
//  Features: advanced-convolution, upgraded-rgba, mouse-driven, temporal
//  Complexity: High
//  Chunks From: charcoal-rub.wgsl, conv-anisotropic-diffusion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-10 — Image Processing & Artistry Enhancer
// ═══════════════════════════════════════════════════════════════════
//
//  Hybrid Approach:
//    1. Apply Perona-Malik anisotropic diffusion to input image
//    2. Edge-preserving smoothing creates smooth tonal regions
//    3. Convert diffused image to charcoal via grayscale + high contrast
//    4. Charcoal reveal mask controls where drawing appears
//    5. Diffusion coefficient (alpha) modulates charcoal density
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Anisotropically diffused charcoal rendering
//    Alpha: Diffusion coefficient * charcoal density — encodes both how much
//           smoothing was applied AND how thick the charcoal layer is.
//           Creates natural transparency variation in the drawing.
//
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

// ═══ CHUNK: hash12 (from charcoal-rub.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: noise (from charcoal-rub.wgsl) ═══
fn noise(x: vec2<f32>) -> f32 {
    var i = floor(x);
    let f = fract(x);
    var a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// ═══ CHUNK: fbm (from charcoal-rub.wgsl) ═══
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var x = p;
    for (var i = 0; i < 5; i++) {
        v = v + a * noise(x);
        x = rot * x * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

// ═══ CHUNK: paperGrain (from charcoal-rub.wgsl) ═══
fn paperGrain(uv: vec2<f32>, scale: f32) -> f32 {
    let grain = fbm(uv * scale);
    return 0.85 + 0.15 * grain;
}

// ═══ CHUNK: diffusionCoefficient (from conv-anisotropic-diffusion.wgsl) ═══
fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
    return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;

  // Parameters
  let hardness = mix(0.1, 0.9, u.zoom_params.x);
  let textureScale = mix(10.0, 100.0, u.zoom_params.y);
  let revealRate = mix(0.01, 0.2, u.zoom_params.z);
  let diffusionStrength = u.zoom_params.w;

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let aspect = resolution.x / resolution.y;
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let dist = distance(uv_aspect, mouse_aspect);

  // Read previous reveal state
  var state = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).r;
  state = max(0.0, state - 0.005);

  if (mouseDown > 0.5) {
      let brushRadius = 0.1;
      let brushSoftness = 0.5;
      let brushVal = 1.0 - smoothstep(brushRadius * (1.0 - brushSoftness), brushRadius, dist);
      let brushNoise = noise(uv * textureScale + time * 10.0);
      state = min(1.0, state + brushVal * revealRate * (0.5 + 0.5 * brushNoise));
  }

  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(state, 0.0, 0.0, 1.0));

  // === ANISOTROPIC DIFFUSION ===
  let kappa = mix(0.02, 0.15, diffusionStrength);
  let dt = mix(0.05, 0.2, diffusionStrength);
  let iterations = i32(mix(1.0, 4.0, diffusionStrength));

  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var current = center;
  var avgCoeff = 0.0;

  for (var iter = 0; iter < iterations; iter++) {
      let n = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 1.0) * pixelSize, 0.0).rgb;
      let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -1.0) * pixelSize, 0.0).rgb;
      let e = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 0.0) * pixelSize, 0.0).rgb;
      let w = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 0.0) * pixelSize, 0.0).rgb;

      let gradN = length(n - current);
      let gradS = length(s - current);
      let gradE = length(e - current);
      let gradW = length(w - current);

      let cN = diffusionCoefficient(gradN, kappa);
      let cS = diffusionCoefficient(gradS, kappa);
      let cE = diffusionCoefficient(gradE, kappa);
      let cW = diffusionCoefficient(gradW, kappa);

      // Mouse heat source acceleration
      let mouseDist = length(uv - mouse);
      let mouseFactor = exp(-mouseDist * mouseDist * 10.0);
      let mouseBoost = 1.0 + mouseFactor * 3.0;

      let fluxN = cN * (n - current);
      let fluxS = cS * (s - current);
      let fluxE = cE * (e - current);
      let fluxW = cW * (w - current);

      let effectiveDt = dt * mouseBoost;
      current = current + effectiveDt * (fluxN + fluxS + fluxE + fluxW);
      avgCoeff = (cN + cS + cE + cW) * 0.25;
  }

  // Blend diffused with original based on diffusion strength
  var diffusedColor = mix(center, current, diffusionStrength);

  // === CHARCOAL CONVERSION ===
  let paperGrainVal = paperGrain(uv, textureScale * 0.1);
  let charcoal_density = state * (0.5 + 0.5 * paperGrainVal);

  // Diffusion coefficient modulates charcoal: more diffusion = smoother = lighter
  let diffusionModulation = mix(0.7, 1.3, avgCoeff);
  let adjustedDensity = charcoal_density * diffusionModulation;

  var charcoal_alpha = smoothstep(0.0, 0.3, adjustedDensity);
  charcoal_alpha = mix(0.0, 0.9, charcoal_alpha * charcoal_alpha);

  let grain_influence = smoothstep(0.3, 0.7, paperGrainVal);
  charcoal_alpha *= mix(0.7, 1.0, grain_influence);
  let edge_softness = smoothstep(0.0, 0.4, state) * (1.0 - smoothstep(0.6, 1.0, state));
  charcoal_alpha *= 0.7 + 0.3 * edge_softness;

  // Paper texture
  let paperNoise = fbm(uv * textureScale);
  let paperBaseColor = vec3<f32>(0.95, 0.94, 0.92) * (0.85 + 0.15 * paperNoise);

  // Diffused image to charcoal
  let diffusedLuma = dot(diffusedColor, vec3<f32>(0.299, 0.587, 0.114));
  let charcoalColor = vec3<f32>(0.08, 0.07, 0.06) * (0.5 + 0.5 * paperGrainVal);
  let charcoal_shade = mix(vec3<f32>(0.25), charcoalColor, adjustedDensity);

  // Modulate reveal by paper texture
  let revealMask = smoothstep(1.0 - hardness, 1.0, state * paperGrainVal);

  var final_rgb = mix(paperBaseColor, charcoal_shade, revealMask);

  // Charcoal dust scattering
  let dust_scatter = smoothstep(0.0, 0.15, state) * (1.0 - revealMask) * 0.3;
  let dust_color = vec3<f32>(0.15, 0.14, 0.12) * paperGrainVal;
  final_rgb = mix(final_rgb, dust_color, dust_scatter);

  let grain_alpha_mod = mix(0.85, 1.0, grain_influence);
  charcoal_alpha *= grain_alpha_mod;

  final_rgb = clamp(final_rgb, vec3<f32>(0.0), vec3<f32>(1.0));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_rgb, charcoal_alpha));

  // Store charcoal thickness in depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(adjustedDensity, 0.0, 0.0, charcoal_alpha));
}
