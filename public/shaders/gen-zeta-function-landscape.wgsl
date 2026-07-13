// ═══════════════════════════════════════════════════════════════════
//  Zeta Function Landscape — optimized
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, aces-tone-map, temporal-smoothing,
//            chromatic-zeros, bass-term-modulation, depth-output, lod-scaling, hex-bokeh,
//            semantic-alpha, branchless-hot-path
//  Complexity: High
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
const MIN_TERMS: i32 = 30;
const MAX_TERMS: i32 = 220;

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn zetaApprox(s_re: f32, s_im: f32, terms: i32) -> vec2<f32> {
  var sum_re = 0.0;
  var sum_im = 0.0;
  for (var n: i32 = 1; n <= terms; n = n + 1) {
    let ln_n = log(f32(n));
    let phase = -s_im * ln_n;
    let c = cos(phase);
    let s = sin(phase);
    let denom = exp(-s_re * ln_n);
    sum_re = sum_re + denom * c;
    sum_im = sum_im + denom * s;
  }
  return vec2<f32>(sum_re, sum_im);
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

fn hexBokehSample(tex: texture_2d<f32>, smp: sampler, uv: vec2<f32>, radius: f32) -> vec3<f32> {
  var sum = vec3<f32>(0.0);
  for (var i = 0; i < 7; i = i + 1) {
    let off = HEX_TAPS[i] * radius;
    sum += textureSampleLevel(tex, smp, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * HEX_WEIGHTS[i];
  }
  return sum;
}

fn landscapeColor(z_mag: f32, z_arg: f32, time: f32, bass: f32, mids: f32, treble: f32,
                  uv_x: f32, ridge: f32) -> vec3<f32> {
  let zeroProximity = 1.0 / (1.0 + z_mag * z_mag * 0.5);
  let hue = fract(z_arg + time * 0.02 + mids * 0.1 + uv_x * 0.2);
  let zeroHue = mix(hue, 0.5 + treble * 0.2, zeroProximity * 0.5);
  let sat = mix(0.5, 1.0, ridge + bass * 0.3);
  let height = log(1.0 + z_mag) * 0.3;
  let val = mix(0.2, 1.0, height + zeroProximity * 0.5);
  return hue2rgb(zeroHue) * sat + vec3<f32>(1.0 - sat) * val;
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

  // Early-exit: background sky with faint grid
  let bgGrid = smoothstep(0.98, 1.0, hash21(uv * 200.0 + vec2<f32>(time * 0.05, 0.0)));
  var bg = vec3<f32>(0.02, 0.025, 0.04) + vec3<f32>(0.03, 0.04, 0.06) * bgGrid;

  let sigma = 0.5 + (param1 - 0.5) * 0.3;
  let t_min = -20.0 - param2 * 40.0 + bass * 5.0;
  let t_max = 20.0 + param2 * 40.0 - bass * 5.0;
  let t_range = t_max - t_min;

  let t = t_min + uv.x * t_range + (mouse.x - 0.5) * 10.0;
  let y_offset = (uv.y - 0.5) * 8.0 * (1.0 + param3 * 2.0) + (0.5 - mouse.y) * 4.0;

  // LOD: fewer terms where the signal changes slowly (peripheral y_offset)
  let lodFactor = 1.0 - smoothstep(2.0, 8.0, abs(y_offset));
  let termT = clamp(param4 + treble * 0.3, 0.0, 1.0) * lodFactor;
  let terms = i32(mix(f32(MIN_TERMS), f32(MAX_TERMS), termT));

  let z = zetaApprox(sigma, t + y_offset * 0.1, terms);
  let z_mag = sqrt(z.x * z.x + z.y * z.y);
  let z_arg = atan2(z.y, z.x) / TAU;

  let height = log(1.0 + z_mag) * 0.3;
  let ridge = smoothstep(0.5, 1.5, height);

  let rgb = landscapeColor(z_mag, z_arg, time, bass, mids, treble, uv.x, ridge);

  // Hex-bokeh temporal smoothing for landscape stability
  let blurRadius = 0.0015 + bass * 0.001;
  let blurredPrev = hexBokehSample(dataTextureC, u_sampler, uv, blurRadius);
  let mixWeight = 0.08 + bass * 0.02;
  let smoothed = mix(rgb, blurredPrev, mixWeight);

  let val = mix(0.2, 1.0, height + (1.0 / (1.0 + z_mag * z_mag * 0.5)) * 0.5);
  var color = acesToneMap((smoothed * val) * 1.1);

  // Branchless background blend: low-height regions fade to sky
  let fgMask = smoothstep(0.08, 0.25, height + ridge * 0.15);
  color = mix(bg, color, fgMask);

  let alpha = clamp(height * 0.7 + ridge * 0.3 + bass * 0.05, 0.0, 1.0);
  let semanticAlpha = mix(0.15, alpha, fgMask) * (0.7 + depth * 0.3);
  let finalColor = vec4<f32>(color, semanticAlpha);

  textureStore(writeTexture, pixel, finalColor);
  textureStore(dataTextureA, pixel, finalColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(height, 0.0, 0.0, 0.0));
}
