// ═══════════════════════════════════════════════════════════════════
//  Wind & Ripple Fireworks
//  Category: generative
//  Features: wind-drifted sparks, ripple-triggered barrages, audio-reactive,
//            mouse command shell, temporal trails, aces-tone-map,
//            semantic alpha, depth-aware
//  Complexity: Medium
//  Created: 2026-07-05
// ═══════════════════════════════════════════════════════════════════
//  Sparks drift on a time-varying wind. Ripples from the UI become
//  ignition points that launch directed radial barrages. Bass deepens
//  shells, mids add secondary gusts, treble puts silver micro-sparkle
//  in the wind. Mouse click/hold launches a personal shell at the cursor.
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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453123); }
fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var v = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { v += a * vnoise(p * f); f *= 2.02; a *= 0.5; }
  return v;
}

fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv - c);
  return (exp(-d * d / (r * r * 0.5)) + 0.3 * exp(-d / (r * 3.0))) * i;
}

// Gravity + drag + wind push (wind integrated over age)
fn sparkPosWind(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, drag: f32, wind: vec2<f32>) -> vec2<f32> {
  let t = age;
  let df = exp(-drag * t);
  let windPush = wind * t * (1.0 - exp(-t * 0.4));
  return o + vec2<f32>(v.x * df + windPush.x, v.y * df - g * t * t * 0.5 + windPush.y * 0.5);
}

