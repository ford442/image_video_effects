// ═══════════════════════════════════════════════════════════════════
//  Audio Symphony Fireworks
//  Category: generative
//  Features: envelope-driven launches, bass primary shells, mids secondary
//            bursts, treble micro-sparks, mouse command shell, temporal
//            trails, aces-tone-map, semantic alpha, depth-aware
//  Complexity: Medium-High
//  Created: 2026-07-05
// ═══════════════════════════════════════════════════════════════════
//  The display is conducted by the music. A smoothed bass envelope triggers
//  bigger/faster launches on transients; mids layer in secondary shells;
//  treble crackles thousands of micro-sparks. The result is a fireworks
//  show that feels tightly synced to the audio spectrum.
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
  let gold = vec3<f32>(1.0, 0.8, 0.25);
  let rose = vec3<f32>(1.0, 0.35, 0.45);
  let blue = vec3<f32>(0.25, 0.65, 1.0);
  let lime = vec3<f32>(0.35, 1.0, 0.5);
  var col = mix(gold, rose, smoothstep(0.0, 0.33, hue));
  col = mix(col, blue, smoothstep(0.33, 0.66, hue));
  col = mix(col, lime, smoothstep(0.66, 1.0, hue));
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

  let launchDensity = mix(0.4, 1.3, u.zoom_params.x);
  let bassDrive = mix(0.4, 1.6, u.zoom_params.y);
  let midsLayering = mix(0.0, 1.0, u.zoom_params.z);
  let trebleSparkle = mix(0.2, 1.0, u.zoom_params.w);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Smoothed bass envelope for transient launches
  var prevBass = extraBuffer[0];
  let envK = select(0.04, 0.18, bass > prevBass);
  let smoothBass = mix(prevBass, bass, envK);
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[0] = smoothBass;
  }
  let bassPulse = max(0.0, bass - smoothBass);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  var col = vec3<f32>(0.01, 0.008, 0.026);
  let star = step(0.991, hash2(floor(uv * 140.0))) * (0.5 + 0.5 * sin(time * 5.0 + hash2(uv * 60.0) * 20.0));
  col += vec3<f32>(0.8, 0.85, 1.0) * star * 0.65;

  // ── Spectrum-driven shells ──
  let numShells = 6;
  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 29.0 + 3.0);
    let seed2 = hash1(si * 47.0 + 9.0);

    let baseCycle = 2.4 / (launchDensity + bassPulse * 1.5);
    let cycle = baseCycle * (0.8 + seed * 0.4);
    let birth = floor((time + seed * 2.0) / cycle) * cycle - seed * 2.0;
    let age = time - birth;
    if (age < 0.0 || age > 7.5) { continue; }

    let baseX = (seed - 0.5) * 1.7;
    let baseY = -0.78;
    let burstDelay = 1.1 + seed * 0.6 - bassPulse * 0.2;
    let burstAge = max(0.0, age - burstDelay);
    let shellEnergy = bassDrive * (0.6 + bass * 0.9 + bassPulse) * (0.8 + seed2 * 0.3);
    let hue = fract(seed * 1.7 + time * 0.02 + si * 0.1);

    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(baseY, baseY + 1.28, t * t);
      col += vec3<f32>(1.0, 0.9, 0.6) * softGlow(uv, vec2<f32>(baseX, y), 0.009, shellEnergy * 2.2);
    }

    if (burstAge > 0.0 && burstAge < 5.5) {
      let center = vec2<f32>(baseX, baseY + 1.28);
      let fade = smoothstep(5.0, 0.3, burstAge);

      // Bass-driven core flash
      col += vec3<f32>(1.0, 0.95, 0.85) * exp(-burstAge * 10.0) * shellEnergy * 2.2 * softGlow(uv, center, 0.07, 1.0);

      // Primary sparks — bass controlled
      let nSparks = i32(30.0 + shellEnergy * 50.0);
      for (var j: i32 = 0; j < nSparks; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 71.0 + jf * 4.1);
        let js2 = hash1(si * 17.0 + jf * 6.3);
        let ang = (jf / f32(nSparks)) * TAU + (js - 0.5) * 0.7;
        let spd = (0.48 + js2 * 0.6) * shellEnergy;
        let vel = vec2<f32>(cos(ang), sin(ang)) * spd;
        let sp = sparkPos(center, vel, burstAge, 1.0, 0.2);
        let sz = 0.006 + js * 0.004;
        let g = softGlow(uv, sp, sz, fade * shellEnergy * 1.5);
        col += shellColor(hue + js * 0.25, smoothstep(0.5, 0.0, burstAge * 0.2)) * g;
      }

      // Mids-driven secondary shells
      let secondaries = i32(1.0 + mids * midsLayering * 4.0);
      for (var sec: i32 = 0; sec < secondaries; sec = sec + 1) {
        let sf = f32(sec);
        let secDelay = 0.2 + sf * 0.15;
        let secAge = max(0.0, burstAge - secDelay);
        if (secAge <= 0.0 || secAge > 3.5) { continue; }
        let secCenter = center + vec2<f32>(cos(sf * 2.4), sin(sf * 1.9)) * 0.08 * shellEnergy;
        let secN = i32(20.0 + shellEnergy * 25.0);
        for (var k: i32 = 0; k < secN; k = k + 1) {
          let kf = f32(k);
          let ks = hash1(si * 37.0 + sf * 11.0 + kf * 3.0);
          let ang = (kf / f32(secN)) * TAU + ks;
          let vel = vec2<f32>(cos(ang), sin(ang)) * (0.35 + ks * 0.35) * shellEnergy;
          let sp = sparkPos(secCenter, vel, secAge, 0.9, 0.28);
          let g = softGlow(uv, sp, 0.005, smoothstep(3.2, 0.2, secAge) * shellEnergy);
          col += shellColor(hue + ks * 0.3 + sf * 0.15, 0.3) * g;
        }
      }

      // Treble micro-sparkle cloud
      let microN = i32(6.0 + treble * trebleSparkle * 24.0);
      for (var m: i32 = 0; m < microN; m = m + 1) {
        let mf = f32(m);
        let ms = hash1(si * 53.0 + mf * 7.0);
        let mAng = ms * TAU + time * 3.0;
        let mVel = vec2<f32>(cos(mAng), sin(mAng)) * (0.25 + ms * 0.45);
        let mPos = sparkPos(center, mVel, burstAge * 0.8, 0.7, 0.35);
        col += vec3<f32>(0.9, 0.96, 1.0) * softGlow(uv, mPos, 0.003, fade * treble * trebleSparkle * 1.1);
      }
    }
  }

  // ── Mouse command shell ──
  if (mouseDown > 0.5) {
    let mAge = fract(time * 0.9) * 4.0;
    if (mAge > 0.8 && mAge < 5.0) {
      let mbAge = mAge - 0.8;
      let mCenter = mouseUV + vec2<f32>(0.0, 0.1);
      let mEnergy = bassDrive * (1.4 + bass);
      let mFade = smoothstep(4.5, 0.2, mbAge);

      col += vec3<f32>(1.0, 0.95, 0.85) * exp(-mbAge * 10.0) * mEnergy * 2.5 * softGlow(uv, mCenter, 0.08, 1.0);

      let mSparks = i32(45.0 + bassDrive * 55.0);
      let mHue = fract(time * 0.02 + treble * 0.1);
      for (var k: i32 = 0; k < mSparks; k = k + 1) {
        let ks = hash1(f32(k) * 2.7 + 2.0);
        let ang = (f32(k) / f32(mSparks)) * TAU + (ks - 0.5) * 0.8;
        let vel = vec2<f32>(cos(ang), sin(ang)) * (0.6 + ks * 0.7) * mEnergy;
        let sp = sparkPos(mCenter, vel, mbAge, 1.0, 0.18);
        let g = softGlow(uv, sp, 0.0065, mFade * mEnergy);
        col += shellColor(fract(ks * 1.4 + mHue), 0.5) * g;
      }

      // Mouse treble halo
      let microN = i32(8.0 + treble * 20.0);
      for (var m: i32 = 0; m < microN; m = m + 1) {
        let ms = hash1(f32(m) * 4.0 + 6.0);
        let mAng = ms * TAU;
        let mVel = vec2<f32>(cos(mAng), sin(mAng)) * (0.2 + ms * 0.4);
        let mPos = sparkPos(mCenter, mVel, mbAge * 0.7, 0.6, 0.3);
        col += vec3<f32>(0.9, 0.96, 1.0) * softGlow(uv, mPos, 0.003, mFade * treble * 1.2);
      }
    }
  }

  // ── Temporal trails ──
  let haze = fbm(uv * 2.0 + vec2<f32>(time * 0.01, -time * 0.012), 2) * 0.018;
  let decay = 0.93 - bassPulse * 0.02;
  col = mix(prev * decay + haze, col, 0.28);

  let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
  col *= clamp(vig, 0.15, 1.0) * (0.7 + depth * 0.55);

  col = acesToneMap(col * 1.08);
  let alpha = clamp(length(col) * 1.1 + 0.13, 0.14, 0.96);

  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.55 + prev * 0.38, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
