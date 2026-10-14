// ═══════════════════════════════════════════════════════════════════
//  Pixel Detonation
//  Category: generative (image-reactive)
//  Features: pixel-to-spark lift, edge-ignited launches, depth-aware
//            bursts, photo dissolution, audio-reactive, mouse barrage,
//            temporal trails, aces-tone-map, semantic alpha
//  Complexity: Medium-High
//  Created: 2026-07-05
//  Upgraded: 2026-10-10
//  Ideas: timed burst shock rings; foreground-led depth-staggered launches
//  A packing: ACES display RGBA (rgb = tone-mapped trail history; a = visual coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

// Scene uv is y-up with the short axis spanning [-0.5, 0.5]; sample the
// full source frame with y=0 at the top, matching Image Pyro.
fn sampleImage(uv: vec2<f32>, res: vec2<f32>) -> vec3<f32> {
  let m = min(res.x, res.y);
  let q = vec2<f32>(uv.x * m / res.x + 0.5, 0.5 - uv.y * m / res.y);
  let p = clamp(q, vec2<f32>(0.0), vec2<f32>(1.0));
  return textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v * age - vec2<f32>(0.0, g) * age * age * 0.5;
}

// Edge detection via finite differences on image luma
fn edgeStrength(uv: vec2<f32>, res: vec2<f32>) -> f32 {
  let eps = 1.5 / min(res.x, res.y);
  let l0 = dot(sampleImage(uv, res), vec3<f32>(0.299, 0.587, 0.114));
  let lx = dot(sampleImage(uv + vec2<f32>(eps, 0.0), res), vec3<f32>(0.299, 0.587, 0.114));
  let ly = dot(sampleImage(uv + vec2<f32>(0.0, eps), res), vec3<f32>(0.299, 0.587, 0.114));
  return length(vec2<f32>(lx - l0, ly - l0)) * 4.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let minRes = min(res.x, res.y);
  let uv = vec2<f32>(f32(pixel.x) - res.x * 0.5, res.y * 0.5 - f32(pixel.y)) / minRes;
  let time = u.config.x;

  let mouse = vec2<f32>(u.zoom_config.yz);
  let mouseDown = u.zoom_config.w;
  let mUV = vec2<f32>((mouse.x - 0.5) * res.x, (0.5 - mouse.y) * res.y) / minRes;

  let power = mix(0.35, 1.8, u.zoom_params.x);
  let ignition = mix(0.15, 0.85, u.zoom_params.y);
  let pixelLift = mix(0.2, 1.0, u.zoom_params.z);
  let trailFade = mix(0.88, 0.96, u.zoom_params.w);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  // Base image — progressively dissolving
  let imgCol = sampleImage(uv, res);
  let lum = dot(imgCol, vec3<f32>(0.299, 0.587, 0.114));
  let edge = edgeStrength(uv, res);

  // Dissolve mask: bright + edge areas fade as detonations happen
  let dissolvePhase = fract(time * 0.08) * 0.5 + bass * 0.15;
  let dissolve = smoothstep(ignition * 0.5, ignition, lum + edge * 0.4) * pixelLift;
  var col = imgCol * (0.5 - dissolve * 0.35 * dissolvePhase);

  // Dark sky fill in dissolved areas
  col = mix(vec3<f32>(0.015, 0.012, 0.03), col, 1.0 - dissolve * 0.3);
  var glowAcc = 0.0;

  // Detonation cores — bright pixels + edges launch fireworks
  let numCores = 8;
  for (var s = 0; s < numCores; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 37.0 + 2.0);
    let seed2 = hash1(si * 61.0 + 5.0);

    // Probe position biased to image features
    let probeUV = vec2<f32>((seed - 0.5) * 1.6, (seed2 - 0.5) * 1.2);
    let probeCol = sampleImage(probeUV, res);
    let probeLum = dot(probeCol, vec3<f32>(0.299, 0.587, 0.114));
    let probeEdge = edgeStrength(probeUV, res);
    let probeTexUV = clamp(
      vec2<f32>(probeUV.x * minRes / res.x + 0.5, 0.5 - probeUV.y * minRes / res.y),
      vec2<f32>(0.0), vec2<f32>(1.0)
    );
    let probeDepth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, probeTexUV, 0.0).r, 0.0, 1.0);

    let igniteScore = smoothstep(ignition * 0.4, ignition, probeLum) + probeEdge * 0.5;
    if (igniteScore < 0.25) { continue; }

    let cycle = 2.4 / (0.6 + ignition * 0.5);
    let launchRate = 0.65 + mids * 0.2;
    // Idea 2 — foreground source depth leads the launch clock, so nearer
    // features ignite first while retaining the existing mortar cadence.
    let depthLead = probeDepth * (0.35 + pixelLift * 0.35);
    let period = cycle * 3.0;
    let launchClock = (time + depthLead) * launchRate + seed * period;
    let age = (launchClock - floor(launchClock / period) * period) / launchRate;
    if (age < 0.0 || age > 6.0) { continue; }

    // Idea 2 — the same foreground ordering also gives nearer shells a higher apogee.
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
      let ascentGlow = softGlow(uv, pos, 0.01, shellPow * 2.0);
      let ascentCore = softGlow(uv, pos, 0.006, shellPow);
      col += probeCol * ascentGlow;
      col += vec3<f32>(1.0, 0.9, 0.6) * ascentCore;
      glowAcc += ascentGlow + ascentCore;
    }

    // Pixel burst — sparks carry source colors, recolor over time
    if (bAge > 0.0 && bAge < 4.5) {
      let bCenter = vec2<f32>(basePos.x, basePos.y + 0.85 * depthBoost);
      let fade = smoothstep(4.2, 0.3, bAge);

      // Core flash from source pixel color
      let coreGlow = exp(-bAge * 10.0) * shellPow * 2.0 * softGlow(uv, bCenter, 0.05, 1.0);
      col += probeCol * coreGlow;
      glowAcc += coreGlow;

      // Idea 1 — timed pressure fronts expand from the existing burst centre.
      // A delayed echo makes the detonation read as concentric shock rings,
      // without replacing the source-coloured ballistic sparks.
      let centerDist = length(uv - bCenter);
      let ringRadius = bAge * (0.16 + shellPow * 0.025);
      let ringWidth = 0.007 + 0.004 * clamp(bAge, 0.0, 1.0);
      let ringDelta = (centerDist - ringRadius) / ringWidth;
      let primaryRing = exp(-ringDelta * ringDelta) * exp(-bAge * 1.35);
      let echoAge = max(bAge - 0.18, 0.0);
      let echoRadius = echoAge * (0.13 + shellPow * 0.018);
      let echoDelta = (centerDist - echoRadius) / (ringWidth * 0.8);
      let echoRing = select(0.0, exp(-echoDelta * echoDelta) * exp(-echoAge * 1.65), bAge > 0.18);
      let shockRing = (primaryRing + echoRing * 0.55) * shellPow;
      let ringCol = mix(probeCol, vec3<f32>(1.0, 0.88, 0.62), 0.45);
      col += ringCol * shockRing;
      glowAcc += shockRing;

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
        var sparkCol = sampleImage(originUV, res);

        // Recolor over time: hot white → source → cooled ember
        let hot = smoothstep(0.8, 0.0, bAge);
        let cool = smoothstep(0.5, 3.0, bAge);
        sparkCol = mix(sparkCol, vec3<f32>(1.0, 0.95, 0.8), hot * 0.8);
        sparkCol = mix(sparkCol, vec3<f32>(0.8, 0.35, 0.1), cool * 0.5);

        let g = softGlow(uv, sp, 0.006 + js * 0.004, fade * shellPow * 1.5);
        col += sparkCol * g * (0.85 + treble * 0.6);
        glowAcc += g;
      }

      // Edge-ignited micro sparks (treble crackle along contours)
      let microN = i32(5.0 + treble * 15.0);
      for (var m = 0; m < microN; m = m + 1) {
        let mf = f32(m);
        let ms = hash1(si * 51.0 + mf * 9.0);
        let edgeUV = probeUV + vec2<f32>(cos(ms * TAU), sin(ms * TAU)) * 0.05;
        let eCol = sampleImage(edgeUV, res);
        let eAng = ms * TAU + time;
        let eVel = vec2<f32>(cos(eAng), sin(eAng)) * (0.2 + ms * 0.25);
        let ePos = sparkPos(bCenter, eVel, bAge * 0.6, 0.6);
        let microGlow = softGlow(uv, ePos, 0.003, fade * treble * 0.7);
        col += eCol * microGlow;
        glowAcc += microGlow;
      }
    }
  }

  // Mouse pixel barrage
  if (mouseDown > 0.45) {
    let mCol = sampleImage(mUV, res);
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
        let kc = mix(sampleImage(mUV * 0.5 + kp * 0.5, res), mCol, 0.6);
        let mouseGlow = softGlow(uv, kp, 0.0055, mFade * mPow);
        col += kc * mouseGlow;
        glowAcc += mouseGlow;
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
  let fireworkCoverage = 1.0 - exp(-glowAcc * 0.65);
  let imageCoverage = clamp(lum * (0.8 - dissolvePhase * dissolve * 0.25) + 0.12, 0.0, 0.92);
  let alpha = clamp(max(imageCoverage, fireworkCoverage), 0.08, 0.98);

  // A is the exact ACES display history consumed from C on the next frame.
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  // Preserve source depth; luminous ballistic material pulls toward the viewer.
  let fireworkDepth = 0.1 + 0.88 * (1.0 - exp(-glowAcc * 1.25));
  let outDepth = max(clamp(depth, 0.0, 1.0), fireworkDepth * fireworkCoverage);
  textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
