// ═══════════════════════════════════════════════════════════════════
//  Chrysanthemum Burst
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium-High
//  Created: 2026-07-05
//  Upgraded: 2026-10-27
//  Ideas: circumferential petal burn wave; split-tip florets
//  Retained: pistil heart; spherical latitudes; petal barbs; color break
//  A packing: ACES display RGBA
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
  return (exp(-d * d / (r * r * 0.45)) + 0.3 * exp(-d / (r * 2.8))) * i;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, drag: f32) -> vec2<f32> {
  let t = age;
  let df = exp(-drag * t);
  return o + vec2<f32>(v.x * df, v.y * df - g * t * t * 0.5);
}

// Ring-layer color: inner hot white → mid crimson → outer blue/gold
fn chrysanthemumColor(ringT: f32, spread: f32, seed: f32, age: f32) -> vec3<f32> {
  let inner = vec3<f32>(1.0, 0.97, 0.92);
  let mid = vec3<f32>(1.0, 0.2, 0.15);
  let outer = vec3<f32>(0.25, 0.7, 1.0);
  let gold = vec3<f32>(1.0, 0.8, 0.25);
  let hue = fract(seed * 1.3 + spread * 0.8 + ringT * 0.4);

  var col = inner;
  if (ringT < 0.25) { col = mix(inner, mid, ringT / 0.25); }
  else if (ringT < 0.6) { col = mix(mid, mix(outer, gold, hue), (ringT - 0.25) / 0.35); }
  else { col = mix(mix(outer, gold, hue), outer * 0.7, (ringT - 0.6) / 0.4); }

  let hot = smoothstep(0.5, 0.0, age * 0.25);
  col = mix(col, inner, hot * 0.7);
  return col;
}

fn petalBurn(angle: f32, ringT: f32, age: f32) -> f32 {
  let wave = 0.5 + 0.5 * cos(angle * 3.0 - age * 5.0 + ringT * TAU);
  return 0.75 + 0.5 * wave * smoothstep(0.1, 0.5, age);
}

