// ═══════════════════════════════════════════════════════════════════
//  Crackle Palm
//  Category: generative
//  Features: multi-stage bursts, delayed crackle, palm fronds,
//            treble micro-pops, audio-reactive, mouse shell,
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
  return (exp(-d * d / (r * r * 0.48)) + 0.32 * exp(-d / (r * 3.0))) * i;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, drag: f32) -> vec2<f32> {
  let t = age;
  let df = exp(-drag * t);
  return o + vec2<f32>(v.x * df, v.y * df - g * t * t * 0.5);
}

fn shellColor(hue: f32, hot: f32) -> vec3<f32> {
  let gold = vec3<f32>(1.0, 0.82, 0.3);
  let red = vec3<f32>(1.0, 0.2, 0.12);
  let blue = vec3<f32>(0.3, 0.7, 1.0);
  let green = vec3<f32>(0.2, 0.95, 0.5);
  var col = mix(gold, red, smoothstep(0.0, 0.33, hue));
  col = mix(col, blue, smoothstep(0.33, 0.66, hue));
  col = mix(col, green, smoothstep(0.66, 1.0, hue));
  return mix(col, vec3<f32>(1.0, 0.97, 0.9), hot);
}

// Micro-crackle pops — treble-driven white sparks
fn addCrackle(
  col: ptr<function, vec3<f32>>,
  uv: vec2<f32>,
  center: vec2<f32>,
  localAge: f32,
  intensity: f32,
  treble: f32,
  seed: f32,
  count: i32
) {
  let popFade = smoothstep(2.5, 0.05, localAge);
  for (var c = 0; c < count; c = c + 1) {
    let cf = f32(c);
    let cs = hash1(seed * 47.0 + cf * 13.7);
    let cs2 = hash1(seed * 23.0 + cf * 9.1);
    // Crackle pops appear in bursts over time
    let popTime = cs * 1.8;
    let popAge = localAge - popTime;
    if (popAge < 0.0 || popAge > 0.35) { continue; }

    let ang = cs * TAU + cs2 * 2.0;
    let dist = (0.08 + cs2 * 0.25) * intensity;
    let popPos = center + vec2<f32>(cos(ang), sin(ang)) * dist;
    let flash = exp(-popAge * 18.0) * (0.5 + treble * 0.8);
    let micro = softGlow(uv, popPos, 0.003 + cs * 0.003, flash * popFade * intensity);
    *col += vec3<f32>(0.95, 0.97, 1.0) * micro * (1.2 + treble);
  }
}

