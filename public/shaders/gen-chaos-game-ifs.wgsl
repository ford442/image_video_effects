// ═══════════════════════════════════════════════════════════════════
//  Chaos Game IFS Fractal — optimized
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, temporal-ghosting, chromatic-attractors,
//            bass-scale-pulse, upgraded-rgba, aces-tone-map, lod-scaling, hex-bokeh,
//            semantic-alpha, branchless-ifs
//  Complexity: Medium
//  Created: 2026-05-23
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
const MIN_ITER: i32 = 3;
const MAX_ITER: i32 = 14;
const IFS_SCALE_BASE: f32 = 0.5;

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

fn ifsPoint(uv: vec2<f32>, iter: i32, time: f32, bass: f32, offset: vec2<f32>) -> vec2<f32> {
  var p = (uv + offset) * 2.0 - 1.0;
  let rot = time * 0.1 + bass * 0.5;
  let c = cos(rot);
  let s = sin(rot);
  let a1 = vec2<f32>(-0.5 * c, -0.5 * s);
  let a2 = vec2<f32>(0.5 * c, 0.5 * s);
  let a3 = vec2<f32>(-0.866 * s, 0.866 * c);
  let scale = IFS_SCALE_BASE + bass * 0.1;

  for (var i: i32 = 0; i < iter; i = i + 1) {
    let fi = f32(i);
    let h = hash12(p + vec2<f32>(fi * 0.1, time * 0.01));
    // Branchless attractor selection via cascaded select
    let t2 = select((p - a3) * scale, (p - a2) * scale, h > 0.33);
    p = select(t2, (p - a1) * scale, h < 0.33);
  }
  return p;
}

fn hexBokehGlow(uv: vec2<f32>, center: vec2<f32>, radius: f32, intensity: f32) -> f32 {
  var glow = 0.0;
  for (var i = 0; i < 7; i = i + 1) {
    let d = length(uv - center - HEX_TAPS[i] * radius);
    glow += exp(-d * d * 80.0) * HEX_WEIGHTS[i];
  }
  return glow * intensity;
}

fn attractorGlow(d: f32, tightness: f32) -> f32 {
  return 1.0 / (1.0 + d * d * tightness);
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

  let param1 = u.zoom_params.x;
  let param2 = u.zoom_params.y;
  let param3 = u.zoom_params.z;
  let param4 = u.zoom_params.w;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  // Background fallback: deep void with subtle grain
  let grain = hash12(uv * 512.0 + vec2<f32>(time * 0.1, 0.0));
  let bg = vec3<f32>(0.01, 0.012, 0.018) + vec3<f32>(0.015, 0.015, 0.02) * grain;

  // LOD: more iterations in center/detail zones, fewer at edges
  let centerDist = length(uv - 0.5);
  let lodFactor = 1.0 - smoothstep(0.25, 0.55, centerDist);
  let iterations = i32(mix(f32(MIN_ITER), f32(MAX_ITER), (param1 + bass * 0.3) * lodFactor));

  // Chromatic attractor separation: R/B use different attractor offsets
  let sepR = param4 * 0.01 * bass;
  let sepB = param4 * 0.01 * treble;
  let p_r = ifsPoint(uv, iterations, time, bass, vec2<f32>(sepR, 0.0));
  let p_b = ifsPoint(uv, iterations, time, bass, vec2<f32>(-sepB, 0.0));
  let p_g = ifsPoint(uv, iterations, time, bass, vec2<f32>(0.0, 0.0));

  let d_r = length(p_r);
  let d_g = length(p_g);
  let d_b = length(p_b);
  let angle = atan2(p_g.y, p_g.x) / TAU;

  let tightness = mix(4.0, 20.0, param2);
  let glow_r = attractorGlow(d_r, tightness);
  let glow_g = attractorGlow(d_g, tightness);
  let glow_b = attractorGlow(d_b, tightness);
  let rings = smoothstep(0.0, 0.1, abs(fract(d_g * mix(3.0, 10.0, param3)) - 0.5));
  let bassBoost = 1.0 + bass * 0.3;

  let hue = fract(angle + time * 0.03 + mids * 0.15);
  let sat = mix(0.4, 1.0, param4 + treble * 0.3);
  let val_r = glow_r * (0.5 + rings * 0.5) * bassBoost;
  let val_g = glow_g * (0.5 + rings * 0.5) * bassBoost;
  let val_b = glow_b * (0.5 + rings * 0.5) * bassBoost;

  let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat);
  var finalRGB = vec3<f32>(rgb.r * val_r, rgb.g * val_g, rgb.b * val_b);

  // Hex-bokeh glow around attractor center for softer falloff
  finalRGB += vec3<f32>(glow_r, glow_g, glow_b) * hexBokehGlow(uv, vec2<f32>(0.5), 0.08 + bass * 0.02, 0.4 + treble * 0.2);

  // Temporal ghosting from previous IFS state
  let ghosted = mix(finalRGB, prev * 0.88, 0.1 + bass * 0.05);

  // Branchless background blend on low-glow regions
  let glowSum = glow_r + glow_g + glow_b;
  let fgMask = smoothstep(0.05, 0.25, glowSum + rings * 0.1);
  var color = mix(bg, acesToneMap(ghosted * 1.1), fgMask);

  let alpha = clamp(glowSum * 0.3 + glow_g * 0.3 + 0.1 + bass * 0.05, 0.0, 1.0);
  let semanticAlpha = mix(0.1, alpha, fgMask) * (0.7 + depth * 0.3);
  let finalColor = vec4<f32>(color, semanticAlpha);

  textureStore(writeTexture, pixel, finalColor);
  textureStore(dataTextureA, pixel, finalColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
