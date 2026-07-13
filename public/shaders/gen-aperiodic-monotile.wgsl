// ═══════════════════════════════════════════════════════════════════
//  Aperiodic Monotile Hat Tiling — optimized
//  Category: generative
//  Features: aperiodic-tiling, monotile, generative-pattern, audio-reactive, mouse-scale,
//            edge-glow, temporal-rotation, chromatic-edge-bloom, bass-scale-pulse,
//            upgraded-rgba, aces-tone-map, lod-scaling, hex-bokeh, semantic-alpha
//  Complexity: High
//  Chunks From: aperiodic tiling + improved visual layering
//  Created: 2026-05-23
//  Updated: 2026-05-31
//  Upgraded: 2026-07-13
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
const TAU: f32 = 6.28318530718;
const HEX_Q: f32 = 0.577350269;
const HEX_R: f32 = 0.666666667;

const HEX_TAPS: array<vec2<f32>, 7> = array<vec2<f32>, 7>(
  vec2<f32>(0.0, 0.0),
  vec2<f32>(1.0, 0.0),
  vec2<f32>(0.5, 0.8660254),
  vec2<f32>(-0.5, 0.8660254),
  vec2<f32>(-1.0, 0.0),
  vec2<f32>(-0.5, -0.8660254),
  vec2<f32>(0.5, -0.8660254)
);
const HEX_WEIGHTS: array<f32, 7> = array<f32, 7>(0.25, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125);

fn rot2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
  let k = vec2<f32>(1.0 / 3.0, 2.0 / 3.0);
  let p = abs(fract(vec3<f32>(h) + vec3<f32>(k.y, k.x, 0.0)) * 6.0 - 3.0);
  return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn tileColor(hash: f32, time: f32, mids: f32, uvX: f32, sat: f32, val: f32) -> vec3<f32> {
  let hue = fract(hash + time * 0.03 + mids * 0.15 + uvX * 0.1);
  return hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
}

fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
  let c = uv - 0.5;
  return 1.0 - dot(c, c) * strength;
}

fn hatTileDistance(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let hex_q = p.x * HEX_Q + p.y * 0.333333;
  let hex_r = p.y * HEX_R;
  let hex_s = -hex_q - hex_r;
  let qf = floor(hex_q);
  let rf = floor(hex_r);
  let sf = floor(hex_s);
  let dq = abs(hex_q - qf - 0.5);
  let dr = abs(hex_r - rf - 0.5);
  let ds = abs(hex_s - sf - 0.5);
  let d = max(dq, max(dr, ds));
  return d * 2.0 - 0.5;
}

fn hexBokehEdge(uv: vec2<f32>, d: f32, edgeWidth: f32, bass: f32, treble: f32) -> vec3<f32> {
  var edgeSum = 0.0;
  var edgeR = 0.0;
  var edgeB = 0.0;
  for (var i = 0; i < 7; i = i + 1) {
    let off = HEX_TAPS[i] * edgeWidth * 0.4;
    let di = hatTileDistance(uv + off, 1.0);
    let w = HEX_WEIGHTS[i];
    edgeSum += smoothstep(edgeWidth, 0.0, abs(di)) * w;
    edgeR += smoothstep(edgeWidth * 1.2, 0.0, abs(di - 0.01 * bass)) * w;
    edgeB += smoothstep(edgeWidth * 1.2, 0.0, abs(di + 0.01 * treble)) * w;
  }
  return vec3<f32>(edgeR, edgeSum, edgeB) * (1.0 + treble);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let time = u.config.x;
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let mouse = u.zoom_config.yz;

  let param1 = u.zoom_params.x;
  let param2 = u.zoom_params.y;
  let param3 = u.zoom_params.z;
  let param4 = u.zoom_params.w;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  // Background fallback: subtle wandering noise
  let bgNoise = hash12(uv * 137.0 + vec2<f32>(time * 0.02, 0.0));
  let bg = vec3<f32>(0.03, 0.025, 0.035) + vec3<f32>(0.02, 0.02, 0.03) * bgNoise;

  // Bass-driven scale pulse
  let scale = mix(8.0, 32.0, param1) * (1.0 + bass * 0.2);
  let rotSpeed = (param2 - 0.5) * 0.5;
  let rot = time * rotSpeed + mouse.x * 0.5;
  let p = rot2(uv - 0.5, rot) + 0.5;

  // LOD: coarser distance for very high scales (fewer tile subdivisions perceptible)
  let lodScale = select(scale, scale * 0.5, scale > 28.0);
  let d = hatTileDistance(p, lodScale);

  let tileID = floor(p.x * lodScale * HEX_Q) + floor(p.y * lodScale * HEX_R) * 137.0;
  let tileHash = hash12(vec2<f32>(tileID, fract(tileID * 0.618)));

  let edgeWidth = mix(0.02, 0.08, param3);
  let chromaEdge = hexBokehEdge(p, d, edgeWidth, bass, treble);
  let edge = chromaEdge.y;

  let sat = mix(0.4, 0.9, param4 + treble * 0.3);
  let val = mix(0.15, 0.85, smoothstep(-0.3, 0.3, d) + bass * 0.2);

  let rgb = tileColor(tileHash, time, mids, uv.x, sat, val);
  let edgeColor = vec3<f32>(1.0, 0.95, 0.8) * chromaEdge;

  // Temporal tile color persistence with branchless mix
  let decay = 0.94 + treble * 0.02;
  let feedback = 0.06 + bass * 0.02;
  let finalRGB = mix(rgb + edgeColor, prev * decay, feedback);

  // Branchless background blend where tile is far from any edge
  let fgMask = smoothstep(-0.45, -0.15, d) + edge * 0.5;
  let vignetteFactor = clamp(vignette(uv, 0.6), 0.55, 1.0);
  var color = mix(bg, acesToneMap(finalRGB * 1.1), clamp(fgMask, 0.0, 1.0)) * vignetteFactor;

  let alpha = clamp(val * 0.6 + edge * 0.4 + bass * 0.05, 0.0, 1.0);
  let semanticAlpha = mix(0.12, alpha, clamp(fgMask, 0.0, 1.0)) * (0.7 + depth * 0.3);
  let finalColor = vec4<f32>(color, semanticAlpha);

  textureStore(writeTexture, pixel, finalColor);
  textureStore(dataTextureA, pixel, finalColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(val * 0.5 + edge * 0.3, 0.0, 0.0, 0.0));
}