fn splitFloret(uv: vec2<f32>, tip: vec2<f32>, velocity: vec2<f32>, ringT: f32, age: f32) -> f32 {
  let side = vec2<f32>(-velocity.y, velocity.x) / max(length(velocity), 0.0001);
  let splitAge = max(0.0, age - 0.55 - ringT * 0.25);
  let offset = side * min(splitAge * 0.035, 0.045);
  let fall = vec2<f32>(0.0, -min(splitAge * splitAge * 0.04, 0.08));
  let light = smoothstep(0.0, 0.15, splitAge) * exp(-splitAge * 1.8) * smoothstep(0.25, 0.65, ringT);
  return softGlow(uv, tip + offset + fall, 0.003, light)
    + softGlow(uv, tip - offset + fall, 0.003, light);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;

  let mouseNorm = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseUV = (mouseNorm - 0.5) * vec2<f32>(res.x / min(res.x, res.y), 1.0);

  let burstSize = mix(0.5, 1.5, u.zoom_params.x);
  let ringLayers = mix(1.0, 4.0, u.zoom_params.y);
  let density = mix(0.4, 1.3, u.zoom_params.z);
  let colorSpread = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  var col = vec3<f32>(0.01, 0.008, 0.025);
  let star = step(0.991, hash2(floor(uv * 130.0))) * 0.6;
  col += vec3<f32>(0.75, 0.8, 1.0) * star;

  let numShells = 8;
  let basePeriod = 1.35;

  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 31.0 + 7.0);
    let seed2 = hash1(si * 53.0 + 11.0);

    let cycle = 6.5 + basePeriod * (0.72 + seed * 0.45);
    let age = fract(time * 1.05 / cycle + seed) * cycle;
    if (age < 0.0 || age > 6.5) { continue; }

    let baseX = (seed - 0.5) * 1.7;
    let baseY = -0.8;
    let burstDelay = 1.1 + seed * 0.5;
    let burstAge = max(0.0, age - burstDelay);
    let energy = burstSize * (0.75 + bass * 0.7);

    // Ascent
    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(baseY, baseY + 1.3, t * t);
      col += vec3<f32>(1.0, 0.9, 0.65) * softGlow(uv, vec2<f32>(baseX, y), 0.009, energy * 2.0);
    }

    if (burstAge > 0.0 && burstAge < 5.5) {
      let center = vec2<f32>(baseX, baseY + 1.28);
      let fade = smoothstep(5.0, 0.3, burstAge);

      // Core flash
      col += vec3<f32>(1.0, 0.98, 0.9) * exp(-burstAge * 14.0) * energy * 2.5 * softGlow(uv, center, 0.06, 1.0);

      // Concentric ring layers (timed stagger)
      let layers = i32(ringLayers + mids * 1.5);
      for (var layer = 0; layer < layers; layer = layer + 1) {
        let lf = f32(layer);
        let layerDelay = lf * 0.08;
        let layerAge = max(0.0, burstAge - layerDelay);
        if (layerAge <= 0.0 || layerAge > 4.5) { continue; }

        let ringT = lf / max(f32(layers) - 0.5, 1.0);
        // Pistil heart: innermost ring slower and denser than outer rays.
        let pistil = 1.0 - ringT;
        let ringSpeed = (0.18 + ringT * 0.82) * energy;
        let sparksPerRing = i32(24.0 + density * 36.0 + lf * 8.0 + pistil * 20.0);
        // Sphere foreshorten: this ring is a latitude on a ball, not a flat disk.
        let lat = (ringT - 0.5) * 1.85;
        let ringR3 = cos(lat);
        let yLift = sin(lat) * 0.16 * energy;

        for (var j: i32 = 0; j < sparksPerRing; j = j + 1) {
          let jf = f32(j);
          let jSeed = hash1(si * 77.0 + lf * 13.0 + jf * 2.7);
          let jSeed2 = hash1(si * 29.0 + lf * 7.0 + jf * 5.1);

          let angle = (jf / f32(sparksPerRing)) * TAU + (jSeed - 0.5) * 0.4 + lf * 0.15;
          let speed = ringSpeed * (1.05 + jSeed2 * 0.35);
          let vel = vec2<f32>(cos(angle), sin(angle)) * speed * ringR3;
          let grav = 0.85 + ringT * 0.35;
          let sp = sparkPos(center + vec2<f32>(0.0, yLift), vel, layerAge, grav, 0.18 + ringT * 0.08);

          let lifeFade = fade * smoothstep(4.0, 0.2, layerAge) * (0.6 + jSeed * 0.4);
          // Radial speed-line stretch along velocity direction.
          let vDir = normalize(vel + vec2<f32>(0.001));
          let streak = exp(-abs(dot(uv - sp, vec2<f32>(-vDir.y, vDir.x))) * 140.0) *
                       exp(-abs(dot(uv - sp, vDir) + layerAge * 0.35) * 18.0) * lifeFade * 0.35;

          let size = (0.005 + jSeed2 * 0.004) * (1.0 + bass * 0.15);
          let glow = softGlow(uv, sp, size, lifeFade * energy * 1.6);

          var sparkCol = chrysanthemumColor(ringT, colorSpread, jSeed, layerAge);
          // Color break — outer sparks change hue partway through the burn.
          let breakAge = 1.05 + jSeed * 0.45;
          let changed = smoothstep(breakAge, breakAge + 0.18, layerAge) * smoothstep(0.35, 0.7, ringT);
          sparkCol = mix(sparkCol, chrysanthemumColor(fract(ringT + 0.42), colorSpread, jSeed, layerAge), changed);
          sparkCol *= petalBurn(angle, ringT, layerAge);
          col += sparkCol * glow * (0.85 + treble * 0.5);
          col += sparkCol * streak * energy;
          col += mix(sparkCol, vec3<f32>(1.0, 0.55, 0.18), 0.4)
            * splitFloret(uv, sp, vel, ringT, layerAge) * lifeFade * energy * 0.75;
          // Petal barbs — short side ticks on the outer rays.
          let barbOff = abs(dot(uv - sp, vec2<f32>(-vDir.y, vDir.x)));
          let barb = exp(-abs(barbOff - 0.012) * 160.0) * exp(-abs(dot(uv - sp, vDir)) * 36.0) * smoothstep(0.4, 0.75, ringT);
          col += sparkCol * barb * lifeFade * 0.5;
        }
      }

      // Secondary crackle on outer ring (treble)
      let crackles = i32(8.0 + treble * 20.0);
      let crackleFade = fade * smoothstep(4.5, 0.5, burstAge);
      for (var c = 0; c < crackles; c = c + 1) {
        let cf = f32(c);
        let cSeed = hash1(si * 44.0 + cf * 11.0);
        let cAng = cSeed * TAU;
        let cVel = vec2<f32>(cos(cAng), sin(cAng)) * (0.5 + cSeed * 0.5) * energy;
        let cPos = sparkPos(center, cVel, burstAge * 0.7, 0.7, 0.3);
        col += vec3<f32>(0.9, 0.95, 1.0) * softGlow(uv, cPos, 0.0035, crackleFade * treble * 0.9);
      }
    }
  }

  // Mouse peony — massive dense burst
  if (mouseDown > 0.5) {
    let mAge = fract(time * 1.1) * 3.5;
    if (mAge > 0.8 && mAge < 5.0) {
      let mbAge = mAge - 0.8;
      let mCenter = mouseUV + vec2<f32>(0.0, 0.1);
      let mEnergy = burstSize * (1.5 + bass);
      let mFade = smoothstep(4.5, 0.2, mbAge);

      col += vec3<f32>(1.0) * exp(-mbAge * 12.0) * mEnergy * 3.0 * softGlow(uv, mCenter, 0.08, 1.0);

      let mLayers = i32(ringLayers + 2.0);
      for (var ml = 0; ml < mLayers; ml = ml + 1) {
        let mlf = f32(ml);
        let mRingT = mlf / f32(mLayers);
        let mPistil = 1.0 - mRingT;
        let mLat = (mRingT - 0.5) * 1.85;
        let mSparks = i32(30.0 + density * 40.0 + mPistil * 16.0);
        for (var mk = 0; mk < mSparks; mk = mk + 1) {
          let mkf = f32(mk);
          let mks = hash1(mkf * 2.1 + mlf * 5.0);
          let mang = (mkf / f32(mSparks)) * TAU + mks;
          let mspd = (0.18 + mRingT * 0.82) * mEnergy;
          let mvel = vec2<f32>(cos(mang), sin(mang)) * mspd * cos(mLat);
          let layerAge = max(0.0, mbAge - mlf * 0.05);
          let mpos = sparkPos(mCenter + vec2<f32>(0.0, sin(mLat) * 0.16 * mEnergy), mvel, layerAge, 0.9, 0.18);
          let mg = softGlow(uv, mpos, 0.006, mFade * mEnergy) * smoothstep(0.0, 0.04, layerAge);
          let petalColor = chrysanthemumColor(mRingT, colorSpread, mks, mbAge) * petalBurn(mang, mRingT, layerAge);
          col += petalColor * mg;
          col += mix(petalColor, vec3<f32>(1.0, 0.55, 0.18), 0.4)
            * splitFloret(uv, mpos, mvel, mRingT, layerAge) * mFade * mEnergy * 0.75;
        }
      }
    }
  }

  // HDR velocity trails via advected history.
  let histCoord = clamp(pixel - vec2<i32>(vec2<f32>(cos(time * 0.3), sin(time * 0.27)) * (2.0 + bass * 2.0)),
                        vec2<i32>(0), vec2<i32>(i32(res.x) - 1, i32(res.y) - 1));
  let prevHist = textureLoad(dataTextureC, histCoord, 0).rgb;
  col = clamp(col + prevHist * (0.86 + density * 0.04), vec3<f32>(0.0), vec3<f32>(5.5));

  let vig = 1.0 - dot(uv * 0.72, uv * 0.72);
  col *= clamp(vig, 0.15, 1.0) * (0.7 + depth * 0.55);

  col = acesToneMap(col * 1.1);
  let luminance = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alpha = 0.14 + 0.83 * (1.0 - exp(-luminance * 2.5));
  let genDepth = clamp(1.0 - length(col) * 0.22, 0.05, 0.98);

  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(genDepth, 0.0, 0.0, 0.0));
}
