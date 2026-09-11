// ═══════════════════════════════════════════════════════════════════
//  Charcoal Rub + Anisotropic Diffusion
//  Category: advanced-hybrid
//  Features: advanced-convolution, upgraded-rgba, mouse-driven, temporal, audio-reactive
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: contour vine strokes; kneaded-eraser skip
//  A packing: raw reveal mask in A.r
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec2<f32>) -> f32 {
    var i = floor(x);
    let f = fract(x);
    var a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u2.x) + (c - a) * u2.y * (1.0 - u2.x) + (d - b) * u2.x * u2.y;
}

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

fn paperGrain(uv: vec2<f32>, scale: f32) -> f32 {
    let grain = fbm(uv * scale);
    return 0.85 + 0.15 * grain;
}

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
    return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let coord = vec2<i32>(global_id.xy);

  var uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let hardness = mix(0.1, 0.9, u.zoom_params.x);
  let textureScale = mix(10.0, 100.0, u.zoom_params.y);
  let revealRate = mix(0.01, 0.2, u.zoom_params.z) * (1.0 + bass * 0.3);
  let diffusionStrength = u.zoom_params.w;

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let dist = distance(uv_aspect, mouse_aspect);

  var state = textureLoad(dataTextureC, coord, 0).r;
  state = max(0.0, state - 0.005);

  if (mouseDown > 0.5) {
      let brushRadius = 0.1;
      let brushSoftness = 0.5;
      let brushVal = 1.0 - smoothstep(brushRadius * (1.0 - brushSoftness), brushRadius, dist);
      let brushNoise = noise(uv * textureScale + time * 10.0);
      state = min(1.0, state + brushVal * revealRate * (0.5 + 0.5 * brushNoise));
  }

  textureStore(dataTextureA, coord, vec4<f32>(state, 0.0, 0.0, 1.0));

  let kappa = mix(0.02, 0.15, diffusionStrength);
  let dt = mix(0.05, 0.2, diffusionStrength);
  let iterations = i32(mix(1.0, 4.0, diffusionStrength));

  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var current = center.rgb;
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

  var diffusedColor = mix(center.rgb, current, diffusionStrength);
  let diffusedLuma = dot(diffusedColor, vec3<f32>(0.299, 0.587, 0.114));

  // Idea 1 — contour vine: charcoal follows Sobel of the diffused plate
  let lumN = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumS = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumE = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumW = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let edgeMag = length(vec2<f32>(lumE - lumW, lumN - lumS));
  let tangent = normalize(vec2<f32>(-(lumN - lumS), lumE - lumW) + vec2<f32>(0.0001));
  let vineStroke = abs(sin(dot(uv * textureScale * 0.35, tangent) * 6.28318)) * smoothstep(0.04, 0.18, edgeMag);

  // Idea 2 — kneaded-eraser skip on bright diffused regions
  let kneadSkip = 1.0 - smoothstep(0.62, 0.88, diffusedLuma) * (0.55 + mids * 0.2);

  let paperGrainVal = paperGrain(uv, textureScale * 0.1);
  let charcoal_density = state * (0.5 + 0.5 * paperGrainVal);
  let diffusionModulation = mix(0.7, 1.3, avgCoeff);
  var adjustedDensity = charcoal_density * diffusionModulation * (0.72 + vineStroke * 0.55) * kneadSkip;

  var charcoal_alpha = smoothstep(0.0, 0.3, adjustedDensity);
  charcoal_alpha = mix(0.0, 0.9, charcoal_alpha * charcoal_alpha);
  let grain_influence = smoothstep(0.3, 0.7, paperGrainVal);
  charcoal_alpha *= mix(0.7, 1.0, grain_influence);
  let edge_softness = smoothstep(0.0, 0.4, state) * (1.0 - smoothstep(0.6, 1.0, state));
  charcoal_alpha *= 0.7 + 0.3 * edge_softness;

  let paperNoise = fbm(uv * textureScale);
  let paperBaseColor = vec3<f32>(0.95, 0.94, 0.92) * (0.85 + 0.15 * paperNoise);
  let charcoalColor = vec3<f32>(0.08, 0.07, 0.06) * (0.5 + 0.5 * paperGrainVal);
  let charcoal_shade = mix(vec3<f32>(0.25), charcoalColor, adjustedDensity);
  let revealMask = smoothstep(1.0 - hardness, 1.0, state * paperGrainVal * kneadSkip);
  var final_rgb = mix(paperBaseColor, charcoal_shade, revealMask);
  final_rgb = mix(final_rgb, charcoalColor * 0.55, vineStroke * state * 0.35);

  let dust_scatter = smoothstep(0.0, 0.15, state) * (1.0 - revealMask) * 0.3;
  let dust_color = vec3<f32>(0.15, 0.14, 0.12) * paperGrainVal;
  final_rgb = mix(final_rgb, dust_color, dust_scatter);

  charcoal_alpha *= mix(0.85, 1.0, grain_influence);
  charcoal_alpha = clamp(charcoal_alpha * (0.85 + center.a * 0.15) * (1.0 + treble * 0.08), 0.0, 1.0);
  final_rgb = acesToneMap(clamp(final_rgb, vec3<f32>(0.0), vec3<f32>(1.0)));

  textureStore(writeTexture, coord, vec4<f32>(final_rgb, charcoal_alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(adjustedDensity, 0.0, 0.0, 0.0));
}
