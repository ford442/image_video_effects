// Horse Tail Brocade — long straight golden streamers
// Upgraded (Batch 37, Algorithmist): drag-integrated ballistic streamers with
// terminal-velocity fall, temporal-coherent curl-style sway (replaces fake linear
// drift), twinkling star field, real generated depth from accumulated heat.
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
  config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const GRAVITY: f32 = 0.85;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn hash1(n: f32) -> f32 { return fract(sin(n*127.1)*43758.5453); }
fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx)*0.1031); p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y)*p3.z);
}
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv - c);
  return (exp(-d*d/(r*r*0.5)) + 0.35*exp(-d/(r*4.0)))*i;
}
// Ballistic arc with linear drag: a = -k*v + g_down. k -> 0 recovers ideal arc;
// finite k gives a terminal fall velocity, which is how real streamers behave.
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, k: f32) -> vec2<f32> {
  let kk = max(k, 0.001);
  let ek = (1.0 - exp(-kk * age)) / kk;
  let gy = g * (age - ek) / kk;
  return o + v * ek - vec2<f32>(0.0, gy);
}
// Temporal-coherent sway: smooth lateral wobble per spark (curl-style perturbation).
fn sway(seed: f32, age: f32) -> f32 {
  return valueNoise(vec2<f32>(seed * 41.3, age * 0.85)) - 0.5;
}
// Per-shell gust: slowly evolving shared wind so whole brocades lean together.
fn shellWind(center: vec2<f32>, time: f32, seed: f32) -> f32 {
  return valueNoise(center * 2.3 + vec2<f32>(seed * 11.7, time * 0.19)) - 0.5;
}
fn tailPos(o: vec2<f32>, dir: vec2<f32>, age: f32, fall: f32, spread: f32, seed: f32, gust: f32) -> vec2<f32> {
  // drag-integrated motion: initial drift velocity + terminal-velocity gravity
  let dragK = 0.10 + seed * 0.22;
  var p = sparkPos(o, dir * 0.15, age, fall * 0.9, dragK);
  // coherent lateral sway grows with age; stream Width slider widens it
  p.x += sway(seed, age) * (0.02 + spread * 0.35) * min(age, 2.5);
  p.x += gust * 0.05 * age * age * 0.3;
  return p;
}
fn goldPalette(gold: f32, seed: f32) -> vec3<f32> {
  let warm = vec3<f32>(1.0, 0.82, 0.3);
  let cool = vec3<f32>(0.9, 0.92, 1.0);
  return mix(mix(warm, cool, seed), vec3<f32>(1.0, 0.75, 0.2), (1.0 - gold)*0.35);
}
fn starField(uv: vec2<f32>, time: f32) -> vec3<f32> {
  let id = floor(uv*160.0);
  let h = hash2(id);
  let twinkle = 0.55 + 0.45 * sin(time * (1.5 + h * 2.5) + h * TAU * 7.0);
  return vec3<f32>(0.8, 0.9, 1.0)*step(0.992, h)*0.35*twinkle;
}
fn hexBokeh(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = uv - c;
  let q = vec2<f32>(d.x*1.2 + d.y*0.6, d.y);
  return softGlow(uv, c, r, i)*(0.7 + 0.3*smoothstep(r*0.5, r*1.5, length(q)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  // ---- screen setup ----
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) - res*0.5) / min(res.x, res.y);
  let sampleUV = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  // zoom_config.yz is 0-1 canvas uv (y=0 top) — map into centered aspect space
  let mouseUV = (u.zoom_config.yz - vec2<f32>(0.5)) * res / min(res.x, res.y);

  // ---- parameters & audio ----
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let tailLen = mix(0.4, 1.0, u.zoom_params.x);
  let spread = mix(0.02, 0.15, u.zoom_params.y);
  let gold = mix(0.4, 1.0, u.zoom_params.z);
  let fall = mix(0.25, 0.85, u.zoom_params.w);

  // ---- previous frame inputs (single sample each) ----
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let camera = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // ---- night sky base ----
  var col = vec3<f32>(0.008, 0.006, 0.02);
  col += starField(uv, time);
  col += camera * 0.04;

  var heat: f32 = 0.0;  // accumulated streamer energy -> generated depth

  // ---- horse-tail brocade bursts ----
  for (var s: i32 = 0; s < 6; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si*37.0 + 2.0);
    let cycle = 2.8 * (0.85 + seed * 0.35);
    let birth = floor((time * 0.55 + seed * 2.0) / cycle) * cycle - seed * 2.0;
    let age = time - birth;
    if (age < 0.0 || age > 8.0) { continue; }

    let bx = (seed - 0.5) * 1.5;
    let by = -0.76;
    let bDelay = 1.3 + seed * 0.5;
    let bAge = max(0.0, age - bDelay);
    let energy = (0.65 + bass * 0.5) * tailLen;
    if (energy < 0.01) { continue; }

    // ascending rocket trail
    if (age < bDelay) {
      let y = mix(by, by + 1.25, (age / bDelay) * (age / bDelay));
      let rocketGlow = softGlow(uv, vec2<f32>(bx, y), 0.009, energy * 2.0);
      col += vec3<f32>(1.0, 0.85, 0.4) * rocketGlow;
      heat += rocketGlow * 0.4;
    }

    // brocade burst and streamers
    if (bAge > 0.0 && bAge < 7.5) {
      let center = vec2<f32>(bx, by + 1.28);
      let fade = smoothstep(7.0, 0.5, bAge);
      let gust = shellWind(center, time, seed) * (0.8 + mids * 0.4);

      // core flash
      let flash = exp(-bAge * 6.0) * energy * hexBokeh(uv, center, 0.07, 1.5);
      col += vec3<f32>(1.0, 0.9, 0.5) * flash;
      heat += flash * 0.8;

      let n = i32(35.0 + energy * 45.0);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let js = hash1(si*79.0 + f32(j)*3.3);
        let js2 = hash1(si*23.0 + f32(j)*5.7);
        let dir = vec2<f32>((js - 0.5)*spread, 0.6 + js2*0.4);
        let streamLen = 6 + i32(tailLen * 8.0);

        // luminous streamer tail
        for (var t: i32 = 0; t < streamLen; t = t + 1) {
          let tf = f32(t) / f32(streamLen);
          let tAge = max(0.0, bAge - tf * 1.2);
          let sp = tailPos(center, dir, tAge, fall, spread, js, gust);
          let tFade = fade * (1.0 - tf * 0.6) * (0.5 + js2 * 0.5);
          let gc = goldPalette(gold, js);
          let glow = softGlow(uv, sp, 0.004 + js * 0.002, tFade * energy * 1.3);
          col += gc * glow;
          heat += glow * 0.3;
        }

        // silver micro-dust on treble
        if (treble > 0.3) {
          let sp = tailPos(center, dir, bAge, fall, spread, js, gust);
          let dust = softGlow(uv, sp, 0.002, treble * fade * 0.5);
          col += vec3<f32>(0.85, 0.9, 1.0) * dust;
          heat += dust * 0.2;
        }
      }
    }
  }

  // ---- mouse-triggered brocade cascade ----
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time * 0.7) * 4.5;
    if (mAge > 0.8) {
      let mb = mAge - 0.8;
      let mFade = smoothstep(3.5, 0.3, mb);
      let mGust = shellWind(mouseUV, time, 0.53);
      for (var k: i32 = 0; k < 30; k = k + 1) {
        let ks = hash1(f32(k)*2.1);
        let dir = vec2<f32>((ks - 0.5)*spread*2.0, 0.7);
        let sp = tailPos(mouseUV, dir, mb, fall, spread, ks, mGust);
        let mGlow = softGlow(uv, sp, 0.005, mFade);
        col += goldPalette(gold, ks) * mGlow;
        heat += mGlow * 0.3;
      }
    }
  }

  // ---- temporal blend & tone map ----
  let trailDecay = mix(0.9, 0.97, tailLen);
  col = mix(prev * trailDecay, col, 0.28);
  col = acesToneMap(col * 1.1);

  let alpha = clamp(length(col) * 1.2 + 0.1, 0.12, 0.96);
  // generated depth: bright streamer cores are near, empty sky is far
  let depth = clamp(1.0 - exp(-heat * 1.5), 0.0, 1.0) * 0.85;
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