fn shellColor(hue: f32, hot: f32) -> vec3<f32> {
  let gold = vec3<f32>(1.0, 0.82, 0.3);
  let red  = vec3<f32>(1.0, 0.2, 0.12);
  let blue = vec3<f32>(0.3, 0.7, 1.0);
  let teal = vec3<f32>(0.2, 0.95, 0.6);
  var col = mix(gold, red, smoothstep(0.0, 0.33, hue));
  col = mix(col, blue, smoothstep(0.33, 0.66, hue));
  col = mix(col, teal, smoothstep(0.66, 1.0, hue));
  return mix(col, vec3<f32>(1.0, 0.97, 0.92), hot);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;

  let mouse = vec2<f32>(u.zoom_config.yz);
  let mouseDown = u.zoom_config.w;
  let mouseUV = (mouse - res * 0.5) / min(res.x, res.y);

  let energy = mix(0.45, 1.45, u.zoom_params.x);
  let windAmt = mix(0.03, 0.42, u.zoom_params.x);
  let rippleSens = mix(0.25, 1.0, u.zoom_params.y);
  let trailLen = mix(0.88, 0.97, u.zoom_params.z);
  let colorDrift = u.zoom_params.w;

  let windAngle = time * 0.22 + colorDrift * PI;
  let wind = vec2<f32>(cos(windAngle), sin(windAngle) * 0.35) * windAmt;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  var col = vec3<f32>(0.012, 0.01, 0.028);
  let star = step(0.992, hash2(floor(uv * 135.0))) * (0.5 + 0.5 * sin(time * 4.0 + hash2(uv * 60.0) * 20.0));
  col += vec3<f32>(0.78, 0.85, 1.0) * star * 0.65;

  // ── Regular mortar shells ──
  let numShells = 7;
  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 23.0 + 4.0);
    let seed2 = hash1(si * 41.0 + 9.0);

    let cycle = 2.1 * (0.8 + seed * 0.5) / (1.0 + bass * 0.25);
    let birth = floor((time + seed * 2.3) / cycle) * cycle - seed * 2.3;
    let age = time - birth;
    if (age < 0.0 || age > 7.5) { continue; }

    let baseX = (seed - 0.5) * 1.7 + wind.x * age * 0.25;
    let baseY = -0.78;
    let burstDelay = 1.1 + seed * 0.7;
    let burstAge = max(0.0, age - burstDelay);
    let shellEnergy = energy * (0.7 + bass * 0.8);
    let hue = fract(seed * 1.6 + colorDrift * 0.6 + time * 0.015);

    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(baseY, baseY + 1.3, t * t);
      col += vec3<f32>(1.0, 0.9, 0.6) * softGlow(uv, vec2<f32>(baseX, y), 0.009, shellEnergy * 2.2);
    }

    if (burstAge > 0.0 && burstAge < 5.5) {
      let center = vec2<f32>(baseX, baseY + 1.28);
      let fade = smoothstep(5.0, 0.3, burstAge);

      // Core flash
      col += vec3<f32>(1.0, 0.95, 0.85) * exp(-burstAge * 10.0) * shellEnergy * softGlow(uv, center, 0.06, 1.6);

      let nSparks = i32(32.0 + energy * 40.0 + mids * 14.0);
      for (var j: i32 = 0; j < nSparks; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 71.0 + jf * 4.1);
        let js2 = hash1(si * 17.0 + jf * 6.3);
        let ang = (jf / f32(nSparks)) * TAU + (js - 0.5) * 0.7;
        let spd = (0.48 + js2 * 0.55) * shellEnergy;
        let vel = vec2<f32>(cos(ang), sin(ang)) * spd;
        let sp = sparkPosWind(center, vel, burstAge, 1.05, 0.2, wind * (0.8 + js * 0.4));
        let sz = 0.006 + js * 0.004;
        let g = softGlow(uv, sp, sz, fade * shellEnergy * 1.5);
        col += shellColor(hue + js * 0.25, smoothstep(0.4, 0.0, burstAge * 0.2)) * g;
      }

      // Silver wind micro-sparkle (treble)
      if (treble > 0.25) {
        let microN = i32(4.0 + treble * 10.0);
        for (var m: i32 = 0; m < microN; m = m + 1) {
          let mf = f32(m);
          let ms = hash1(si * 53.0 + mf * 7.0);
          let mAng = ms * TAU + time * 2.0;
          let mVel = vec2<f32>(cos(mAng), sin(mAng)) * (0.25 + ms * 0.35);
          let mPos = sparkPosWind(center, mVel, burstAge * 0.7, 0.7, 0.3, wind * 1.3);
          col += vec3<f32>(0.8, 0.92, 1.0) * softGlow(uv, mPos, 0.003, fade * treble * 0.9);
        }
      }
    }
  }

  // ── Ripple-triggered barrages ──
  for (var r: i32 = 0; r < 50; r = r + 1) {
    let ripple = u.ripples[r];
    let rAge = time - ripple.z;
    let strength = ripple.w;
    if (rAge < 0.0 || rAge > 1.4 || strength < (1.0 - rippleSens) * 0.6) { continue; }

    let rCenter = (ripple.xy - vec2<f32>(0.5)) * res / min(res.x, res.y);
    let rSparks = i32(18.0 + strength * 34.0 + mids * 12.0);
    let rFade = smoothstep(1.4, 0.1, rAge);

    for (var j: i32 = 0; j < rSparks; j = j + 1) {
      let jf = f32(j);
      let js = hash1(f32(r) * 31.0 + jf * 5.0);
      let ang = (jf / f32(rSparks)) * TAU + js;
      let spd = (0.35 + js * 0.45) * strength;
      let vel = vec2<f32>(cos(ang), sin(ang)) * spd;
      let sp = sparkPosWind(rCenter, vel, rAge, 0.9, 0.25, wind * 0.7);
      let g = softGlow(uv, sp, 0.005 + js * 0.003, rFade * strength * 1.8);
      col += shellColor(fract(js + colorDrift), 0.4) * g;
    }
  }

  // ── Mouse command shell ──
  if (mouseDown > 0.5) {
    let mAge = fract(time * 0.85) * 4.2;
    if (mAge > 0.9 && mAge < 5.0) {
      let mbAge = mAge - 0.9;
      let mCenter = mouseUV + vec2<f32>(0.0, 0.1);
      let mEnergy = energy * (1.3 + bass);
      let mFade = smoothstep(4.5, 0.2, mbAge);
      col += vec3<f32>(1.0, 0.95, 0.8) * exp(-mbAge * 8.0) * mEnergy * softGlow(uv, mCenter, 0.07, 1.5);

      let mSparks = i32(45.0 + energy * 45.0);
      for (var k: i32 = 0; k < mSparks; k = k + 1) {
        let ks = hash1(f32(k) * 2.7 + 2.0);
        let ang = (f32(k) / f32(mSparks)) * TAU + (ks - 0.5) * 0.8;
        let vel = vec2<f32>(cos(ang), sin(ang)) * (0.6 + ks * 0.7) * mEnergy;
        let sp = sparkPosWind(mCenter, vel, mbAge, 1.0, 0.18, wind * 0.9);
        let g = softGlow(uv, sp, 0.0065, mFade * mEnergy);
        col += shellColor(fract(ks * 1.4 + colorDrift), 0.5) * g;
      }
    }
  }

  // ── Temporal trails / wind haze ──
  let haze = fbm(uv * 2.2 + vec2<f32>(time * 0.012, -time * 0.008) + wind * 2.0, 2) * 0.02;
  col = mix(prev * trailLen + haze, col, 0.28);

  let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
  col *= clamp(vig, 0.15, 1.0) * (0.7 + depth * 0.55);

  col = acesToneMap(col * 1.08);
  let alpha = clamp(length(col) * 1.1 + 0.13, 0.14, 0.96);

  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.55 + prev * 0.38, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
