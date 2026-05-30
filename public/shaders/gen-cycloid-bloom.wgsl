// ═══════════════════════════════════════════════════════════════════
//  Cycloid Bloom
//  Category: generative
//  Features: audio-reactive, temporal, psychedelic, procedural, mouse-distortion,
//            chromatic-layer-separation, depth-output, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════
//  Nested hypotrochoid and epicycloid curves layered to form a
//  blooming flower/mandala. Multiple gear-ratio pairs evolve slowly,
//  each petal glowing with a prismatic hue that shifts with audio
//  and time. Feedback accumulation burns in bright arcs.

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
const LAYERS: i32 = 5;
const STEPS:  i32 = 240;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn hypotrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
  let x = (R - r) * cos(t) + d * cos((R - r) / r * t);
  let y = (R - r) * sin(t) - d * sin((R - r) / r * t);
  return vec2<f32>(x, y);
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

  let spinSpeed  = mix(0.15, 2.0, u.zoom_params.x);
  let petalMult  = mix(1.0, 4.0,  u.zoom_params.y);
  let glowWidth  = mix(0.02, 0.004, u.zoom_params.z);
  let feedback   = u.zoom_params.w;

  // Mouse-driven distortion: mouse pulls the bloom center
  let mousePull = (mouse - 0.5) * 0.3;
  let p = (uv - 0.5 + mousePull * bass) * vec2<f32>(aspect, 1.0) * 2.4;

  var colorAcc = vec3<f32>(0.0);
  var glowAcc  = 0.0;

  for (var li: i32 = 0; li < LAYERS; li = li + 1) {
    let lf   = f32(li);
    let R    = 1.0;
    let rInner = 1.0 / (3.0 + lf * petalMult);
    let d    = rInner * (0.55 + 0.4 * sin(time * 0.07 * spinSpeed + lf * 1.2));
    let phaseOff = lf * 0.47 + time * spinSpeed * (0.12 + lf * 0.08) * (1.0 + bass * 0.4);
    let scale = 0.88 - lf * 0.1;

    var minDist = 1e9;
    var bestT   = 0.0;
    for (var si: i32 = 0; si <= STEPS; si = si + 1) {
      let t   = f32(si) / f32(STEPS) * TAU * (1.0 / rInner);
      let pt  = hypotrochoid(t + phaseOff, R, rInner, d) * scale;
      let di  = distance(p, pt);
      if (di < minDist) {
        minDist = di;
        bestT   = t;
      }
    }

    let w    = glowWidth * (1.0 + bass * 0.7) * (1.3 - lf * 0.15);
    let g    = smoothstep(w * 3.5, 0.0, minDist) + smoothstep(w * 7.0, 0.0, minDist) * 0.3;
    let hue  = fract(lf / f32(LAYERS) + time * spinSpeed * 0.09 + bestT * 0.04 + mids * 0.2);
    let sat  = 0.82 + treble * 0.18;
    colorAcc = colorAcc + hsv2rgb(vec3<f32>(hue, sat, 1.0)) * g;
    glowAcc  = glowAcc + g;
  }

  // Chromatic layer separation: R from outer layers, B from inner
  let chromaR = colorAcc * vec3<f32>(1.1, 0.95, 0.85);
  let chromaB = colorAcc * vec3<f32>(0.85, 0.95, 1.1);
  colorAcc = mix(chromaR, chromaB, smoothstep(0.0, 1.0, treble));

  let prev  = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let fbMix = mix(0.05, 0.70, feedback);
  colorAcc = mix(colorAcc, prev * 0.90, fbMix);

  let vign  = 1.0 - smoothstep(0.7, 1.45, length(p));
  colorAcc  = colorAcc * vign;
  let depth = clamp(glowAcc * 0.35, 0.0, 1.0);
  let alpha = clamp(length(colorAcc) * 0.75 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture,      coord, vec4<f32>(colorAcc, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(colorAcc, alpha));
}
