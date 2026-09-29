// ═══════════════════════════════════════════════════════════════════
//  Image Pyro
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: drag-damped spark flight; shell types per mortar (peony / willow / ring); crossette split
//  A packing: ACES display RGBA (rgb = tone-mapped colour, read back from C as trail history; a = semantic glow alpha)
// ═══════════════════════════════════════════════════════════════════
//  Created 2026-07-05 (Spark Engine). The loaded image (or video frame)
//  is the source material. Bright areas "ignite" and launch fireworks
//  whose sparks carry the photo's own colors.
//  Floor fixes (2026-09-28): scene is y-up (pixel y flipped) so shells rise
//  and gravity pulls down; pointer is zoom_config.yz UV mapped into scene uv;
//  image sampled full-frame (was 2x zoomed); core flash falls off from the
//  burst centre; Trail Length now lengthens trails (mirror map, same 0.9025
//  decay at default 0.5); unread dataTextureB write removed; depth = this
//  frame's firework glow (bright = forward) over a far backdrop; one
//  consistent launch clock (HEAD mixed scaled and real time, so every mortar
//  went permanently dark after ~27 s at default; before that a shell was
//  reset before its burst could open). Each mortar now fires every 3 cycles
//  (~4.8 s at default) with phases spread over the period. Shell rise
//  (ASCENT) scaled to the real ±0.5 frame so bursts open on screen, and the
//  launch-brightness probe reads the photo instead of the clamped bottom row.
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
// FLOOR: shell rise height. HEAD's 1.12 assumed a [-1,1] frame; the short axis spans
// [-0.5,0.5], so bursts opened on (or past) the top edge. 0.76 opens them upper-middle.
const ASCENT: f32 = 0.76;

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

// Scene uv is y-up with the short axis spanning [-0.5, 0.5]; map to the full frame (y=0 top).
fn sampleImage(uv: vec2<f32>, res: vec2<f32>) -> vec3<f32> {
  let m = min(res.x, res.y);
  let q = vec2<f32>(uv.x * m / res.x + 0.5, 0.5 - uv.y * m / res.y);
  let p = clamp(q, vec2<f32>(0.0), vec2<f32>(1.0));
  return textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  let t = age;
  return o + v * t - vec2<f32>(0.0, g) * t * t * 0.5;
}

// Idea 1 — drag-damped spark flight. Closed form of p'' = -k p' - g y^ :
//   p = o + v (1 - e^{-kt})/k - g y^ (t/k - (1 - e^{-kt})/k^2)
// Sparks decelerate, then droop at terminal speed g/k. Callers pass k > 0.
fn sparkPosDrag(o: vec2<f32>, v: vec2<f32>, t: f32, g: f32, k: f32) -> vec2<f32> {
  let e = 1.0 - exp(-k * t);
  return o + v * (e / k) - vec2<f32>(0.0, g * (t / k - e / (k * k)));
}
fn sparkVelDrag(v: vec2<f32>, t: f32, g: f32, k: f32) -> vec2<f32> {
  let ek = exp(-k * t);
  return v * ek - vec2<f32>(0.0, g * (1.0 - ek) / k);
}

