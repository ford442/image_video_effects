// ═══════════════════════════════════════════════════════════════════
//  Temporal Frequency Decomposition
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Discrete temporal Fourier analysis across the 8-frame history ring.
//  Each pixel accumulates a weighted sum where weights follow
//  sin/cos at the target temporal frequency. Static pixels cancel to
//  zero; pixels flickering or oscillating near the target frequency
//  produce large magnitude responses and glow brightly.
//  The result is overlaid on the current frame.
//
//  zoom_params layout:
//    x = target frequency (0→0.05 cycles/frame, 1→0.5, default 0.25→~0.18)
//    y = glow brightness  (0→dim, 1→blazing, default 0.6)
//    z = glow color hue   (0→red/orange, 0.5→cyan, 1→red again, default 0.17→yellow)
//    w = base blend       (0→glow only, 1→base+glow, default 0.8)
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=freq, y=glowBright, z=glowHue, w=baseBlend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const TAU: f32 = 6.28318530718;
const N_FRAMES: f32 = 8.0;  // total frames including current

// Simple hue→RGB conversion
fn hue2rgb(h: f32) -> vec3<f32> {
  let h6 = fract(h) * 6.0;
  let r  = clamp(abs(h6 - 3.0) - 1.0, 0.0, 1.0);
  let g  = clamp(2.0 - abs(h6 - 2.0), 0.0, 1.0);
  let b  = clamp(2.0 - abs(h6 - 4.0), 0.0, 1.0);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Parameters; bass boosts glow brightness, mids rotate hue for spectral color
  let freq       = 0.05 + u.zoom_params.x * 0.45;
  let glowBright = u.zoom_params.y * 2.0 * (1.0 + bass * 0.6);
  let glowHue    = fract(u.zoom_params.z + mids * 0.15);
  let baseBlend  = u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Discrete Fourier bin at target frequency over 8 time samples
  // Real part (cosine weights) and imaginary part (sine weights)
  var realAcc = current.rgb * 1.0;  // cos(0) = 1
  var imagAcc = current.rgb * 0.0;  // sin(0) = 0

  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist  = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let t     = f32(age);
    realAcc += hist.rgb * cos(TAU * freq * t);
    imagAcc += hist.rgb * sin(TAU * freq * t);
  }

  // Frequency magnitude (normalised by sample count)
  let magnitude = sqrt(realAcc * realAcc + imagAcc * imagAcc) / N_FRAMES;

  // Scalar energy level for glow brightness
  let energy = (magnitude.r + magnitude.g + magnitude.b) / 3.0;

  // Coloured glow: single hue tinted by frequency energy
  let glowColor = hue2rgb(glowHue) * energy * glowBright;

  // Composite: base + glow
  let base   = current.rgb * baseBlend;
  let output = base + glowColor;
  let alpha = clamp(energy * 2.5 + baseBlend * 0.3 + bass * 0.2, 0.0, 1.0);
  let finalOut = vec4<f32>(output, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
