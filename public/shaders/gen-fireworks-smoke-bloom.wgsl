// ═══════════════════════════════════════════════════════════════════
//  Smoke Bloom Fireworks
//  Category: generative
//  Features: volumetric smoke puffs, feedback light bloom, gravity sparks,
//            audio-reactive, mouse command shell, temporal trails,
//            aces-tone-map, semantic alpha, depth-aware
//  Complexity: Medium-High
//  Created: 2026-07-05
// ═══════════════════════════════════════════════════════════════════
//  Soft volumetric smoke gathers around bursts and along falling sparks.
//  A cheap neighbor-feedback bloom adds luminous halos to bright areas.
//  Bass swells the smoke glow, mids add secondary burst layers, treble
//  scatters micro-sparks. Mouse launches a smoky peony at the cursor.
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

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, drag: f32) -> vec2<f32> {
  let t = age;
  let df = exp(-drag * t);
  return o + vec2<f32>(v.x * df, v.y * df - g * t * t * 0.5);
}

fn shellColor(hue: f32, hot: f32) -> vec3<f32> {
  let gold = vec3<f32>(1.0, 0.82, 0.3);
  let crimson = vec3<f32>(1.0, 0.22, 0.15);
  let violet = vec3<f32>(0.55, 0.35, 1.0);
  let cyan = vec3<f32>(0.2, 0.9, 0.95);
  var col = mix(gold, crimson, smoothstep(0.0, 0.33, hue));
  col = mix(col, violet, smoothstep(0.33, 0.66, hue));
  col = mix(col, cyan, smoothstep(0.66, 1.0, hue));
  return mix(col, vec3<f32>(1.0, 0.97, 0.92), hot);
}

