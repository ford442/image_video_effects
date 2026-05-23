// ═══════════════════════════════════════════════════════════════════
//  Strange Field Flow
//  Category: generative
//  Features: audio-reactive, temporal, psychedelic, procedural
//  Complexity: High
//  Created: 2026-05-23
// ═══════════════════════════════════════════════════════════════════
//  A 2D strange-attractor-inspired vector field where each pixel
//  evaluates a modified Clifford / Peter de Jong attractor map and
//  paints streaks along the local flow direction. The attractor
//  coefficients pulse to audio, producing vivid acid-neon whorls
//  that morph continuously. Temporal persistence burns trails.

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

const TAU: f32 = 6.283185307179586;
const ITERS: i32 = 8;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// ═══ CHUNK: hash12 (standard) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Peter de Jong attractor step
fn deJongStep(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  let x = sin(a * p.y) - cos(b * p.x);
  let y = sin(c * p.x) - cos(d * p.y);
  return vec2<f32>(x, y);
}

// Modified Clifford attractor step
fn cliffordStep(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  let x = sin(a * p.y) + c * cos(a * p.x);
  let y = sin(b * p.x) + d * cos(b * p.y);
  return vec2<f32>(x, y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res    = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord  = vec2<i32>(global_id.xy);
  let uv     = vec2<f32>(global_id.xy) / res;
  let time   = u.config.x;
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let speed    = mix(0.15, 1.8, u.zoom_params.x);
  let chaos    = mix(0.0,  1.0, u.zoom_params.y); // blend de Jong / Clifford
  let density  = mix(1.0,  3.5, u.zoom_params.z); // brightness
  let feedback = u.zoom_params.w;

  // Attractor coefficients drift slowly with audio
  let t = time * speed;
  let a = 1.7  + 0.9 * sin(t * 0.13) + bass   * 0.6;
  let b = -1.3 + 0.8 * cos(t * 0.17) + mids   * 0.5;
  let c = -1.8 + 0.7 * sin(t * 0.11) + treble * 0.4;
  let d = 1.5  + 0.9 * cos(t * 0.19) + bass   * 0.3;

  // Map pixel to attractor space [-2.5, 2.5]
  let scale = 2.5;
  var q = (uv - 0.5) * 2.0 * scale;

  // Iterate the map forward and accumulate orbit density
  var density_acc = 0.0;
  var orbit_hue   = 0.0;
  var pt = q;

  for (var i: i32 = 0; i < ITERS; i = i + 1) {
    let pJ = deJongStep(pt, a, b, c, d);
    let pC = cliffordStep(pt, a, b, c, d);
    pt = mix(pJ, pC, chaos);

    // Map orbit point back to UV and accumulate if near current pixel
    let orbitUV = pt / (scale * 2.0) + 0.5;
    let delta   = abs(uv - orbitUV);
    let w = exp(-length(delta) * 30.0 * (1.0 + mids));
    density_acc = density_acc + w;
    orbit_hue   = orbit_hue + w * fract(f32(i) / f32(ITERS) + time * speed * 0.08);
  }

  // Normalize
  density_acc = density_acc / f32(ITERS);
  let normHue = select(0.0, orbit_hue / max(density_acc * f32(ITERS), 0.001), density_acc > 0.001);

  // Color: hue from orbit position, saturation high, value from density
  let hue = fract(normHue + time * speed * 0.05 + length(q) * 0.04);
  let sat = 0.88 + treble * 0.12;
  let val = density_acc * density * (1.0 + bass * 0.6);
  var color = hsv2rgb(vec3<f32>(hue, sat, 1.0)) * val;

  // Temporal feedback — slight zoom-in pull
  var histUV = uv;
  let pullStrength = 0.003 + speed * 0.002;
  histUV = mix(histUV, vec2<f32>(0.5), pullStrength);
  // Small phase rotation of history coords
  let histP = (histUV - 0.5) * 2.0;
  let hRot  = 0.008 * speed;
  let hc = cos(hRot); let hs = sin(hRot);
  let rHistP = vec2<f32>(histP.x * hc - histP.y * hs, histP.x * hs + histP.y * hc);
  histUV = rHistP * 0.5 + 0.5;

  let prev  = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  let fbMix = mix(0.1, 0.82, feedback);
  color = mix(color, prev * 0.91, fbMix);

  let vign  = 1.0 - smoothstep(0.5, 1.1, length(q / scale));
  color = color * vign;
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(4.0));

  let depth = clamp(density_acc * 0.5, 0.0, 1.0);
  let alpha = clamp(length(color) * 0.5, 0.0, 1.0);

  textureStore(writeTexture,      coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(color, alpha));
}