// Capsule glow (softGlow's profile around a segment) for willow tails.
fn segGlow(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32, i: f32) -> f32 {
  let ab = b - a;
  let h = clamp(dot(uv - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
  let d = length(uv - a - ab * h);
  return (exp(-d*d/(r*r*0.55)) + 0.32 * exp(-d/(r*3.2))) * i;
}

fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a); let s = sin(a);
  return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  // FLOOR: y-up scene — pixel y grows downward, so flip it.
  let minRes = min(res.x, res.y);
  let uv = vec2<f32>(f32(pixel.x) - res.x * 0.5, res.y * 0.5 - f32(pixel.y)) / minRes;
  let time = u.config.x;

  // FLOOR: zoom_config.yz is the pointer in canvas UV 0..1 (y=0 top); map into scene uv.
  let mouse = vec2<f32>(u.zoom_config.yz);
  let mouseDown = u.zoom_config.w;
  let mUV = vec2<f32>((mouse.x - 0.5) * res.x, (0.5 - mouse.y) * res.y) / minRes;

  let power = mix(0.35, 1.9, u.zoom_params.x);
  let ignition = mix(0.3, 1.4, u.zoom_params.y);
  // FLOOR: Trail Length lengthens trails (mirror of HEAD's inverted map; decay 0.9025 at default 0.5).
  let trail = mix(0.3, 0.95, 1.0 - u.zoom_params.z);
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
  var glowAcc = 0.0; // this frame's firework light, for depth

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
    // FLOOR: the launch site sits just below the frame (short axis spans ±0.5), so read
    // the photo a little above it — HEAD's probe sampled the clamped bottom row only.
    let probeCol = sampleImage(vec2<f32>(probe.x, -0.3), res);
    let probeLum = dot(probeCol, vec3<f32>(0.299, 0.587, 0.114));
    let spawnProb = smoothstep(0.12, 0.75, probeLum) * 0.9 + 0.1;

    // FLOOR: one local launch clock. Each mortar fires once per 3 ignition cycles,
    // phases spread over the whole period; age is in real seconds.
    let cycle = 2.1 / (0.7 + ignition * 0.6);
    let rate = 0.7 + ignition * 0.4;
    let period = cycle * 3.0;
    let tl = time * rate + seed * period;
    let cyc = floor(tl / period);
    let age = (tl - cyc * period) / rate;
    let lifeS = period / rate;
    if (age < 0.0 || age > 6.5) { continue; }
    let lifeEnd = min(lifeS, 6.5);
    let endFade = 1.0 - smoothstep(lifeEnd - 0.45, lifeEnd, age);

    let basePos = probe + vec2<f32>(0.0, -0.05);
    let burstDelay = 1.25 + seed * 0.6;
    let bAge = max(0.0, age - burstDelay);

    let shellPow = power * (0.6 + probeLum * 1.1 + bass * 0.7);

    // Idea 2 — shell type per mortar per cycle: 0 peony (60%), 1 willow (22%), 2 ring (18%).
    let typeH = hash1(si * 53.1 + cyc * 7.13);
    var shellType = 0;
    if (typeH < 0.22) { shellType = 1; } else if (typeH < 0.40) { shellType = 2; }
    // Idea 3 — half the peony shells carry crossette stars.
    let crossShell = shellType == 0 && hash1(si * 17.3 + cyc * 3.71) < 0.5;
    let ringTilt = mix(0.25, 1.0, hash1(si * 5.1 + cyc * 1.9));   // ring plane seen edge-on .. face-on
    let ringRoll = (hash1(si * 8.3 + cyc * 2.7) - 0.5) * 1.2;

    // Ascent
    if (age < burstDelay) {
      let t = age / burstDelay;
      let y = mix(basePos.y, basePos.y + ASCENT * 1.03, t * t);
      let pos = vec2<f32>(basePos.x, y);
      let streak = softGlow(uv, pos, 0.012, shellPow * 1.9);
      let ascCol = mix(vec3<f32>(0.9, 0.85, 0.6), probeCol * 0.8 + 0.2, 0.5);
      col += ascCol * streak;
      glowAcc += streak;
    }

    // Main burst — sample image colors for the sparks
    let burstLife = select(4.8, 5.8, shellType == 1);
    if (bAge > 0.0 && bAge < burstLife) {
      let bCenter = vec2<f32>(basePos.x * 0.9, basePos.y + ASCENT);
      let nSparks = i32(32.0 + power * 42.0 + mids * 18.0);
      let gGrav = 1.05 + shellPow * 0.1;
      // Idea 1 — drag per shell type (willow: heavy drag, slow droop).
      let kDrag = select(2.4, 4.6, shellType == 1);
      let fadeEnd = select(4.3, 5.6, shellType == 1);
      let fade = smoothstep(fadeEnd, 0.5, bAge) * endFade;
      for (var j = 0; j < nSparks; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si * 7.0 + jf * 2.3);
        let js2 = hash1(si * 11.0 + jf * 5.9);
        let ang = (jf / f32(nSparks)) * TAU + (js - 0.5) * 1.2;
        let spd = (0.48 + js2 * 0.7) * (0.85 + shellPow * 0.4);
        var vel = vec2<f32>(cos(ang), sin(ang)) * spd;
        if (shellType == 1) {
          vel *= 1.4;                                   // willow: stronger lift charge vs heavy drag
        } else if (shellType == 2) {
          // Idea 2 — ring: evenly spaced stars on a tilted planar ellipse, near-uniform speed.
          let ra = (jf / f32(nSparks)) * TAU;
          let rs = (0.8 + js2 * 0.08) * (0.85 + shellPow * 0.4);
          vel = rot2(vec2<f32>(cos(ra), sin(ra) * ringTilt), ringRoll) * rs;
        }

        let sp = sparkPosDrag(bCenter, vel, bAge, gGrav, kDrag);

        // Sample image near burst center for color (with twist)
        let sampleUV = bCenter * 0.6 + sp * 0.4;
        var sparkCol = sampleImage(sampleUV, res);
        sparkCol = mix(sparkCol, vec3<f32>(0.95, 0.7, 0.4), js * 0.3); // gold bias
        if (shellType == 1) {
          sparkCol = mix(sparkCol, vec3<f32>(1.0, 0.72, 0.32), 0.65); // willow: charcoal gold
        }
        sparkCol = sparkCol * (0.7 + 0.6 * js2);

        // Hue twist param
        let lumC = length(sparkCol);
        sparkCol = mix(sparkCol, vec3<f32>(lumC), abs(hueTwist) * 0.5);
        if (hueTwist > 0.0) { sparkCol = sparkCol.bgr; }

        let amp = fade * shellPow * 1.6;
        let rad = 0.007 + js * 0.005;
        var g = 0.0;
        if (shellType == 1) {
          // Willow: long hanging tail from 0.3 s back along the drooping path.
          let tailP = sparkPosDrag(bCenter, vel, max(bAge - 0.3, 0.0), gGrav, kDrag);
          g = segGlow(uv, tailP, sp, rad * 0.8, amp);
        } else if (crossShell && js2 > 0.72) {
          // Idea 3 — crossette: the star splits into four at mid-life, children at
          // heading ±45° / ±135° (a cross, 90° apart), carrying some parent momentum.
          let tS = 0.55 + js * 0.35;
          if (bAge < tS) {
            g = softGlow(uv, sp, rad, amp);
          } else {
            let pS = sparkPosDrag(bCenter, vel, tS, gGrav, kDrag);
            let vS = sparkVelDrag(vel, tS, gGrav, kDrag);
            let hd = normalize(vS + vec2<f32>(1e-5, 0.0));
            let cAge = bAge - tS;
            for (var c = 0; c < 4; c = c + 1) {
              let cd = rot2(hd, PI * 0.25 + f32(c) * PI * 0.5);
              let cv = vS * 0.35 + cd * (0.45 * spd);
              let cp = sparkPosDrag(pS, cv, cAge, gGrav, kDrag);
              g += softGlow(uv, cp, 0.006, amp * 0.75);
            }
            g += softGlow(uv, pS, 0.012, amp * 2.0 * exp(-cAge * 12.0)); // split pop
          }
        } else {
          g = softGlow(uv, sp, rad, amp);
        }

        col += sparkCol * g * (0.9 + treble * 0.7);
        glowAcc += g;
      }

      // Quick core flash using image brightness
      // FLOOR: fall off from the burst centre (HEAD lit the whole screen uniformly).
      let cdist = length(uv - bCenter);
      let coreFall = 0.8 * exp(-cdist * cdist / 0.035) + 0.2 * exp(-cdist * 5.0);
      let core = exp(-bAge * 9.0) * shellPow * 1.8 * coreFall;
      col += probeCol * core * 1.3;
      glowAcc += core;
    }

    // Lingering embers tinted by image
    if (bAge > 0.6 && bAge < 5.5) {
      let emN = i32(9.0 + power * 7.0);
      for (var e = 0; e < emN; e = e + 1) {
        let es = hash1(si * 27.0 + f32(e) * 4.1);
        let eang = es * TAU * 0.6;
        let evel = vec2<f32>(cos(eang), -0.3 + sin(eang) * 0.3) * (0.22 + es * 0.2);
        let epos = sparkPos(basePos + vec2<f32>(0.0, ASCENT * 0.98), evel, bAge * 0.85, 0.65);
        let ef = softGlow(uv, epos, 0.005, smoothstep(4.8, 1.0, bAge - 0.5) * shellPow * 0.65) * endFade;
        let ecol = sampleImage(epos * 0.7 + basePos * 0.3, res) * 0.85;
        col += ecol * ef;
        glowAcc += ef;
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
        let kp = sparkPosDrag(mC, kv, mbAge, 1.0, 2.4); // Idea 1 — same drag flight
        let kg = softGlow(uv, kp, 0.0065, smoothstep(3.0, 0.2, mbAge) * mPow);
        let kc = sampleImage(kp * 0.4 + mUV * 0.6, res);
        col += kc * kg * (1.0 + treble * 0.4);
        glowAcc += kg;
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

  // Feedback state: A = ACES display RGBA (C.rgb read back as trail history).
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));

  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  // Depth: far photo backdrop (0.1); this frame's sparks / glow pull forward.
  let depth = 0.1 + 0.85 * (1.0 - exp(-glowAcc * 1.5));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
