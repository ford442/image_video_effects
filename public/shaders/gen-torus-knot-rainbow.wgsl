// ═══════════════════════════════════════════════════════════════════
//  Torus Knot Rainbow
//  Category: generative
//  Features: audio-reactive, temporal, psychedelic, procedural,
//            chromatic-tube-gradient, audio-wind-modulation, depth-output
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-05-31
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

const TAU: f32 = 6.283185307179586;
const STEPS: i32 = 300;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn torusKnotPoint(t: f32, pWind: f32, qWind: f32, R: f32, r: f32) -> vec3<f32> {
  let phi = t * pWind;
  let theta = t * qWind;
  let x = (R + r * cos(theta)) * cos(phi);
  let y = (R + r * cos(theta)) * sin(phi);
  let z = r * sin(theta);
  return vec3<f32>(x, y, z);
}

fn project(pt: vec3<f32>, camDist: f32) -> vec2<f32> {
  let w = 1.0 / (camDist - pt.z);
  return pt.xy * w;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res    = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord  = vec2<i32>(global_id.xy);
  let uv     = vec2<f32>(global_id.xy) / res;
  let time   = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse  = u.zoom_config.yz;

  let spinSpeed  = mix(0.2, 2.0, u.zoom_params.x);
  let knotP      = floor(mix(2.0, 6.0, u.zoom_params.y));
  let knotQ      = floor(mix(3.0, 7.0, u.zoom_params.z)) + 1.0;
  let tubeRadius = mix(0.025, 0.006, u.zoom_params.w);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.2;

  let rot  = time * spinSpeed * 0.18 + mouse.x * TAU;
  let cosR = cos(rot);
  let sinR = sin(rot);
  let px   = p.x * cosR - p.y * sinR;
  let py   = p.x * sinR + p.y * cosR;
  p = vec2<f32>(px, py);

  // Audio-driven wind parameter modulation
  let pWind = knotP;
  let qWind = knotQ + bass * 1.5;
  let R     = 0.65;
  let r     = 0.35;
  let cam   = 3.8 + (mouse.y - 0.5) * 2.5;

  var glowAcc   = 0.0;
  var colorAccR = vec3<f32>(0.0);
  var colorAccB = vec3<f32>(0.0);

  for (var si: i32 = 0; si < STEPS; si = si + 1) {
    let t  = f32(si) / f32(STEPS) * TAU;
    let pt = torusKnotPoint(t, pWind, qWind, R, r);
    let proj = project(pt, cam);
    let d  = distance(p, proj);
    let w  = tubeRadius * (1.0 + bass * 0.5);
    let g  = smoothstep(w * 3.0, 0.0, d) + smoothstep(w * 6.0, 0.0, d) * 0.25;

    // Chromatic tube gradient: inner warm, outer cool
    let hue = fract(f32(si) / f32(STEPS) + time * spinSpeed * 0.1 + treble * 0.12);
    let sat = 0.85 + mids * 0.15;
    let rgb = hsv2rgb(vec3<f32>(hue, sat, 1.0));
    let warm = hsv2rgb(vec3<f32>(fract(hue + 0.05), sat, 1.0));
    let cool = hsv2rgb(vec3<f32>(fract(hue - 0.05), sat, 1.0));

    colorAccR = colorAccR + warm * g;
    colorAccB = colorAccB + cool * g;
    glowAcc  = glowAcc + g;
  }

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let chromaMix = smoothstep(0.0, 1.0, treble);
  var colorAcc = mix(colorAccR, colorAccB, chromaMix);
  colorAcc = mix(colorAcc, prev * 0.88, 0.45);

  let vign  = 1.0 - smoothstep(0.7, 1.4, length(p));
  colorAcc  = colorAcc * vign;
  let depth = clamp(glowAcc * 0.3, 0.0, 1.0);
  let alpha = clamp(length(colorAcc) * 0.7 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture,      coord, vec4<f32>(colorAcc, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(colorAcc, alpha));
}
