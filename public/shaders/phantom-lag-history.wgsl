// ═══════════════════════════════════════════════════════════════════
//  phantom-lag-history
//  Category: advanced-hybrid
//  Features: temporal-echo, luminance-history, rgba-state-machine, mouse-driven
//  Complexity: Very High
//  Chunks From: phantom-lag, alpha-luminance-history
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Phantom lag temporal echoes combined with rolling luminance history.
//  Each echo trail carries its own luminance memory, creating persistent
//  light-painted echoes that fade with physically-inspired decay. The alpha
//  channel stores the accumulated luminance history for downstream effects.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let time = u.config.x;

  let decayEcho = 0.9 + u.zoom_params.x * 0.09;
  let echoX = (u.zoom_params.y - 0.5) * 0.05;
  let echoY = (u.zoom_params.z - 0.5) * 0.05;
  let hueShift = u.zoom_params.w;

  let decayHistory = mix(0.005, 0.3, u.zoom_params.x);
  let glowIntensity = u.zoom_params.y * 3.0;
  let colorShift = u.zoom_params.z;
  let diffusion = u.zoom_params.w;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let currentLuma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // ═══ PHANTOM LAG: temporal echo with offset ═══
  let historyUV = uv - vec2<f32>(echoX, echoY);
  let history = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

  var newHistory = mix(current, history, decayEcho);

  // Hue shift on history
  if (hueShift > 0.01) {
    let old = newHistory;
    newHistory.r = mix(old.r, old.g, hueShift * 0.1);
    newHistory.g = mix(old.g, old.b, hueShift * 0.1);
    newHistory.b = mix(old.b, old.r, hueShift * 0.1);
  }

  // ═══ LUMINANCE HISTORY: rolling average ═══
  let prevState = textureLoad(dataTextureC, coord, 0);
  let prevAvgLuma = prevState.a;
  let newAvgLuma = mix(prevAvgLuma, currentLuma, decayHistory);

  // Glow where it WAS bright
  let glowAmount = max(0.0, newAvgLuma - currentLuma);
  let glowColor = vec3<f32>(1.0, 0.85, 0.6) * glowAmount * glowIntensity;

  // History tint
  var displayColor = newHistory.rgb + glowColor;
  let historyTint = vec3<f32>(
    1.0 + colorShift * 0.3,
    1.0 - colorShift * 0.1,
    1.0 - colorShift * 0.2
  );
  displayColor *= mix(vec3<f32>(1.0), historyTint, smoothstep(0.0, 0.5, newAvgLuma));

  // ═══ MOUSE TRAIL ═══
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseInfluence = smoothstep(0.15, 0.0, mouseDist) * mouseDown;
  let boostedAvg = mix(newAvgLuma, 1.0, mouseInfluence * 0.5);

  // ═══ RIPPLE FLASH ═══
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleBoost = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 2.0 && rDist < 0.1) {
      rippleBoost += smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 0.5);
    }
  }
  let finalAvgLuma = mix(boostedAvg, 1.0, rippleBoost * 0.3);

  // ═══ SPATIAL DIFFUSION ═══
  let ps = 1.0 / resolution;
  let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let diffusedAvg = (left.a + right.a + down.a + up.a) * 0.125 + finalAvgLuma * 0.5;

  // Alpha based on history accumulation
  let luma = dot(displayColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(0.75, 1.0, luma * decayEcho);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAlpha = mix(0.6, 1.0, depth);
  let finalAlpha = (alpha + depthAlpha) * 0.5;

  displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(2.0));
  displayColor = displayColor / (1.0 + displayColor * 0.3);
  displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Store state: RGB = color, A = diffused luminance history
  textureStore(dataTextureA, coord, vec4<f32>(displayColor, diffusedAvg));
  textureStore(writeTexture, coord, vec4<f32>(displayColor, finalAlpha));

  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
