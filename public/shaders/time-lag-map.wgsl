// ═══════════════════════════════════════════════════════════════════
//  Time-Lag Map
//  Category: geometric
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: luma-keyed delay; motion-gated smear
//  A packing: history RGB (C is previous history)
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

const PI: f32 = 3.14159265359;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * hash21(p * freq + vec2<f32>(time * 0.1));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getLagAmount(uv: vec2<f32>, mappingType: f32, time: f32, depth: f32) -> f32 {
  let selector = floor(mappingType * 5.0);
  var lag = 0.0;
  if (selector < 1.0) {
    lag = length(uv - vec2<f32>(0.5)) * 2.0;
  } else if (selector < 2.0) {
    lag = uv.x;
  } else if (selector < 3.0) {
    lag = uv.y;
  } else if (selector < 4.0) {
    let centered = uv - vec2<f32>(0.5);
    let angle = atan2(centered.y, centered.x) / PI * 0.5 + 0.5;
    let radius = length(centered) * 2.0;
    lag = fract(angle + radius + time * 0.2);
  } else {
    lag = fbm(uv * 4.0, time);
  }
  lag = lag * (1.0 - depth * 0.5);
  return clamp(lag, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  let iCoord = vec2<i32>(coord);

  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let bufferLength = mix(0.1, 1.0, u.zoom_params.x);
  let mappingFunction = u.zoom_params.y;
  let feedbackMix = mix(0.0, 0.95, u.zoom_params.z);
  let motionSense = mix(0.0, 2.0, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  var lagAmount = getLagAmount(uv, mappingFunction, time, depth);

  var mouse = u.zoom_config.yz;
  let mouseDist = length(uv - mouse);
  let mouseRadius = 0.2;
  let mouseInfluence = (1.0 - clamp(mouseDist / mouseRadius, 0.0, 1.0)) * f32(mouseDist < mouseRadius);
  lagAmount = mix(lagAmount, 1.0, mouseInfluence * 0.5);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleAge = time - ripple.z;
    let live = f32(ripple.z > 0.0 && rippleAge > 0.0 && rippleAge < 3.0);
    let dist = length(uv - ripple.xy);
    let wave = sin(dist * 20.0 - rippleAge * 5.0) * 0.5 + 0.5;
    let fade = 1.0 - rippleAge / 3.0;
    lagAmount = mix(lagAmount, wave, fade * 0.3 * live * f32(dist < rippleAge * 0.3));
  }

  let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let historyColor = textureLoad(dataTextureC, iCoord, 0);
  let luma = dot(currentColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  // Idea 1 — luma-keyed delay.
  lagAmount = mix(lagAmount, clamp(lagAmount * (0.55 + luma * 0.9), 0.0, 1.0), 0.45);

  let motion = length(currentColor.rgb - historyColor.rgb);
  let motionInfluence = clamp(motion * motionSense, 0.0, 1.0);
  lagAmount = lagAmount * (1.0 - motionInfluence * 0.7 * f32(motionSense > 0.0));

  // Idea 2 — motion-gated smear along |current−C| gradient.
  let nCoord = clamp(iCoord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(size) - vec2<i32>(1));
  let histN = textureLoad(dataTextureC, nCoord, 0).rgb;
  let smearDir = vec2<f32>(motion, length(histN - historyColor.rgb));
  let smearUV = clamp(uv + smearDir * motionInfluence * 0.012 * (1.0 + mids * 0.3), vec2<f32>(0.0), vec2<f32>(1.0));
  let smearHist = textureLoad(dataTextureC, clamp(vec2<i32>(smearUV * vec2<f32>(size)), vec2<i32>(0), vec2<i32>(size) - vec2<i32>(1)), 0);

  let blendFactor = lagAmount * bufferLength;
  var delayedColor = mix(currentColor.rgb, mix(historyColor.rgb, smearHist.rgb, motionInfluence * 0.5), blendFactor);

  let newHistory = mix(historyColor.rgb, currentColor.rgb, 0.1 + (1.0 - lagAmount) * 0.3);
  textureStore(dataTextureA, iCoord, vec4<f32>(newHistory, 1.0));

  let chromaLag = lagAmount * 0.02;
  let rDelayed = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(chromaLag, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bDelayed = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(chromaLag, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var finalColor = vec3<f32>(
    mix(delayedColor.r, rDelayed, lagAmount * 0.3),
    delayedColor.g,
    mix(delayedColor.b, bDelayed, lagAmount * 0.3)
  );
  let ghost = historyColor.rgb * lagAmount * 0.3;
  finalColor = finalColor + ghost * 0.2;
  finalColor = finalColor + vec3<f32>(0.3, 0.6, 1.0) * motion * 0.5 * f32(motion > 0.1);
  finalColor = finalColor * (1.0 - lagAmount * 0.2);
  finalColor = aces(max(finalColor, vec3<f32>(0.0)));
  let alpha = clamp(currentColor.a * 0.3 + lagAmount * 0.45 + motionInfluence * 0.2 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, iCoord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, iCoord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
