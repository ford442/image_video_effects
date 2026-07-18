// ═══ gen-fireworks-roman-candle ════════════════════════════════════
//  Category: generative
//  Features: audio-reactive, mouse-driven, fireworks, temporal, roman-candle,
//            aces-tone-map, ign-dither, premultiplied-alpha
//  Complexity: Medium

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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const NUM_TUBES: i32 = 6;
const NUM_SHOTS: i32 = 16;
const NUM_TRAILS: i32 = 5;
const NUM_BURST_SPARKS: i32 = 12;

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hash1(n: f32) -> f32 { return fract(sin(n*127.1)*43758.5453); }
fn hash2(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7)))*43758.5453123); }

fn starCol(i: f32) -> vec3<f32> {
  let cols = array<vec3<f32>, 5>(
    vec3<f32>(1.0,0.2,0.15), vec3<f32>(0.2,0.75,1.0), vec3<f32>(1.0,0.85,0.3),
    vec3<f32>(0.3,1.0,0.5), vec3<f32>(1.0,0.5,0.9));
  return cols[i32(i*4.99) % 5];
}

fn softGlow(d2: f32, r2: f32, i: f32) -> f32 {
  let gaussian = exp(-d2 / (r2 * 0.5));
  let halo = 0.35 * exp(-sqrt(max(d2, 0.0)) / (sqrt(max(r2, 0.0001)) * 3.0));
  return (gaussian + halo) * i;
}

fn hexBokehGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  var glow = 0.0;
  let r2 = r * r;
  for (var k = 0; k < 7; k = k + 1) {
    let d2 = length(uv - c - HEX_TAPS[k] * r * 0.5);
    glow += softGlow(d2 * d2, r2, i) * HEX_WEIGHTS[k];
  }
  return glow;
}

fn evalTubeStars(uv: vec2<f32>, time: f32, tubeX: f32, tubeY: f32,
                 fireRate: f32, starSize: f32, energy: f32, seed: f32) -> vec3<f32> {
  var acc = vec3<f32>(0.0);
  let shotInterval = 0.35 / fireRate;
  let cycle = f32(NUM_SHOTS) * shotInterval + 1.5;
  let baseCycle = floor(time / cycle) * cycle;
  for (var shot = 0; shot < NUM_SHOTS; shot = shot + 1) {
    let sf = f32(shot);
    let shotTime = sf * shotInterval + seed * 0.5;
    let birth = baseCycle + shotTime;
    let age = time - birth;
    let inLife = step(0.0, age) * step(age, 3.5);
    if (inLife < 0.5) { continue; }
    let fade = smoothstep(3.0, 0.1, age);
    let starY = tubeY + age * 1.8 * energy;
    let wobble = sin(age * 3.0 + seed * 10.0) * 0.02;
    let starPos = vec2<f32>(tubeX + wobble, starY);
    let sz = starSize * (1.0 + energy * 0.15);
    let g = hexBokehGlow(uv, starPos, sz, fade * energy * 2.0);
    acc += starCol(seed + sf * 0.1) * g;
    for (var tr = 1; tr < NUM_TRAILS; tr = tr + 1) {
      let trf = f32(tr) * 0.08;
      let trailPos = vec2<f32>(starPos.x, starY - trf * 0.15);
      let trailFade = fade * energy * (1.0 - trf * 0.8) * 0.7;
      acc += starCol(seed) * hexBokehGlow(uv, trailPos, sz * 0.6, trailFade);
    }
    let burstWindow = step(1.2, age) * step(age, 2.5);
    let bAge = (age - 1.2) * burstWindow;
    let burstY = tubeY + 1.2 * energy;
    let burstC = vec2<f32>(tubeX, burstY);
    for (var sp = 0; sp < NUM_BURST_SPARKS; sp = sp + 1) {
      let ang = f32(sp) / f32(NUM_BURST_SPARKS) * TAU;
      let bp = burstC + vec2<f32>(cos(ang), sin(ang)) * bAge * 0.25 * energy;
      acc += starCol(seed) * hexBokehGlow(uv, bp, sz * 0.8, fade * exp(-bAge * 2.0) * energy * 0.8) * burstWindow;
    }
  }
  return acc;
}

fn mouseCandle(uv: vec2<f32>, time: f32, mouseUV: vec2<f32>, fireRate: f32,
               starSize: f32, bass: f32, enabled: f32) -> vec3<f32> {
  var acc = vec3<f32>(0.0);
  let mAge = fract(time * 1.5);
  let shots = i32(5.0 + fireRate * 5.0);
  for (var s = 0; s < shots; s = s + 1) {
    let sa = f32(s) * 0.15;
    let inShot = step(sa, mAge) * step(mAge, sa + 0.4);
    let localAge = (mAge - sa) * inShot;
    let sp = mouseUV + vec2<f32>(0.0, localAge * 1.5);
    let fade = (1.0 - localAge * 2.5) * (0.8 + bass);
    acc += starCol(f32(s) * 0.2) * hexBokehGlow(uv, sp, starSize * 1.5, fade) * enabled;
  }
  return acc;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;
  let mouseUV = (u.zoom_config.yz - res * 0.5) / min(res.x, res.y);
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;

  let fireRate = mix(0.3, 1.2, u.zoom_params.x);
  let starSize = mix(0.004, 0.014, u.zoom_params.y);
  let tubeSpread = mix(0.3, 1.0, u.zoom_params.z);
  let trailLen = mix(0.88, 0.96, u.zoom_params.w);

  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let readDepth = textureLoad(readDepthTexture, pixel, 0).r;

  // Early-exit background: keep only faint sky and temporal trail where no fireworks live
  var col = vec3<f32>(0.01, 0.008, 0.022);
  let horizonFade = smoothstep(-0.95, -0.75, uv.y);
  col *= horizonFade;

  for (var t = 0; t < NUM_TUBES; t = t + 1) {
    let tf = f32(t);
    let seed = hash1(tf * 19.0 + 1.0);
    let tubeX = (seed - 0.5) * 1.8 * tubeSpread;
    let tubeY = -0.82;
    let energy = (0.7 + bass * 0.5) * (1.0 + seed * 0.2);
    col += evalTubeStars(uv, time, tubeX, tubeY, fireRate, starSize, energy, seed);
    col += vec3<f32>(0.8, 0.4, 0.1) * hexBokehGlow(uv, vec2<f32>(tubeX, tubeY), 0.012, 0.4 + treble * 0.3);
  }

  let mouseActive = step(0.5, u.zoom_config.w);
  col += mouseCandle(uv, time, mouseUV, fireRate, starSize, bass, mouseActive);

  col = mix(prev * trailLen, col, 0.35);
  let dust = step(0.987 - treble * 0.03, hash2(uv + vec2<f32>(time * 8.0, 0.0)));
  col += vec3<f32>(0.7, 0.85, 1.0) * dust * treble * 0.5;

  col = acesToneMap(col * 1.08);
  col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

  let intensity = clamp(length(col) * 1.1 + 0.14, 0.14, 0.96);
  let depth = 0.02 + readDepth * 0.08;
  let semanticAlpha = mix(intensity, depth, 0.25);

  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.5 + prev * 0.4, semanticAlpha));
  textureStore(dataTextureA, pixel, vec4<f32>(col, semanticAlpha));
  textureStore(writeTexture, pixel, vec4<f32>(col * semanticAlpha, semanticAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
