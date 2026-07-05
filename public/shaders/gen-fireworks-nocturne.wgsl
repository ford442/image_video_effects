// ═══════════════════════════════════════════════════════════════════
//  Fireworks Nocturne
//  Category: generative
//  Features: multi-shell pyrotechnics, gravity physics, audio-reactive,
//            mouse command bursts, temporal trails, ember persistence,
//            aces-tone-map, semantic alpha, depth-aware
//  Complexity: Medium-High
//  Created: 2026-07-05
//  By: Spark Engine (Grok)
// ═══════════════════════════════════════════════════════════════════
//  Classic celebration fireworks with:
//  - Staggered mortar launches from base
//  - Ascent streaks (comets)
//  - Timed radial bursts + gravity on sparks
//  - Secondary crackle + long falling embers
//  - Soft volumetric smoke + glow accumulation
//  - Bass = bigger shells + energy, Treble = sparkle/crackle
//  - Mouse hold/click = personal shell at cursor
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

// Canonical ACES
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hashes & noise (canonical forms)
fn hash1(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453123);
}
fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) {
    v += a * vnoise(p * f);
    f *= 2.02;
    a *= 0.5;
  }
  return v;
}

// Soft circular glow (cheap, nice falloff)
fn softGlow(uv: vec2<f32>, center: vec2<f32>, radius: f32, intensity: f32) -> f32 {
  let d = length(uv - center);
  let core = exp(-d * d / (radius * radius * 0.6));
  let halo = exp(-d / (radius * 3.5)) * 0.35;
  return (core + halo) * intensity;
}

// Simple star twinkle
fn starField(uv: vec2<f32>, time: f32, density: f32) -> f32 {
  let grid = floor(uv * 140.0);
  let rnd = hash2(grid);
  if (rnd > density) { return 0.0; }
  let flicker = 0.6 + 0.4 * sin(time * 6.0 + rnd * 40.0);
  return smoothstep(0.92, 1.0, rnd) * flicker * 0.9;
}

// Jewel + metal palette (shiftable)
fn fireworkColor(hue: f32, temp: f32) -> vec3<f32> {
  // 0=gold, 1=crimson, 2=electric blue, 3=emerald, 4=magenta/silver mix
  let g = vec3<f32>(1.00, 0.85, 0.35);
  let c = vec3<f32>(1.00, 0.25, 0.15);
  let b = vec3<f32>(0.30, 0.75, 1.00);
  let e = vec3<f32>(0.20, 0.95, 0.55);
  let m = vec3<f32>(0.95, 0.35, 0.85);

  var col = g;
  if (hue < 0.22) { col = mix(g, c, hue / 0.22); }
  else if (hue < 0.42) { col = mix(c, b, (hue - 0.22) / 0.20); }
  else if (hue < 0.62) { col = mix(b, e, (hue - 0.42) / 0.20); }
  else if (hue < 0.82) { col = mix(e, m, (hue - 0.62) / 0.20); }
  else { col = mix(m, vec3<f32>(0.95, 0.92, 1.0), (hue - 0.82) / 0.18); }

  // Hot white core boost
  col = mix(col, vec3<f32>(1.0), temp * 0.6);
  return col;
}