fn smokePuff(uv: vec2<f32>, center: vec2<f32>, age: f32, density: f32, time: f32) -> f32 {
  let q = (uv - center) * 6.0;
  let n = fbm(q + vec2<f32>(time * 0.015, age * 0.08), 3);
  let d = length(uv - center);
  return n * exp(-d * d * 1.8) * density;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;
  let uv01 = vec2<f32>(pixel) / res;
  let ps = 1.0 / res;

  let mouse = vec2<f32>(u.zoom_config.yz);
  let mouseDown = u.zoom_config.w;
  let mouseUV = (mouse - res * 0.5) / min(res.x, res.y);

  let smokeDensity = mix(0.25, 1.1, u.zoom_params.x);
  let bloomStrength = mix(0.15, 0.75, u.zoom_params.y);
  let energy = mix(0.45, 1.5, u.zoom_params.z);
  let trailDecay = mix(0.9, 0.97, u.zoom_params.w);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  var col = vec3<f32>(0.01, 0.008, 0.024);
  let star = step(0.993, hash2(floor(uv * 140.0))) * (0.5 + 0.5 * sin(time * 4.5 + hash2(uv * 55.0) * 20.0));
  col += vec3<f32>(0.8, 0.85, 1.0) * star * 0.6;

  // ── Mortar shells with smoke and bloom ──
  let numShells = 6;
  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 29.0 + 3.0);
    let seed2 = hash1(si * 47.0 + 9.0);

    let cycle = 2.3 * (0.8 + seed * 0.5) / (1.0 + bass * 0.2);
    let birth = floor((time + seed * 2.1) / cycle) * cycle - seed * 2.1;
    let age = time - birth;
    if (age < 0.0 || age > 7.5) { continue; }

    let baseX = (seed - 0.5) * 1.65;
    let baseY = -0.78;
    let burstDelay = 1.2 + seed * 0.6;
    let burstAge = max(0.0, age - burstDelay);
    let shellEnergy = energy * (0.75 + bass * 0.7);
    let hue = fract(seed * 1.5 + time * 0.012);

    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(baseY, baseY + 1.28, t * t);
      col += vec3<f32>(1.0, 0.9, 0.6) * softGlow(uv, vec2<f32>(baseX, y), 0.009, shellEnergy * 2.1);
    }

    if (burstAge > 0.0 && burstAge < 5.8) {
      let center = vec2<f32>(baseX, baseY + 1.28);
      let fade = smoothstep(5.2, 0.3, burstAge);

      // Core flash + smoke puff at center
      col += vec3<f32>(1.0, 0.96, 0.85) * exp(-burstAge * 9.0) * shellEnergy * 2.2 * softGlow(uv, center, 0.07, 1.0);
      let smoke = smokePuff(uv, center, burstAge, smokeDensity * (0.6 + bass * 0.4), time);
      col += vec3<f32>(0.12, 0.1, 0.14) * smoke * fade * shellEnergy;

      // Primary sparks
      let nSparks = i32(28.0 + energy * 42.0 + mids * 12.0);
      for (var j: i32 = 0; j < nSparks; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 71.0 + jf * 4.1);
        let js2 = hash1(si * 17.0 + jf * 6.3);
        let ang = (jf / f32(nSparks)) * TAU + (js - 0.5) * 0.7;
        let spd = (0.5 + js2 * 0.6) * shellEnergy;
        let vel = vec2<f32>(cos(ang), sin(ang)) * spd;
        let sp = sparkPos(center, vel, burstAge, 1.0, 0.2);
        let sz = 0.006 + js * 0.004;
        let g = softGlow(uv, sp, sz, fade * shellEnergy * 1.5);
        col += shellColor(hue + js * 0.25, smoothstep(0.5, 0.0, burstAge * 0.2)) * g;

        // Trail smoke behind bright sparks
        if (js2 > 0.65) {
          let trailSmoke = smokePuff(uv, sp, burstAge + js, smokeDensity * 0.6, time);
          col += vec3<f32>(0.08, 0.07, 0.1) * trailSmoke * fade * shellEnergy * 0.7;
        }
      }

      // Secondary bloom ring (mids-driven)
      let secondaries = i32(1.0 + mids * 3.5);
      for (var sec: i32 = 0; sec < secondaries; sec = sec + 1) {
        let sf = f32(sec);
        let secDelay = 0.25 + sf * 0.18;
        let secAge = max(0.0, burstAge - secDelay);
        if (secAge <= 0.0 || secAge > 3.5) { continue; }
        let secCenter = center + vec2<f32>(cos(sf * 2.0), sin(sf * 1.7)) * 0.08 * shellEnergy;
        let secN = i32(20.0 + energy * 24.0);
        for (var k: i32 = 0; k < secN; k = k + 1) {
          let kf = f32(k);
          let ks = hash1(si * 37.0 + sf * 11.0 + kf * 3.0);
          let ang = (kf / f32(secN)) * TAU + ks;
          let vel = vec2<f32>(cos(ang), sin(ang)) * (0.35 + ks * 0.35) * shellEnergy;
          let sp = sparkPos(secCenter, vel, secAge, 0.9, 0.28);
          let g = softGlow(uv, sp, 0.005, smoothstep(3.2, 0.2, secAge) * shellEnergy);
          col += shellColor(hue + ks * 0.3 + sf * 0.1, 0.3) * g;
        }
      }

      // Treble micro-sparkle
      let microN = i32(6.0 + treble * 16.0);
      for (var m: i32 = 0; m < microN; m = m + 1) {
        let mf = f32(m);
        let ms = hash1(si * 53.0 + mf * 7.0);
        let mAng = ms * TAU;
        let mVel = vec2<f32>(cos(mAng), sin(mAng)) * (0.3 + ms * 0.4);
        let mPos = sparkPos(center, mVel, burstAge * 0.7, 0.7, 0.3);
        col += vec3<f32>(0.9, 0.95, 1.0) * softGlow(uv, mPos, 0.003, fade * treble * 0.85);
      }
    }
  }

  // ── Mouse smoky peony ──
  if (mouseDown > 0.5) {
    let mAge = fract(time * 0.8) * 4.0;
    if (mAge > 0.8 && mAge < 5.0) {
      let mbAge = mAge - 0.8;
      let mCenter = mouseUV + vec2<f32>(0.0, 0.1);
      let mEnergy = energy * (1.4 + bass);
      let mFade = smoothstep(4.5, 0.2, mbAge);

      col += vec3<f32>(1.0, 0.96, 0.85) * exp(-mbAge * 10.0) * mEnergy * 2.5 * softGlow(uv, mCenter, 0.08, 1.0);
      col += vec3<f32>(0.1, 0.09, 0.12) * smokePuff(uv, mCenter, mbAge, smokeDensity, time) * mFade * mEnergy;

      let mSparks = i32(40.0 + energy * 50.0);
      let mHue = fract(time * 0.02 + u.zoom_params.w * 0.5);
      for (var k: i32 = 0; k < mSparks; k = k + 1) {
        let ks = hash1(f32(k) * 2.7 + 2.0);
        let ang = (f32(k) / f32(mSparks)) * TAU + (ks - 0.5) * 0.8;
        let vel = vec2<f32>(cos(ang), sin(ang)) * (0.6 + ks * 0.7) * mEnergy;
        let sp = sparkPos(mCenter, vel, mbAge, 1.0, 0.18);
        let g = softGlow(uv, sp, 0.0065, mFade * mEnergy);
        col += shellColor(fract(ks * 1.4 + mHue), 0.5) * g;
      }
    }
  }

  // ── Feedback light bloom from dataTextureC ──
  let bloom = (
    textureSampleLevel(dataTextureC, u_sampler, clamp(uv01 + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb +
    textureSampleLevel(dataTextureC, u_sampler, clamp(uv01 - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb +
    textureSampleLevel(dataTextureC, u_sampler, clamp(uv01 + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb +
    textureSampleLevel(dataTextureC, u_sampler, clamp(uv01 - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb +
    textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).rgb
  ) * 0.2;
  col += bloom * bloomStrength * (0.6 + bass * 0.4);

  // ── Temporal persistence ──
  let haze = fbm(uv * 2.0 + vec2<f32>(time * 0.01, -time * 0.012), 2) * 0.018;
  col = mix(prev * trailDecay + haze, col, 0.28);

  let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
  col *= clamp(vig, 0.15, 1.0) * (0.7 + depth * 0.55);

  col = acesToneMap(col * 1.08);
  let alpha = clamp(length(col) * 1.1 + 0.13, 0.14, 0.96);

  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.55 + prev * 0.38, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