// Palm frond arms — curved downward trails from sub-points
fn addPalmFrond(
  col: ptr<function, vec3<f32>>,
  uv: vec2<f32>,
  origin: vec2<f32>,
  armAngle: f32,
  localAge: f32,
  spread: f32,
  energy: f32,
  hue: f32
) {
  let frondLen = 8;
  let dir = vec2<f32>(cos(armAngle), sin(armAngle) * 0.3 - 0.7);
  let side = vec2<f32>(-dir.y, dir.x) * spread * 0.15;

  for (var f = 0; f < frondLen; f = f + 1) {
    let ff = f32(f) / f32(frondLen);
    let along = dir * ff * (0.35 + spread * 0.4);
    let droop = vec2<f32>(0.0, -ff * ff * (0.25 + spread * 0.35));
    let sway = side * sin(ff * PI + localAge * 2.0) * 0.08;
    let pos = origin + along + droop + sway;

    let fade = smoothstep(3.5, 0.2, localAge) * (1.0 - ff * 0.5);
    let g = softGlow(uv, pos, 0.005 + ff * 0.003, fade * energy);
    *col += shellColor(hue + ff * 0.15, 1.0 - ff) * g;
  }
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

  let energy = mix(0.45, 1.6, u.zoom_params.x);
  let stageDelay = mix(0.25, 1.2, u.zoom_params.y);
  let crackleAmt = mix(0.2, 1.0, u.zoom_params.z);
  let palmSpread = mix(0.2, 1.0, u.zoom_params.w);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  var col = vec3<f32>(0.01, 0.008, 0.022);
  col += vec3<f32>(0.75, 0.8, 1.0) * step(0.992, hash2(floor(uv * 125.0))) * 0.55;

  let numShells = 7;
  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 29.0 + 3.0);
    let seed2 = hash1(si * 47.0 + 9.0);

    let cycle = 2.2 * (0.85 + seed * 0.4);
    let birth = floor((time * (0.7 + bass * 0.15) + seed * 1.6) / cycle) * cycle - seed * 1.6;
    let age = time - birth;
    if (age < 0.0 || age > 7.5) { continue; }

    let baseX = (seed - 0.5) * 1.65;
    let baseY = -0.78;
    let burstDelay = 1.2 + seed * 0.6;
    let burstAge = max(0.0, age - burstDelay);
    let shellEnergy = energy * (0.75 + bass * 0.65);
    let hue = fract(seed * 1.4 + time * 0.01);

    // Ascent
    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(baseY, baseY + 1.25, t * t);
      col += vec3<f32>(1.0, 0.88, 0.55) * softGlow(uv, vec2<f32>(baseX, y), 0.009, shellEnergy * 2.2);
    }

    if (burstAge > 0.0 && burstAge < 6.5) {
      let center = vec2<f32>(baseX, baseY + 1.28);
      let fade = smoothstep(6.0, 0.3, burstAge);

      // ── STAGE 1: Primary burst ──
      let nPrimary = i32(30.0 + shellEnergy * 35.0);
      for (var j: i32 = 0; j < nPrimary; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 71.0 + jf * 4.1);
        let js2 = hash1(si * 17.0 + jf * 6.3);
        let ang = (jf / f32(nPrimary)) * TAU + (js - 0.5) * 0.6;
        let spd = (0.5 + js2 * 0.6) * shellEnergy;
        let vel = vec2<f32>(cos(ang), sin(ang)) * spd;
        let sp = sparkPos(center, vel, burstAge, 1.0, 0.2);
        let g = softGlow(uv, sp, 0.006 + js * 0.004, fade * shellEnergy * 1.5);
        col += shellColor(hue + js * 0.2, smoothstep(0.5, 0.0, burstAge * 0.2)) * g;
      }

      // Core flash
      col += vec3<f32>(1.0, 0.95, 0.85) * exp(-burstAge * 10.0) * shellEnergy * 2.0 * softGlow(uv, center, 0.07, 1.0);

      // ── STAGE 2: Delayed crackle from sub-points along primary sparks ──
      let stage2Start = stageDelay * (0.6 + seed * 0.4);
      let stage2Age = max(0.0, burstAge - stage2Start);
      if (stage2Age > 0.0 && stage2Age < 4.0) {
        let subPoints = i32(5.0 + mids * 4.0);
        for (var sp = 0; sp < subPoints; sp = sp + 1) {
          let spf = f32(sp);
          let sps = hash1(si * 83.0 + spf * 11.0);
          let sps2 = hash1(si * 37.0 + spf * 7.0);
          let subAng = sps * TAU;
          let subDist = (0.12 + sps2 * 0.2) * shellEnergy;
          let subCenter = center + vec2<f32>(cos(subAng), sin(subAng)) * subDist;

          let crackleCount = i32(4.0 + crackleAmt * 12.0 + treble * 10.0);
          addCrackle(&col, uv, subCenter, stage2Age, shellEnergy * crackleAmt, treble, sps, crackleCount);
        }
      }

      // ── STAGE 3: Palm fronds (mids-driven, after stage 2) ──
      let stage3Start = stage2Start + 0.35 + mids * 0.25;
      let stage3Age = max(0.0, burstAge - stage3Start);
      if (stage3Age > 0.0 && stage3Age < 4.5) {
        let arms = i32(4.0 + palmSpread * 5.0 + mids * 2.0);
        for (var a = 0; a < arms; a = a + 1) {
          let af = f32(a);
          let armAng = (af / f32(arms)) * TAU + seed * 0.5;
          let armOrigin = center + vec2<f32>(cos(armAng), sin(armAng)) * 0.06 * shellEnergy;
          addPalmFrond(&col, uv, armOrigin, armAng, stage3Age, palmSpread, shellEnergy * (0.7 + mids * 0.5), hue + af * 0.1);
        }
      }

      // Continuous treble micro-crackle over whole burst
      if (treble > 0.2 && burstAge > 0.1) {
        let microN = i32(3.0 + treble * crackleAmt * 8.0);
        addCrackle(&col, uv, center, burstAge, shellEnergy * 0.5, treble, seed2, microN);
      }
    }
  }

  // Mouse triple-stage command shell
  if (mouseDown > 0.5) {
    let mAge = fract(time * 0.85) * 4.0;
    if (mAge > 0.9 && mAge < 5.5) {
      let mbAge = mAge - 0.9;
      let mCenter = mouseUV + vec2<f32>(0.0, 0.1);
      let mEnergy = energy * (1.4 + bass);

      // Stage 1
      let mn = i32(40.0);
      for (var mk = 0; mk < mn; mk = mk + 1) {
        let mks = hash1(f32(mk) * 2.3);
        let mang = (f32(mk) / f32(mn)) * TAU;
        let mvel = vec2<f32>(cos(mang), sin(mang)) * (0.6 + mks * 0.7) * mEnergy;
        let mpos = sparkPos(mCenter, mvel, mbAge, 1.0, 0.18);
        col += shellColor(mks, 0.5) * softGlow(uv, mpos, 0.007, smoothstep(4.0, 0.2, mbAge) * mEnergy);
      }

      // Stage 2 crackle
      let mStage2 = max(0.0, mbAge - stageDelay * 0.5);
      if (mStage2 > 0.0) {
        addCrackle(&col, uv, mCenter, mStage2, mEnergy * crackleAmt, treble, 7.0, i32(8.0 + treble * 15.0));
      }

      // Stage 3 palm
      let mStage3 = max(0.0, mbAge - stageDelay * 0.5 - 0.4);
      if (mStage3 > 0.0) {
        let mArms = i32(5.0 + palmSpread * 4.0);
        for (var ma = 0; ma < mArms; ma = ma + 1) {
          let maf = f32(ma);
          addPalmFrond(&col, uv, mCenter, (maf / f32(mArms)) * TAU, mStage3, palmSpread, mEnergy, maf * 0.15);
        }
      }
    }
  }

  // Temporal trails
  col = mix(prev * 0.925, col, 0.3);

  let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
  col *= clamp(vig, 0.15, 1.0) * (0.7 + depth * 0.5);
  col = acesToneMap(col * 1.08);

  let alpha = clamp(length(col) * 1.1 + 0.13, 0.14, 0.96);
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.55 + prev * 0.38, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
