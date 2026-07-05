// ═══════════════════════════════════════════════════════════════════
//  Pixel Detonation
//  Category: generative (image-reactive)
//  Features: pixel-to-spark lift, edge-ignited launches, depth-aware
//            bursts, photo dissolution, audio-reactive, mouse barrage,
//            temporal trails, aces-tone-map, semantic alpha
//  Complexity: Medium-High
//  Created: 2026-07-05
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

fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv - c);
  return (exp(-d * d / (r * r * 0.5)) + 0.28 * exp(-d / (r * 3.0))) * i;
}

fn sampleImg(uv: vec2<f32>) -> vec3<f32> {
  let p = clamp(uv * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  return textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
  let p = clamp(uv * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, p, 0.0).r;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v * age - vec2<f32>(0.0, g) * age * age * 0.5;
}

// Edge detection via finite differences on image luma
fn edgeStrength(uv: vec2<f32>, res: vec2<f32>) -> f32 {
  let eps = 1.5 / min(res.x, res.y);
  let l0 = dot(sampleImg(uv), vec3<f32>(0.299, 0.587, 0.114));
  let lx = dot(sampleImg(uv + vec2<f32>(eps, 0.0)), vec3<f32>(0.299, 0.587, 0.114));
  let ly = dot(sampleImg(uv + vec2<f32>(0.0, eps)), vec3<f32>(0.299, 0.587, 0.114));
  return length(vec2<f32>(lx - l0, ly - l0)) * 4.0;
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

  let power = mix(0.35, 1.8, u.zoom_params.x);
  let ignition = mix(0.15, 0.85, u.zoom_params.y);
  let pixelLift = mix(0.2, 1.0, u.zoom_params.z);
  let trailFade = mix(0.88, 0.96, u.zoom_params.w);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  // Base image — progressively dissolving
  let imgCol = sampleImg(uv);
  let lum = dot(imgCol, vec3<f32>(0.299, 0.587, 0.114));
  let edge = edgeStrength(uv, res);

  // Dissolve mask: bright + edge areas fade as detonations happen
  let dissolvePhase = fract(time * 0.08) * 0.5 + bass * 0.15;
  let dissolve = smoothstep(ignition * 0.5, ignition, lum + edge * 0.4) * pixelLift;
  var col = imgCol * (0.5 - dissolve * 0.35 * dissolvePhase);

  // Dark sky fill in dissolved areas
  col = mix(vec3<f32>(0.015, 0.012, 0.03), col, 1.0 - dissolve * 0.3);

  // Detonation cores — bright pixels + edges launch fireworks
  let numCores = 8;
  for (var s = 0; s < numCores; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 37.0 + 2.0);
    let seed2 = hash1(si * 61.0 + 5.0);

    // Probe position biased to image features
    let probeUV = vec2<f32>((seed - 0.5) * 1.6, (seed2 - 0.5) * 1.2);
    let probeCol = sampleImg(probeUV);
    let probeLum = dot(probeCol, vec3<f32>(0.299, 0.587, 0.114));
    let probeEdge = edgeStrength(probeUV, res);
    let probeDepth = sampleDepth(probeUV);

    let igniteScore = smoothstep(ignition * 0.4, ignition, probeLum) + probeEdge * 0.5;
    if (igniteScore < 0.25) { continue; }

    let cycle = 2.4 / (0.6 + ignition * 0.5);
    let birth = floor((time * (0.65 + mids * 0.2) + seed * 1.8) / cycle) * cycle - seed * 1.8;
    let age = time - birth;
    if (age < 0.0 || age > 6.0) { continue; }

    // Depth: foreground launches higher
    let depthBoost = 0.7 + probeDepth * 0.8;
    let basePos = probeUV + vec2<f32>(0.0, -0.08 * depthBoost);
    let burstDelay = 0.9 + seed * 0.5;
    let bAge = max(0.0, age - burstDelay);
    let shellPow = power * igniteScore * depthBoost * (0.6 + bass * 0.7);

    // Ascent from pixel origin
    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(basePos.y, basePos.y + 0.9 * depthBoost, t * t);
      let pos = vec2<f32>(basePos.x, y);
      col += probeCol * softGlow(uv, pos, 0.01, shellPow * 2.0);
      col += vec3<f32>(1.0, 0.9, 0.6) * softGlow(uv, pos, 0.006, shellPow);
    }

    // Pixel burst — sparks carry source colors, recolor over time
    if (bAge > 0.0 && bAge < 4.5) {
      let bCenter = vec2<f32>(basePos.x, basePos.y + 0.85 * depthBoost);
      let fade = smoothstep(4.2, 0.3, bAge);

      // Core flash from source pixel color
      col += probeCol * exp(-bAge * 10.0) * shellPow * 2.0 * softGlow(uv, bCenter, 0.05, 1.0);

      let nSparks = i32(20.0 + power * 35.0 + mids * 12.0);
      for (var j = 0; j < nSparks; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 13.0 + jf * 3.1);
        let js2 = hash1(si * 29.0 + jf * 7.3);

        let ang = (jf / f32(nSparks)) * TAU + (js - 0.5) * 1.0;
        let spd = (0.35 + js2 * 0.55) * shellPow * pixelLift;
        let vel = vec2<f32>(cos(ang), sin(ang)) * spd;
        let sp = sparkPos(bCenter, vel, bAge, 0.9 + shellPow * 0.15);

        // Sample image at spark's origin pixel (pixel flight)
        let originUV = mix(probeUV, sp * 0.3 + probeUV * 0.7, pixelLift * 0.5);
        var sparkCol = sampleImg(originUV);

        // Recolor over time: hot white → source → cooled ember
        let hot = smoothstep(0.8, 0.0, bAge);
        let cool = smoothstep(0.5, 3.0, bAge);
        sparkCol = mix(sparkCol, vec3<f32>(1.0, 0.95, 0.8), hot * 0.8);
        sparkCol = mix(sparkCol, vec3<f32>(0.8, 0.35, 0.1), cool * 0.5);

        let g = softGlow(uv, sp, 0.006 + js * 0.004, fade * shellPow * 1.5);
        col += sparkCol * g * (0.85 + treble * 0.6);
      }

      // Edge-ignited micro sparks (treble crackle along contours)
      let microN = i32(5.0 + treble * 15.0);
      for (var m = 0; m < microN; m = m + 1) {
        let mf = f32(m);
        let ms = hash1(si * 51.0 + mf * 9.0);
        let edgeUV = probeUV + vec2<f32>(cos(ms * TAU), sin(ms * TAU)) * 0.05;
        let eCol = sampleImg(edgeUV);
        let eAng = ms * TAU + time;
        let eVel = vec2<f32>(cos(eAng), sin(eAng)) * (0.2 + ms * 0.25);
        let ePos = sparkPos(bCenter, eVel, bAge * 0.6, 0.6);
        col += eCol * softGlow(uv, ePos, 0.003, fade * treble * 0.7);
      }
    }
  }

  // Mouse pixel barrage
  if (mouseDown > 0.45) {
    let mCol = sampleImg(mUV);
    let mLum = dot(mCol, vec3<f32>(0.3, 0.6, 0.1));
    let mPow = power * (1.2 + mLum + bass);
    let mAge = fract(time * 1.2) * 3.2;
    if (mAge > 0.7) {
      let mbAge = mAge - 0.7;
      let mC = mUV + vec2<f32>(0.0, 0.1);
      let mFade = smoothstep(3.0, 0.15, mbAge);
      let mn = i32(35.0 + power * 38.0);
      for (var k = 0; k < mn; k = k + 1) {
        let ks = hash1(f32(k) * 2.7 + 4.0);
        let ka = (f32(k) / f32(mn)) * TAU + ks * 1.5;
        let kv = vec2<f32>(cos(ka), sin(ka)) * (0.45 + ks * 0.7) * pixelLift;
        let kp = sparkPos(mC, kv, mbAge, 0.95);
        let kc = mix(sampleImg(mUV * 0.5 + kp * 0.5), mCol, 0.6);
        col += kc * softGlow(uv, kp, 0.0055, mFade * mPow);
      }
    }
  }

  // Temporal trails
  let smoke = vnoise(uv * 4.0 + vec2<f32>(time * 0.015)) * 0.02;
  col = mix(prev * trailFade + smoke, col, 0.3);

  // Treble pixel dust
  let dust = step(0.985 - treble * 0.035, hash2(uv * 220.0 + time * 14.0));
  col += vec3<f32>(0.65, 0.8, 1.0) * dust * treble * 0.7;

  let vig = 1.0 - dot(uv * 0.65, uv * 0.65);
  col *= clamp(vig * 1.1 + 0.15, 0.2, 1.1) * (0.65 + depth * 0.5);

  col = acesToneMap(col * 1.05);
  let alpha = clamp(length(col) * 1.1 + 0.15, 0.12, 0.96);

  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.5 + prev * 0.42, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
