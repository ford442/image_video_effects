// ═══════════════════════════════════════════════════════════════════
//  Acid Lissajous
//  Category: generative
//  Features: lissajous-curves, audio-frequency, mouse-phase, neon-trails, depth-motion,
//            hypnotic-pattern, mouse-orbit, chromatic-strands, bass-strand-count, upgraded-rgba, aces-tone-map
//  Complexity: Medium
//  Updated: 2026-05-31
//  Upgraded: 2026-06-06
// ═══════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════
//  Lissajous figures drawn as glowing neon tubes with acid-trip
//  color cycling. Multiple harmonic pairs trace sinusoidal paths
//  whose phase ratios continuously drift, creating ever-evolving
//  knot patterns. Each strand is independently hue-shifted and
//  blooms with a soft radial glow.

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
const STRANDS: i32 = 7;
const SAMPLES: i32 = 180;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn strandGlow(d: f32, radius: f32) -> f32 {
  let core  = smoothstep(radius, 0.0, d);
  let bloom = smoothstep(radius * 4.0, 0.0, d) * 0.35;
  return core + bloom;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

  let speed      = mix(0.3, 2.5,  u.zoom_params.x);
  let complexity = mix(2.0, 9.0,  u.zoom_params.y);
  let glowWidth  = mix(0.012, 0.003, u.zoom_params.z);
  let feedback   = u.zoom_params.w;

  // Mouse orbit: strands rotate around mouse position
  let mouseOffset = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 0.5 * bass;
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0 - mouseOffset;

  var totalColor = vec3<f32>(0.0);
  var totalWeight = 0.0;

  // Bass drives strand count up to 9 total
  let activeStrands = STRANDS + i32(bass * 2.0);

  for (var si: i32 = 0; si < activeStrands; si = si + 1) {
    let sf    = f32(si);
    let freqX = floor(mix(1.0, complexity, sf / max(f32(STRANDS) - 1.0, 1.0)));
    let freqY = floor(freqX + select(1.0, 0.0, si % 2 == 0));
    let phase = sf * 0.63 + time * speed * (0.7 + sf * 0.11) * (1.0 + bass * 0.3);
    let hueBase = fract(sf / f32(activeStrands) + time * 0.07 * speed + mids * 0.15);

    var minDist = 1e9;
    for (var ti: i32 = 0; ti <= SAMPLES; ti = ti + 1) {
      let t   = f32(ti) / f32(SAMPLES) * TAU;
      let cx  = sin(freqX * t + phase) * (0.85 + treble * 0.12);
      let cy  = sin(freqY * t) * (0.85 + bass * 0.12);
      let d   = distance(p, vec2<f32>(cx, cy));
      minDist = min(minDist, d);
    }

    let glow  = strandGlow(minDist, glowWidth * (1.0 + bass * 0.6));
    let sat   = clamp(0.8 + treble * 0.2, 0.0, 1.0);
    let val   = glow * (1.5 + mids * 0.8);
    let rgb   = hsv2rgb(vec3<f32>(hueBase, sat, 1.0)) * val;
    totalColor  = totalColor + rgb;
    totalWeight = totalWeight + glow;
  }

  var histUV = uv;
  histUV.x = histUV.x + sin(time * 0.3) * 0.001;
  histUV.y = histUV.y + cos(time * 0.2) * 0.001;
  let prev = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  let fbMix = mix(0.05, 0.65, feedback);
  totalColor = mix(totalColor, prev * 0.92, fbMix);

  let vign = 1.0 - smoothstep(0.65, 1.3, length(p));
  totalColor = totalColor * vign;

  // Chromatic strand separation: R leads, B lags
  let chromaR = totalColor * vec3<f32>(1.1, 0.95, 0.85);
  let chromaB = totalColor * vec3<f32>(0.85, 0.95, 1.1);
  totalColor = mix(chromaR, chromaB, smoothstep(0.3, 0.7, treble));

  let depth = clamp(totalWeight * 0.4, 0.0, 1.0);
  let alpha = clamp(length(totalColor) + bass * 0.05, 0.0, 1.0);

  totalColor = acesToneMap(totalColor * 1.1);
  textureStore(writeTexture,      coord, vec4<f32>(totalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(totalColor, alpha));
}
