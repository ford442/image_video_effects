// ═══════════════════════════════════════════════════════════════════
//  Image Pyro
//  Category: generative
//  Features: image-reactive fireworks, color sampling, gravity,
//            audio-reactive bursts, mouse-directed, trails, aces
//  Complexity: Medium
//  Created: 2026-07-05
//  By: Spark Engine
// ═══════════════════════════════════════════════════════════════════
//  The loaded image (or video frame) is the source material.
//  Bright areas "ignite" and launch fireworks whose sparks carry
//  the photo's own colors. Explosions feel like the picture itself
//  is celebrating and coming apart in colored light.
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
  return (exp(-d*d/(r*r*0.55)) + 0.32 * exp(-d/(r*3.2))) * i;
}

fn sampleImage(uv: vec2<f32>, res: vec2<f32>) -> vec3<f32> {
  let p = clamp(uv * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  return textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  let t = age;
  return o + v * t - vec2<f32>(0.0, g) * t * t * 0.5;
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
  let mUV = (mouse - res * 0.5) / min(res.x, res.y);

  let power = mix(0.35, 1.9, u.zoom_params.x);
  let ignition = mix(0.3, 1.4, u.zoom_params.y);
  let trail = mix(0.3, 0.95, u.zoom_params.z);
  let hueTwist = u.zoom_params.w * 0.6;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Base image (slightly darkened for night mood)
  let imgUV = uv;
  var base = sampleImage(imgUV, res) * 0.65;

  // Boost ignition in bright image areas
  let lum = dot(base, vec3<f32>(0.299, 0.587, 0.114));
  let igniteFactor = smoothstep(0.08, 0.65, lum) * ignition;

  var col = base * (0.55 + igniteFactor * 0.25);

  // Subtle starfield over darks
  let dark = 1.0 - saturate(lum * 1.8);
  let twinkle = step(0.993, hash2(uv * 180.0 + time * 1.5)) * dark * 0.6;
  col += vec3<f32>(0.7, 0.8, 1.0) * twinkle;

  // Image-driven launch zones (sample several "mortars" biased to bright parts)
  let numLaunches = 7;
  for (var s = 0; s < numLaunches; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 19.77 + 4.0);
    let seed2 = hash1(si * 31.4 + 2.0);

    // Prefer launching from brighter parts of image
    let probe = vec2<f32>(seed - 0.5, -0.65 + seed2 * 0.12);
    let probeCol = sampleImage(probe, res);
    let probeLum = dot(probeCol, vec3<f32>(0.299, 0.587, 0.114));
    let spawnProb = smoothstep(0.12, 0.75, probeLum) * 0.9 + 0.1;

    let cycle = 2.1 / (0.7 + ignition * 0.6);
    let birth = floor((time * (0.7 + ignition * 0.4) + seed * 1.6) / cycle) * cycle - seed * 1.6;
    let age = time - birth;
    if (age < 0.0 || age > 6.5) { continue; }

    let basePos = probe + vec2<f32>(0.0, -0.05);
    let burstDelay = 1.25 + seed * 0.6;
    let bAge = max(0.0, age - burstDelay);

    let shellPow = power * (0.6 + probeLum * 1.1 + bass * 0.7);

    // Ascent
    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(basePos.y, basePos.y + 1.15, t * t);
      let pos = vec2<f32>(basePos.x, y);
      let streak = softGlow(uv, pos, 0.012, shellPow * 1.9);
      let ascCol = mix(vec3<f32>(0.9, 0.85, 0.6), probeCol * 0.8 + 0.2, 0.5);
      col += ascCol * streak;
    }

    // Main burst — sample image colors for the sparks
    if (bAge > 0.0 && bAge < 4.8) {
      let bCenter = vec2<f32>(basePos.x * 0.9, basePos.y + 1.12);
      let nSparks = i32(32.0 + power * 42.0 + mids * 18.0);
      for (var j = 0; j < nSparks; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 7.0 + jf * 2.3);
        let js2 = hash1(si * 11.0 + jf * 5.9);
        let ang = (jf / f32(nSparks)) * TAU + (js - 0.5) * 1.2;
        let spd = (0.48 + js2 * 0.7) * (0.85 + shellPow * 0.4);
        let vel = vec2<f32>(cos(ang), sin(ang)) * spd;

        let sp = sparkPos(bCenter, vel, bAge, 1.05 + shellPow * 0.1);

        let fade = smoothstep(4.3, 0.5, bAge);
        let g = softGlow(uv, sp, 0.007 + js * 0.005, fade * shellPow * 1.6);

        // Sample image near burst center for color (with twist)
        let sampleUV = bCenter * 0.6 + sp * 0.4;
        var sparkCol = sampleImage(sampleUV, res);
        sparkCol = mix(sparkCol, vec3<f32>(0.95, 0.7, 0.4), js * 0.3); // gold bias
        sparkCol = sparkCol * (0.7 + 0.6 * js2);

        // Hue twist param
        let lumC = length(sparkCol);
        sparkCol = mix(sparkCol, vec3<f32>(lumC), abs(hueTwist) * 0.5);
        if (hueTwist > 0.0) { sparkCol = sparkCol.bgr; }

        col += sparkCol * g * (0.9 + treble * 0.7);
      }

      // Quick core flash using image brightness
      let core = exp(-bAge * 9.0) * shellPow * 1.8;
      col += probeCol * core * 1.3;
    }

    // Lingering embers tinted by image
    if (bAge > 0.6 && bAge < 5.5) {
      let emN = i32(9.0 + power * 7.0);
      for (var e = 0; e < emN; e = e + 1) {
        let es = hash1(si * 27.0 + f32(e) * 4.1);
        let eang = es * TAU * 0.6;
        let evel = vec2<f32>(cos(eang), -0.3 + sin(eang) * 0.3) * (0.22 + es * 0.2);
        let epos = sparkPos(basePos + vec2<f32>(0.0, 1.1), evel, bAge * 0.85, 0.65);
        let ef = softGlow(uv, epos, 0.005, smoothstep(4.8, 1.0, bAge - 0.5) * shellPow * 0.65);
        let ecol = sampleImage(epos * 0.7 + basePos * 0.3, res) * 0.85;
        col += ecol * ef;
      }
    }
  }

  // Mouse directed barrage (samples image at mouse too)
  if (mouseDown > 0.45) {
    let mLum = dot(sampleImage(mUV, res), vec3<f32>(0.3, 0.6, 0.1));
    let mPow = power * (1.3 + mLum * 1.2 + bass);
    let mAge = fract(time * 1.3) * 3.6;
    if (mAge > 0.9) {
      let mbAge = mAge - 0.9;
      let mC = mUV + vec2<f32>(0.0, 0.15);
      let mn = i32(42.0 + power * 40.0);
      for (var k = 0; k < mn; k = k + 1) {
        let ks = hash1(f32(k) * 1.3 + 9.0);
        let ka = (f32(k) / f32(mn)) * TAU + ks * 1.8;
        let kv = vec2<f32>(cos(ka), sin(ka)) * (0.6 + ks * 0.9);
        let kp = sparkPos(mC, kv, mbAge, 1.0);
        let kg = softGlow(uv, kp, 0.0065, smoothstep(3.0, 0.2, mbAge) * mPow);
        let kc = sampleImage(kp * 0.4 + mUV * 0.6, res);
        col += kc * kg * (1.0 + treble * 0.4);
      }
    }
  }

  // Temporal trails / afterglow from previous
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let decay = mix(0.94, 0.88, trail);
  let smoke = fbm(uv * 3.0 + vec2<f32>(time * 0.01), 2) * 0.022 * (0.6 + bass * 0.4);
  col = mix(prev * decay + smoke, col, 0.32);

  // Extra treble sparkle on top of everything
  let extra = step(0.986 - treble * 0.04, hash2(uv * 240.0 + time * 17.0));
  col += vec3<f32>(0.6, 0.85, 1.0) * extra * treble * 0.9;

  // Gentle vignette
  let v = 1.0 - dot(uv * 0.68, uv * 0.68);
  col *= clamp(v * 1.15 + 0.15, 0.2, 1.15);

  col = acesToneMap(col * 1.03);

  let alpha = clamp(length(col) * 1.1 + 0.18, 0.12, 0.97);

  // Feedback state
  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.55 + prev * 0.4, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));

  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}