// Gravity + drag physics position for a spark
fn sparkPos(origin: vec2<f32>, vel: vec2<f32>, age: f32, g: f32, drag: f32) -> vec2<f32> {
  let t = age;
  let dragFactor = exp(-drag * t);
  let vx = vel.x * dragFactor;
  let vy = vel.y * dragFactor - g * t * 0.5;  // integrate gravity
  return origin + vec2<f32>(vx, vy) * t;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;
  let dt = max(u.config.y, 0.001);

  let mouse = vec2<f32>(u.zoom_config.yz);
  let mouseDown = u.zoom_config.w;
  let mouseUV = (mouse - res * 0.5) / min(res.x, res.y);

  // Params
  let energy = mix(0.4, 1.6, u.zoom_params.x);
  let tempo = mix(0.6, 1.7, u.zoom_params.y);
  let density = mix(0.4, 1.35, u.zoom_params.z);
  let colorDrift = u.zoom_params.w;

  // Audio
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Depth tint (subtle)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
  let depthBoost = 0.7 + depth * 0.6;

  var col = vec3<f32>(0.0);

  // ── Night sky base + starfield ──
  let sky = vec3<f32>(0.015, 0.012, 0.035);
  col += sky;
  let stars = starField(uv * 1.0 + vec2<f32>(time * 0.003, -time * 0.001), time, 0.012 + bass * 0.003);
  col += vec3<f32>(0.85, 0.9, 1.0) * stars * 0.85;

  // Subtle nebular haze
  let haze = fbm(uv * 1.8 + vec2<f32>(time * 0.008, time * 0.012), 3) * 0.035;
  col += vec3<f32>(0.04, 0.03, 0.07) * haze;

  // ── Firework shells (8 primary + some variation) ──
  let numShells = 9;
  let basePeriod = 1.85 / tempo;  // seconds between new shells on average

  for (var s: i32 = 0; s < numShells; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 17.3 + 11.0);
    let seed2 = hash1(si * 29.7 + 7.0);

    // Staggered launch timing
    let launchOffset = seed * basePeriod * 0.9;
    let cycle = basePeriod * (0.85 + seed2 * 0.35);
    let shellTime = time * tempo + launchOffset;
    let shellBirth = floor(shellTime / cycle) * cycle - launchOffset;
    let age = time - shellBirth;

    if (age < 0.0 || age > 7.5) { continue; }

    // Launch base position (bottom third, spread)
    let baseX = (seed - 0.5) * 1.85 + sin(si * 1.7 + time * 0.1) * 0.08;
    let baseY = -0.82 + seed2 * 0.04;
    let launchPos = vec2<f32>(baseX, baseY);

    let burstDelay = 1.35 + seed * 0.9;          // time to apex
    let burstAge = max(0.0, age - burstDelay);

    // Energy from bass + global param
    let shellEnergy = energy * (0.75 + bass * 0.9);

    // Ascent comet phase
    if (age < burstDelay + 0.15) {
      let ascendT = age / burstDelay;
      let curY = mix(baseY, baseY + 1.35, ascendT * ascendT * (3.0 - 2.0 * ascendT)); // ease
      let cometPos = vec2<f32>(baseX, curY);

      // Ascent streak
      let streakLen = 0.035 + bass * 0.01;
      for (var k = 0; k < 4; k = k + 1) {
        let kF = f32(k) * 0.22;
        let past = cometPos - vec2<f32>(0.0, kF * streakLen);
        let g = softGlow(uv, past, 0.009 + kF * 0.004, (1.0 - kF * 1.4) * shellEnergy * 1.6);
        let cAsc = mix(vec3<f32>(1.0, 0.95, 0.7), vec3<f32>(1.0, 0.75, 0.4), kF);
        col += cAsc * g;
      }
      // Bright head
      col += vec3<f32>(1.0, 0.97, 0.85) * softGlow(uv, cometPos, 0.011, shellEnergy * 3.2);
    }

    // Burst + falling phase
    if (burstAge > 0.0 && burstAge < 5.5) {
      let burstCenter = vec2<f32>(baseX + (seed2 - 0.5) * 0.04, baseY + 1.32);

      // Primary radial burst
      let numSparks = i32(38.0 + density * 48.0 + mids * 12.0);
      let burstHueBase = fract(seed * 1.7 + colorDrift * 0.6 + time * 0.015);

      for (var j: i32 = 0; j < numSparks; j = j + 1) {
        let jf = f32(j);
        let jSeed = hash1(si * 91.0 + jf * 3.7);
        let jSeed2 = hash1(si * 13.0 + jf * 7.1 + 50.0);

        let angle = (jf / f32(numSparks)) * TAU + (jSeed - 0.5) * 0.7;
        let speed = (0.55 + jSeed2 * 0.65) * (0.9 + shellEnergy * 0.35);

        let vel = vec2<f32>(cos(angle), sin(angle)) * speed;
        let grav = 1.15 + shellEnergy * 0.15;   // gravity strength
        let drag = 0.18;

        let sp = sparkPos(burstCenter, vel, burstAge, grav, drag);

        // Lifetime fade + distance fade
        let lifeFade = smoothstep(4.8, 0.6, burstAge) * (0.6 + jSeed * 0.4);
        let size = (0.0065 + jSeed2 * 0.005) * (1.0 + bass * 0.2) * (1.0 - burstAge * 0.07);

        let glow = softGlow(uv, sp, size, lifeFade * shellEnergy * 1.8);

        let hue = fract(burstHueBase + jSeed * 0.35 + colorDrift);
        let temp = smoothstep(0.0, 0.6, 1.0 - burstAge * 0.18); // hot at birth
        let sparkCol = fireworkColor(hue, temp);

        col += sparkCol * glow * (0.85 + treble * 0.6);
      }

      // Secondary crackle / micro bursts (treble driven)
      let crackles = i32(6.0 + treble * 14.0);
      for (var c = 0; c < crackles; c = c + 1) {
        let cf = f32(c);
        let cSeed = hash1(si * 44.0 + cf * 19.0 + time * 3.0);
        let cAngle = cSeed * TAU + time * (2.0 + cSeed);
        let cSpeed = 0.35 + cSeed * 0.4;
        let cVel = vec2<f32>(cos(cAngle), sin(cAngle)) * cSpeed;
        let cPos = sparkPos(burstCenter, cVel, burstAge * 0.6, 0.9, 0.35);

        let cGlow = softGlow(uv, cPos, 0.0045, (0.4 + treble * 0.8) * lifeFade * shellEnergy);
        col += vec3<f32>(0.95, 0.98, 1.0) * cGlow * 1.4;
      }

      // Core flash ring (brief)
      let ring = exp(-abs(burstAge - 0.12) * 11.0) * shellEnergy * 1.4;
      col += vec3<f32>(1.0, 0.95, 0.8) * ring * softGlow(uv, burstCenter, 0.09, 1.0);
    }

    // Long-lived falling embers (willow / peony style)
    if (burstAge > 0.8 && burstAge < 6.8) {
      let emberCount = i32(11.0 + density * 9.0);
      for (var e = 0; e < emberCount; e = e + 1) {
        let ef = f32(e);
        let eSeed = hash1(si * 63.0 + ef * 5.3);
        let eAngle = eSeed * TAU + (eSeed - 0.5) * 1.6;
        let eVel = vec2<f32>(cos(eAngle), sin(eAngle) * 0.6) * (0.28 + eSeed * 0.25);
        let emberPos = sparkPos(burstCenter, eVel, burstAge * 0.9, 0.72, 0.05);

        let eAge = burstAge - 0.7;
        let eFade = smoothstep(5.8, 1.2, eAge);
        let eg = softGlow(uv, emberPos, 0.0055, eFade * 0.9 * shellEnergy * 0.7);

        let emberCol = mix(vec3<f32>(1.0, 0.55, 0.15), vec3<f32>(0.9, 0.3, 0.1), eAge * 0.12);
        col += emberCol * eg;
      }
    }
  }

  // ── User / mouse command shell (big special burst) ──
  if (mouseDown > 0.5 || length(mouseUV) < 10.0) {  // always consider mouse pos
    let mAge = fract(time * 0.9) * 3.8;  // cycling personal bursts when held
    let mBurstT = 1.1;
    let mCenter = mouseUV + vec2<f32>(0.0, 0.1); // slight lift

    if (mAge > mBurstT - 0.6 && mAge < 5.0) {
      let mBurstAge = max(0.0, mAge - mBurstT);
      let mEnergy = energy * (1.6 + bass * 0.8);

      // Fast bright ascent from mouse toward top when held
      if (mBurstAge < 0.9) {
        let asc = mix(mCenter.y, mCenter.y + 0.9, smoothstep(0.0, 0.9, mBurstAge));
        let head = vec2<f32>(mCenter.x, asc);
        col += vec3<f32>(1.0, 0.92, 0.6) * softGlow(uv, head, 0.018, mEnergy * 2.8);
      }

      // Massive colorful burst
      let mSparks = i32(55.0 + density * 55.0);
      for (var ms = 0; ms < mSparks; ms = ms + 1) {
        let msf = f32(ms);
        let msSeed = hash1(msf * 9.1 + 3.0);
        let ang = msf / f32(mSparks) * TAU + (msSeed - 0.5) * 1.1;
        let mVel = vec2<f32>(cos(ang), sin(ang)) * (0.7 + msSeed * 0.8);
        let mPos = sparkPos(mCenter, mVel, mBurstAge, 1.05, 0.22);

        let mFade = smoothstep(4.2, 0.4, mBurstAge);
        let mSz = 0.007 + msSeed * 0.006;
        let mg = softGlow(uv, mPos, mSz, mFade * mEnergy * 1.5);

        let mh = fract(msSeed * 1.6 + colorDrift + time * 0.03);
        let mc = fireworkColor(mh, 0.6 - mBurstAge * 0.1);
        col += mc * mg * (1.0 + treble * 0.5);
      }
    }
  }

  // ── Soft smoke / lingering glow from dataTextureC (temporal) ──
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let smoke = fbm(uv * 2.4 + vec2<f32>(time * 0.02, -time * 0.015), 2) * 0.035;
  let decay = 0.935 - bass * 0.015;  // bass can keep glow hotter
  col = mix(prev * decay + smoke, col, 0.28);

  // Extra sparkle layer driven by treble (global dust)
  let sparkDust = step(0.988 - treble * 0.035, hash2(uv * 190.0 + time * 12.0));
  col += vec3<f32>(0.7, 0.85, 1.0) * sparkDust * (0.6 + treble);

  // Vignette + slight cinematic lift
  let vig = 1.0 - dot(uv * 0.72, uv * 0.72);
  col *= clamp(vig, 0.15, 1.0) * 1.25;
  col *= depthBoost;

  // Chromatic pop on very bright areas (subtle)
  let br = length(col);
  let ca = 0.0018 * saturate((br - 1.0) * 0.7);
  col = vec3<f32>(col.r + ca, col.g, col.b - ca * 0.6);

  // ACES + final
  col = acesToneMap(col * 1.05);

  // Semantic alpha (bright = more opaque)
  let alpha = clamp(br * 1.15 + 0.15, 0.15, 0.98);

  // Persist state for trails/smoke
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(dataTextureC, pixel, vec4<f32>(col * 0.6 + prev * 0.35, 1.0)); // light feedback

  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
