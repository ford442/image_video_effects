// Fan Shell Spread — wide hemisphere fan burst
// Upgraded (Batch 37, Algorithmist): physically-grounded ballistic + linear-drag
// spark integration, temporal-coherent wind advection, per-spark flutter noise,
// twinkling star field, real generated depth from accumulated spark heat.
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
  return (exp(-d*d/(r*r*0.5)) + 0.3*exp(-d/(r*3.0)))*i;
}
// Ballistic arc with linear drag: a = -k*v + g_down. k -> 0 recovers ideal arc.
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, k: f32) -> vec2<f32> {
  let kk = max(k, 0.001);
  let ek = (1.0 - exp(-kk * age)) / kk;
  let gy = g * (age - ek) / kk;
  return o + v * ek - vec2<f32>(0.0, gy);
}
// Temporal-coherent shell wind: smoothly evolving 2D gust per burst center.
fn shellWind(center: vec2<f32>, time: f32, seed: f32) -> vec2<f32> {
  let q = center * 2.7 + vec2<f32>(seed * 13.7, seed * 7.1);
  let wx = valueNoise(q + vec2<f32>(time * 0.23, 0.0)) - 0.5;
  let wy = valueNoise(q + vec2<f32>(5.2, 1.3) - vec2<f32>(0.0, time * 0.17)) - 0.5;
  return vec2<f32>(wx, wy);
}
// Per-spark flutter: tiny coherent wobble so trails are not ruler-straight.
fn flutter(seed: f32, age: f32) -> vec2<f32> {
  let p = vec2<f32>(seed * 31.4, age * 1.9);
  return vec2<f32>(valueNoise(p), valueNoise(p + vec2<f32>(9.3, 4.7))) - vec2<f32>(0.5);
}
fn palette(t: f32) -> vec3<f32> {
  let h = fract(t);
  let r = abs(h*6.0 - 3.0) - 1.0;
  let g = abs(h*6.0 - 2.0) - 1.0;
  let b = abs(h*6.0 - 4.0) - 1.0;
  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
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
  let fanAngle = mix(0.35, 1.55, u.zoom_params.x);
  let power = mix(0.45, 1.5, u.zoom_params.y);
  let density = mix(0.35, 1.1, u.zoom_params.z);
  let hueCycle = u.zoom_params.w;

  // ---- previous frame inputs (single sample each) ----
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let camera = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // ---- night sky base ----
  var col = vec3<f32>(0.01, 0.008, 0.024);
  col += starField(uv, time);
  col += camera * 0.04;

  var heat: f32 = 0.0;  // accumulated spark energy -> generated depth

  // ---- fan shell bursts ----
  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 31.0 + 3.0);
    let cycle = 2.1 * (0.85 + seed * 0.35);
    let birth = floor((time * 0.7 + seed * 1.5) / cycle) * cycle - seed * 1.5;
    let age = time - birth;
    if (age < 0.0 || age > 6.0) { continue; }

    let bx = (seed - 0.5) * 1.55;
    let by = -0.78;
    let bDelay = 1.1 + seed * 0.45;
    let bAge = max(0.0, age - bDelay);
    let energy = power * (0.7 + bass * 0.6);
    if (energy < 0.01) { continue; }

    // ascending rocket trail
    if (age < bDelay) {
      let y = mix(by, by + 1.2, (age / bDelay) * (age / bDelay));
      let rocketGlow = softGlow(uv, vec2<f32>(bx, y), 0.009, energy * 2.0);
      col += vec3<f32>(1.0, 0.88, 0.55) * rocketGlow;
      heat += rocketGlow * 0.4;
    }

    // fan burst
    if (bAge > 0.0 && bAge < 5.5) {
      let center = vec2<f32>(bx, by + 1.22);
      let fade = smoothstep(5.0, 0.3, bAge);
      let halfFan = fanAngle * (0.5 + mids * 0.3);
      let wind = shellWind(center, time, seed);
      let windGain = 0.10 + mids * 0.06;

      // core flash
      let flash = exp(-bAge * 10.0) * energy * hexBokeh(uv, center, 0.065, 1.5);
      col += vec3<f32>(1.0) * flash;
      heat += flash * 0.8;

      let n = i32(30.0 + density * 60.0);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 67.0 + jf * 3.1);
        let fanT = jf / f32(n) - 0.5;
        let ang = fanT * halfFan * PI + (js - 0.5) * 0.15;
        let spd = (0.4 + js * 0.35) * energy;
        let vel = vec2<f32>(sin(ang) * spd, cos(ang) * spd * 0.7 + 0.15);
        // drag varies per spark: heavy sparks push through, light ones hang
        let dragK = 0.08 + js * 0.30;
        var sp = sparkPos(center, vel, bAge, GRAVITY, dragK);
        // temporal-coherent wind advection grows with age^2 (gust integration)
        sp += wind * windGain * bAge * bAge;
        sp += flutter(js, bAge) * 0.012 * (0.3 + bAge * 0.4);

        // main spark
        let h = fract(js + hueCycle + time * 0.02);
        let sc = palette(h) * (0.85 + treble * 0.25);
        let glow = softGlow(uv, sp, 0.005 + js * 0.004, fade * energy * (0.85 + treble * 0.4));
        col += sc * glow;
        heat += glow * 0.35;

        // faint trailing echo, domain-warped by the same flutter field
        let echoAge = max(0.0, bAge - 0.08);
        var echo = sparkPos(center, vel, echoAge, GRAVITY, dragK);
        echo += wind * windGain * echoAge * echoAge;
        echo += flutter(js, echoAge) * 0.012 * (0.3 + echoAge * 0.4);
        col += sc * softGlow(uv, echo, 0.007, glow * 0.35);
      }
    }
  }

  // ---- mouse-triggered personal fan ----
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time * 1.0) * 3.2;
    if (mAge > 0.6) {
      let mb = mAge - 0.6;
      let halfF = fanAngle * 0.6;
      let mFade = smoothstep(2.5, 0.1, mb);
      let mWind = shellWind(mouseUV, time, 0.77);
      for (var k: i32 = 0; k < 35; k = k + 1) {
        let fanT = f32(k) / 35.0 - 0.5;
        let ang = fanT * halfF * PI;
        let vel = vec2<f32>(sin(ang), cos(ang) * 0.6 + 0.2) * power * 0.5;
        var sp = sparkPos(mouseUV, vel, mb, GRAVITY, 0.18);
        sp += mWind * 0.08 * mb * mb;
        let h = fract(f32(k) * 0.1 + hueCycle);
        let mGlow = softGlow(uv, sp, 0.006, mFade * power);
        col += palette(h) * mGlow;
        heat += mGlow * 0.3;
      }
    }
  }

  // ---- temporal blend & tone map ----
  col = mix(prev * 0.92, col, 0.32);
  col = acesToneMap(col * 1.1);

  let alpha = clamp(length(col) * 1.2 + 0.1, 0.12, 0.96);
  // generated depth: bright burst cores are near, empty sky is far
  let depth = clamp(1.0 - exp(-heat * 1.5), 0.0, 1.0) * 0.85;
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
