// ═══════════════════════════════════════════════════════════════════
//  Willow Cascade
//  Category: generative
//  Features: willow-style drooping trails, wind drift, long-exposure
//            temporal persistence, golden/silver palette, audio-reactive,
//            mouse command shell, aces-tone-map, semantic alpha
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

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

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
  return (exp(-d * d / (r * r * 0.5)) + 0.4 * exp(-d / (r * 4.0))) * i;
}

// Willow spark: slow fall, wind drift, heavy drag
fn willowPos(origin: vec2<f32>, vel: vec2<f32>, age: f32, droop: f32, wind: f32) -> vec2<f32> {
  let t = age;
  let drag = exp(-0.08 * t);
  let windDrift = wind * t * (1.0 - exp(-t * 0.4));
  let grav = droop * t * t * 0.5;
  return origin + vec2<f32>(vel.x * drag + windDrift, vel.y * drag - grav);
}

fn willowColor(warmth: f32, silver: f32, age: f32) -> vec3<f32> {
  let gold = vec3<f32>(1.0, 0.82, 0.35);
  let silv = vec3<f32>(0.85, 0.9, 1.0);
  let amber = vec3<f32>(1.0, 0.55, 0.12);
  var col = mix(silv, gold, warmth);
  col = mix(col, amber, (1.0 - warmth) * 0.4);
  col = mix(col, silv, silver * 0.7);
  // Fade warm as spark ages
  col = mix(col, vec3<f32>(0.7, 0.45, 0.15), saturate(age * 0.08));
  return col;
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

  let trailLen = mix(0.88, 0.97, u.zoom_params.x);
  let droopAmt = mix(0.35, 1.15, u.zoom_params.y);
  let windAmt = mix(-0.12, 0.35, u.zoom_params.z) + sin(time * 0.15) * 0.04;
  let warmth = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  var col = vec3<f32>(0.012, 0.01, 0.028);

  // Starfield
  let star = step(0.992, hash2(floor(uv * 120.0))) * (0.5 + 0.5 * sin(time * 5.0 + hash2(uv * 50.0) * 20.0));
  col += vec3<f32>(0.8, 0.85, 1.0) * star * 0.7;

  // Willow shells — fewer, more majestic
  let numShells = 6;
  let basePeriod = 2.8;

  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 23.1 + 5.0);
    let seed2 = hash1(si * 41.7 + 3.0);

    let cycle = basePeriod * (0.9 + seed * 0.4);
    let birth = floor((time * (0.55 + mids * 0.15) + seed * 2.1) / cycle) * cycle - seed * 2.1;
    let age = time - birth;
    if (age < 0.0 || age > 9.0) { continue; }

    let baseX = (seed - 0.5) * 1.6;
    let baseY = -0.78;
    let burstDelay = 1.5 + seed * 0.7;
    let burstAge = max(0.0, age - burstDelay);
    let shellEnergy = (0.7 + bass * 0.6) * (1.0 + seed2 * 0.2);

    // Ascent comet (brief golden streak)
    if (age < burstDelay + 0.1) {
      let t = age / burstDelay;
      let y = mix(baseY, baseY + 1.4, t * t);
      let head = vec2<f32>(baseX, y);
      col += vec3<f32>(1.0, 0.9, 0.6) * softGlow(uv, head, 0.01, shellEnergy * 2.5);
      for (var k = 0; k < 3; k = k + 1) {
        let kf = f32(k) * 0.25;
        col += vec3<f32>(1.0, 0.75, 0.3) * softGlow(uv, head - vec2<f32>(0.0, kf * 0.04), 0.007, (1.0 - kf) * shellEnergy);
      }
    }

    // Willow burst — drooping curtain of sparks
    if (burstAge > 0.0 && burstAge < 8.0) {
      let burstCenter = vec2<f32>(baseX, baseY + 1.38);
      let burstFade = smoothstep(7.5, 0.5, burstAge);

      // Core flash
      col += vec3<f32>(1.0, 0.95, 0.8) * exp(-burstAge * 6.0) * shellEnergy * softGlow(uv, burstCenter, 0.07, 1.5);

      let numStrands = i32(28.0 + seed * 12.0);
      for (var j: i32 = 0; j < numStrands; j = j + 1) {
        let jf = f32(j);
        let jSeed = hash1(si * 67.0 + jf * 4.3);
        let jSeed2 = hash1(si * 19.0 + jf * 8.1);

        // Upward launch then gravity droop
        let angle = (jf / f32(numStrands)) * TAU + (jSeed - 0.5) * 0.5;
        let upSpeed = (0.35 + jSeed2 * 0.45) * shellEnergy;
        let vel = vec2<f32>(cos(angle) * upSpeed * 0.6, sin(angle) * upSpeed + 0.25);

        let wPos = willowPos(burstCenter, vel, burstAge, droopAmt * (0.8 + bass * 0.3), windAmt + jSeed * 0.08);

        // Velocity-stretched droop streak along fall direction.
        let fallDir = normalize(vec2<f32>(windAmt + jSeed * 0.08, -1.0));
        let streak = exp(-abs(dot(uv - wPos, vec2<f32>(-fallDir.y, fallDir.x))) * 120.0) *
                     exp(-abs(dot(uv - wPos, fallDir) + burstAge * 0.2) * 14.0) * burstFade * 0.4;

        // Trail samples along the arc (willow curtain effect)
        for (var t = 0; t < 5; t = t + 1) {
          let tf = f32(t) * 0.18;
          let trailAge = max(0.0, burstAge - tf);
          let tPos = willowPos(burstCenter, vel, trailAge, droopAmt * (0.8 + bass * 0.3), windAmt);
          let tFade = burstFade * (1.0 - tf * 0.7) * (0.5 + jSeed * 0.5);
          let tSize = 0.005 + jSeed2 * 0.004;
          let tg = softGlow(uv, tPos, tSize, tFade * shellEnergy * 1.4);
          let tc = willowColor(warmth, jSeed * treble, burstAge + tf);
          col += tc * tg;
        }
        col += willowColor(warmth, jSeed * treble, burstAge) * streak * shellEnergy;

        // Silver micro-sparkle along strand (treble)
        if (treble > 0.3) {
          let micro = softGlow(uv, wPos, 0.003, treble * burstFade * 0.8);
          col += vec3<f32>(0.75, 0.88, 1.0) * micro * jSeed;
        }
      }

      // Soft smoke following trails
      let smoke = fbm(uv * 1.5 + burstCenter + vec2<f32>(time * 0.01, -burstAge * 0.05), 2);
      col += vec3<f32>(0.04, 0.035, 0.05) * smoke * burstFade * 0.06 * shellEnergy;
    }
  }

  // Mouse willow shell
  if (mouseDown > 0.5) {
    let mAge = fract(time * 0.7) * 4.5;
    let mBurst = 1.2;
    if (mAge > mBurst && mAge < 7.0) {
      let mbAge = mAge - mBurst;
      let mCenter = mouseUV + vec2<f32>(0.0, 0.12);
      let mFade = smoothstep(6.0, 0.3, mbAge);
      let mEnergy = (1.2 + bass * 0.8);

      col += vec3<f32>(1.0, 0.92, 0.7) * exp(-mbAge * 5.0) * mEnergy * softGlow(uv, mCenter, 0.08, 1.8);

      let mStrands = i32(40.0);
      for (var m = 0; m < mStrands; m = m + 1) {
        let mf = f32(m);
        let ms = hash1(mf * 3.7 + 1.0);
        let ang = (mf / f32(mStrands)) * TAU;
        let mVel = vec2<f32>(cos(ang) * 0.4, 0.5 + ms * 0.4) * mEnergy;
        let mPos = willowPos(mCenter, mVel, mbAge, droopAmt * 1.1, windAmt * 1.5);
        let mg = softGlow(uv, mPos, 0.006, mFade * mEnergy);
        col += willowColor(warmth, ms, mbAge) * mg;
      }
    }
  }

  // Advected HDR willow trails.
  let histCoord = clamp(pixel - vec2<i32>(vec2<f32>(windAmt * 8.0, -2.0 - droopAmt)),
                        vec2<i32>(0), vec2<i32>(i32(res.x) - 1, i32(res.y) - 1));
  let prevHist = textureLoad(dataTextureC, histCoord, 0).rgb;
  col = clamp(col + prevHist * trailLen, vec3<f32>(0.0), vec3<f32>(5.5));

  // Treble dust
  let dust = step(0.987 - treble * 0.03, hash2(uv * 200.0 + time * 10.0));
  col += vec3<f32>(0.7, 0.82, 1.0) * dust * treble * 0.5;

  let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
  col *= clamp(vig, 0.18, 1.0) * (0.75 + depth * 0.5);

  col = acesToneMap(col * 1.08);
  let alpha = clamp(length(col) * 1.1 + 0.12, 0.15, 0.96);
  let genDepth = clamp(1.0 - length(col) * 0.2, 0.05, 0.98);

  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(genDepth, 0.0, 0.0, 0.0));
}
