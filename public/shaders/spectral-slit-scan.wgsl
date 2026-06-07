// ═══════════════════════════════════════════════════════════════════
//  Spectral Slit Scan v2
//  Category: artistic
//  Features: audio-reactive, mouse-driven, temporal, multi-slit
//  Complexity: High
//  Upgraded: 2026-05-30
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

// ═══ CHUNK: aces_approx (filmic tone mapping) ═══
fn aces_approx(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash12 (deterministic noise) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let slitCount = 3.0 + floor(u.zoom_params.x * 4.0);
  let trailDecay = 0.75 + u.zoom_params.y * 0.24;
  let chromaShift = u.zoom_params.z * 0.04;
  let curveAmp = u.zoom_params.w * 0.06;

  // Velocity driven by bass
  let velo = 1.0 + bass * 2.5;

  var accum = vec3<f32>(0.0);
  var totalWeight = 0.0;
  var maxAge = 0.0;

  for (var s: u32 = 0u; s < 3u; s = s + 1u) {
    let fi = f32(s);
    let slitPhase = fi * 2.094;

    // Parametric slit curves: sine, spiral, radial
    var curveOff = vec2<f32>(0.0);
    if (s == 0u) {
      curveOff.x = sin(uv.y * 6.28 + time * velo * 0.7 + slitPhase) * curveAmp;
    } else if (s == 1u) {
      let ang = time * velo * 0.5 + fi * 2.094;
      curveOff = vec2<f32>(cos(ang), sin(ang)) * curveAmp * (0.5 + uv.y);
    } else {
      let rd = length(uv - 0.5);
      curveOff = normalize(uv - 0.5 + 0.001) * sin(rd * 12.0 - time * velo) * curveAmp;
    }

    // Mouse adds parallax offset per slit
    let mousePull = (mouse - 0.5) * 0.02 * (fi + 1.0);
    let parallax = (depth - 0.5) * 0.03 * (fi + 1.0);

    let sampleUV = clamp(uv + curveOff + mousePull + parallax, vec2<f32>(0.0), vec2<f32>(1.0));

    // Spectral decomposition: R/G/B sample at different temporal lags
    let histR = textureSampleLevel(dataTextureC, u_sampler, sampleUV + vec2<f32>(chromaShift, 0.0), 0.0);
    let histG = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);
    let histB = textureSampleLevel(dataTextureC, u_sampler, sampleUV - vec2<f32>(chromaShift, 0.0), 0.0);

    let age = clamp(1.0 - (histR.a + histG.a + histB.a) * 0.333, 0.0, 1.0);
    let decay = pow(trailDecay, fi + 1.0);
    let w = decay * (1.0 + bass * 0.5);

    accum.r = accum.r + mix(histR.r, histG.r, 0.3) * w;
    accum.g = accum.g + mix(histG.g, histB.g, 0.3) * w;
    accum.b = accum.b + mix(histB.b, histR.b, 0.3) * w;
    totalWeight = totalWeight + w;
    maxAge = max(maxAge, age);
  }

  if (totalWeight > 0.0) {
    accum = accum / totalWeight;
  }

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let feedback = mix(inputColor.rgb, accum, 0.6);

  // HDR streak accumulation with tone mapping
  var hdr = feedback * (1.0 + bass * 0.4);
  hdr = aces_approx(hdr);

  // Alpha: slit intensity × temporal accumulation age
  let slitIntensity = smoothstep(0.1, 0.9, totalWeight / 3.0);
  let alpha = clamp(slitIntensity * (0.3 + maxAge * 0.7), 0.0, 1.0);

  let finalColor = vec4<f32>(hdr, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
