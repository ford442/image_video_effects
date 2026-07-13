// ═══════════════════════════════════════════════════════════════════
//  Cycloid Bloom
//  Category: generative
//  Features: audio-reactive, temporal, psychedelic, procedural, mouse-distortion,
//            chromatic-layer-separation, depth-output, upgraded-rgba, aces-tone-map,
//            hdr-aces, oklab-mix, blackbody-core, fresnel-rim, volumetric-glow
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-07-13
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn huePreservingClamp(col: vec3<f32>, maxVal: f32) -> vec3<f32> {
    let mx = max(max(col.r, col.g), col.b);
    let scale = min(mx, maxVal) / max(mx, 0.0001);
    return col * scale;
}

fn rgbToOkLab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        0.8189330101, 0.3618667424, -0.1288597137,
        0.0329845436, 0.9293118715, 0.0361456387,
        0.0482003018, 0.2643662691, 0.6338517070
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
    return mat3x3<f32>(
        0.2104542553, 0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050, 0.4505937099,
        0.0259040371, 0.7827717662, -0.8086757660
    ) * lms_;
}

fn okLabToRgb(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        1.0, 0.3963377774, 0.2158037573,
        1.0, -0.1055613458, -0.0638541728,
        1.0, -0.0894841775, -1.2914855480
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        4.0767416621, -3.3077115913, 0.2309699292,
        -1.2684380046, 2.6097574011, -0.3413193965,
        -0.0041960863, -0.7034186147, 1.7076147010
    ) * lms;
}

fn blackbody(t: f32) -> vec3<f32> {
    let T = mix(1800.0, 14000.0, clamp(t, 0.0, 1.0));
    let g = clamp(0.0001 * T - 0.05, 0.0, 1.0);
    let b = clamp(0.00004 * (T - 4200.0), 0.0, 1.0);
    return vec3<f32>(1.0, g, b) * (T / 5000.0);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let h = dot(i, vec2<f32>(127.1, 311.7));
    let a = fract(sin(h) * 43758.5453123);
    let b = fract(sin(h + 127.1) * 43758.5453123);
    let c = fract(sin(h + 311.7) * 43758.5453123);
    let d = fract(sin(h + 438.8) * 43758.5453123);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
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
      let closer = f32(di < minDist);
      minDist = mix(minDist, di, closer);
      bestT   = mix(bestT, t, closer);
    }

    let w    = glowWidth * (1.0 + bass * 0.7) * (1.3 - lf * 0.15);
    let g    = smoothstep(w * 3.5, 0.0, minDist) + smoothstep(w * 7.0, 0.0, minDist) * 0.3;
    let hue  = fract(lf / f32(LAYERS) + time * spinSpeed * 0.09 + bestT * 0.04 + mids * 0.2);
    let sat  = 0.82 + treble * 0.18;
    colorAcc = colorAcc + hsv2rgb(vec3<f32>(hue, sat, 1.0)) * g;
    glowAcc  = glowAcc + g;
  }

  let chromaR = colorAcc * vec3<f32>(1.1, 0.95, 0.85);
  let chromaB = colorAcc * vec3<f32>(0.85, 0.95, 1.1);
  colorAcc = mix(chromaR, chromaB, smoothstep(0.0, 1.0, treble));

  let coreTemp = 0.35 + bass * 0.25 + mids * 0.15;
  let coreGlow = blackbody(coreTemp) * exp(-length(p) * 2.5) * (1.0 + bass);
  colorAcc = colorAcc + coreGlow;

  let fresnel = pow(1.0 - smoothstep(0.0, 1.2, length(p)), 3.0);
  let rim = vec3<f32>(0.5, 0.8, 1.0) * fresnel * glowAcc * (1.0 + treble) * 0.4;
  colorAcc = colorAcc + rim;

  let prev  = textureLoad(dataTextureC, coord, 0).rgb;
  let fbMix = mix(0.05, 0.70, feedback);
  colorAcc = mix(colorAcc, prev * 0.90, fbMix);

  let vign  = 1.0 - smoothstep(0.7, 1.45, length(p));
  colorAcc  = colorAcc * vign;

  let volGlow = vec3<f32>(0.2, 0.5, 0.7) * glowAcc * 0.15 * (1.0 + mids);
  colorAcc = colorAcc + volGlow;

  let okBloom = rgbToOkLab(colorAcc);
  let okWarm = rgbToOkLab(blackbody(0.45 + bass * 0.2));
  let okMix = mix(okBloom, okWarm, 0.2 + bass * 0.1);
  colorAcc = okLabToRgb(okMix);

  let depth = clamp(glowAcc * 0.35, 0.0, 1.0);
  let alpha = clamp(length(colorAcc) * 0.75 + bass * 0.05, 0.0, 1.0);

  colorAcc = huePreservingClamp(colorAcc, 7.0);
  colorAcc = acesToneMap(colorAcc * 1.15);
  textureStore(writeTexture,      coord, vec4<f32>(colorAcc, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(colorAcc, alpha));
}
