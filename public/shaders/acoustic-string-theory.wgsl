// ═══════════════════════════════════════════════════════════════════
//  Acoustic String Theory
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, feedback-loop,
//            gravity-well, spring-damper, pluck-on-click, spectrum-drive,
//            shockwave, video-luma, sparkle
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07, 2026-11-08
//  Interactivist pass: 2026-07-22 (pluck excitation, spring well, band weights)
//  Ideas: sympathetic resonance (ratio-matched unplucked strings swell and ring); tension-modulation pitch glide (closed-form chirp tracking the pluck decay); standing-wave nodal pins on each string's own wavelength
//  A packing: r = bass envelope (global), g = harmonicField, b = nodeField, a = alpha; texels (0,0) = spring well (pos.xy, vel.xy) and (1,0) = (fract(lastTime), -, -, 0.7371 sentinel) are STATE, not pixels
//  2026-11-08 rescue: the spring well / pluck state lived in extraBuffer[133..141], which the host
//    re-uploads (zeroes) every frame - the well sat at the screen centre and plucks never fired - and
//    `dt` was config.y (the ripple count). State now lives in two A texels with a sentinel, dt comes
//    from the time stored there, and the pluck is the newest click ripple (u.ripples).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// State map (A texels; exact textureLoad on C, sentinel guards inherited / first-frame garbage):
//   (0,0) = well pos.x, well pos.y, well vel.x, well vel.y     (string space, aspect-corrected)
//   (1,0) = lastTime, 0, 0, SENT
// Pluck = the newest ripple in u.ripples (a click spawns one), so it needs no state.
const SENT: f32 = 0.7371;

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

// x*x, not pow(x, 2.0): the base is often negative and WGSL leaves pow(neg, y) undefined.
fn sq(x: f32) -> f32 {
  return x * x;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  let dist2 = dot(d, d) + 0.01;
  return d / max(length(d), 1e-4) * strength / dist2;
}

// Spectral weight: which audio band excites string at normalized index t01.
// Low strings answer the bass, middle strings the mids, high strings the treble.
fn bandWeight(t01: f32, bass: f32, mids: f32, treble: f32) -> f32 {
  let bw = bass * exp(-sq((t01 - 0.12) * 2.4));
  let mw = mids * exp(-sq((t01 - 0.50) * 2.8));
  let tw = treble * exp(-sq((t01 - 0.88) * 2.4));
  return bw + mw + tw;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let rawBass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // State texels (previous frame) + sentinel; (2,0) is an ordinary pixel and
  // carries the global bass envelope in .r.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  let envPrev = select(rawBass, textureLoad(dataTextureC, vec2<i32>(2, 0), 0).r, stateOk);
  var prev = textureLoad(dataTextureC, coord, 0);
  prev = select(prev, vec4<f32>(0.0), (gid.y == 0u) && (gid.x < 2u));   // state texels carry no trail
  let bass = bass_env(envPrev, rawBass, 0.8, 0.15);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w;

  let strings = mix(2.0, 16.0, u.zoom_params.x);
  let tension = mix(0.5, 5.0, u.zoom_params.y);
  let harmonics = mix(1.0, 8.0, u.zoom_params.z);
  let resonance = mix(0.2, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);

  // ── Interactive state ──────────────────────────────────────────────
  // Spring-damper: the gravity well chases the mouse with damped overshoot.
  // Every thread integrates the same step from the same C texels, so all agree;
  // the two state texels persist it (written at the end of main).
  let targetPos = vec2<f32>(mouse.x * aspect, mouse.y);
  // lastTime is stored as fract(time): A is rgba16float on the balanced / battery tiers, where an absolute
  // time loses its 0.017 s resolution after ~1 minute. fract(time - fract(t0)) = fract(time - t0).
  let dt = clamp(fract(time - select(time, st1.x, stateOk)), 0.001, 0.05);
  let wPos0 = select(targetPos, st0.xy, stateOk);
  let wVel0 = select(vec2<f32>(0.0), st0.zw, stateOk);
  let stiff = 42.0;
  let damping = 7.0;
  let wVel = wVel0 + ((targetPos - wPos0) * stiff - wVel0 * damping) * dt;
  let wellPos = wPos0 + wVel * dt;

  // Pluck: the newest click ripple (strength 1). Aspect-corrected string space.
  var pluckTime = -100.0;
  var pluckX = 0.0;
  var pluckY = 0.0;
  let rCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let newer = rp.z > pluckTime;
    pluckTime = select(pluckTime, rp.z, newer);
    pluckX = select(pluckX, (rp.x * 2.0 - 1.0) * aspect, newer);
    pluckY = select(pluckY, rp.y * 2.0 - 1.0, newer);
  }
  let pluckAmp = select(0.0, 1.0, rCount > 0u);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Spring-following gravity well bends string space
  let well = gravityWell(p, wellPos, 0.08 + bass * 0.06);
  p = p + well;

  // Click shockwave ripple
  let mDist = length(p - wellPos);
  let shock = exp(-mDist * 4.0) * mouseDown * sin(mDist * 25.0 - time * 10.0);

  // Video luma feedback boosts brightness
  let vid = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(vid, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = smoothstep(0.5, 1.0, luma) * 0.4;

  // Pluck envelope: gaussian strike that rings down faster under high tension.
  let pluckAge = max(time - pluckTime, 0.0);
  let pluckRate = 1.2 + tension * 1.6;
  let pluckDecay = exp(-pluckAge * pluckRate);
  let pluckEnv = pluckAmp * pluckDecay;
  let pluckGauss = exp(-sq((p.x - pluckX) * 3.0));
  // ── Idea 2: tension-modulation pitch glide ─────────────────────────
  // A large-amplitude string is stretched, so its pitch starts sharp and
  // glides down as the amplitude decays. With omega(t) = w0 (1 + g e^{-k t})
  // the phase integral is closed-form: w0 (t + g (1 - e^{-k t}) / k) - no state.
  let glideAge = pluckAge + 0.6 * (1.0 - pluckDecay) / pluckRate;
  // Struck string index (nearest string row) for sympathetic matching.
  let struckIdx = clamp(round((pluckY + 0.9) / 1.8 * strings - 0.5), 0.0, strings - 1.0);
  let struckOmega = 2.0 + struckIdx * 0.5;
  var simple = array<f32, 8>(0.5, 0.6666667, 0.75, 0.8, 1.25, 1.3333334, 1.5, 2.0);
  let swell = 1.0 - exp(-pluckAge * 6.0);

  var stringField = 0.0;
  var harmonicField = 0.0;
  var nodeField = 0.0;
  var pinField = 0.0;

  for (var s = 0u; s < u32(strings); s = s + 1u) {
    let fs = f32(s);
    let sy = -0.9 + (fs + 0.5) / strings * 1.8;
    let t01 = fs / max(strings - 1.0, 1.0);
    // Audio spectrum drive: each string's loudness tracks its band.
    let specAmp = 1.0 + bandWeight(t01, bass, mids, treble) * 0.55;
    // Pluck excitation: gaussian displacement centered on the struck string.
    let struck = exp(-sq((sy - pluckY) * 4.0));
    let ring = sin(p.x * tension * 8.0 - glideAge * (6.0 + fs * 0.7));
    // ── Idea 1: sympathetic resonance ───────────────────────────────
    // An unstruck string whose pitch sits on a simple ratio (2:1, 3:2, 4:3, ...)
    // of the struck string is driven through the bridge: it swells in and rings
    // faintly across the whole string, like an open piano string.
    let ratio = (2.0 + fs * 0.5) / struckOmega;
    var symMatch = 0.0;
    for (var qi = 0; qi < 8; qi = qi + 1) {
      let dq = (ratio - simple[qi]) / 0.05;
      symMatch = symMatch + exp(-dq * dq);
    }
    let symWide = exp(-sq((p.x - pluckX) * 0.45));
    let sympathy = pluckEnv * sat(symMatch) * (1.0 - struck) * swell * symWide * 0.55;
    let excite = pluckEnv * struck * pluckGauss * ring + sympathy * ring;
    let pluck = sin(p.x * tension * (1.0 + fs * 0.15) - time * (2.0 + fs * 0.5) * (1.0 + bass * 0.5));
    let damp = exp(-abs(p.x - wellPos.x * 0.5) * 2.0) * (0.5 + mids);
    let wave = sin((p.y - sy + shock * 0.15 + excite * 0.35) * tension * 15.0) * exp(-abs(p.y - sy) * tension * 3.0);
    let amp = (0.15 + damp + abs(excite) * 0.8) * resonance * (1.0 + bass * 0.3) * specAmp;
    let stringLine = abs(wave + pluck * amp);
    stringField = stringField + smoothstep(0.05, 0.0, stringLine) * (0.7 + fs * 0.05) * specAmp;

    // Harmonic rolloff brightens with tension (stiffer string = richer overtones).
    let rolloff = mix(0.68, 0.5, sat(tension / 5.0));
    for (var h = 1u; h < u32(harmonics); h = h + 1u) {
      let fh = f32(h);
      let harmY = sy + sin(fh * 1.618) * 0.15 + excite * 0.1;
      let harmWave = sin((p.y - harmY) * tension * 15.0 * fh) * exp(-abs(p.y - harmY) * tension * 5.0);
      let harmLine = abs(harmWave + pluck * amp * pow(rolloff, fh));
      harmonicField = harmonicField + smoothstep(0.03, 0.0, harmLine) * 0.3 * specAmp;
    }

    let nodeX = sin(fs * 2.7 + time * 0.3) * 0.5 + well.x * 0.5;
    let nodeDist = length(p - vec2<f32>(nodeX, sy));
    nodeField = nodeField + exp(-nodeDist * nodeDist * 80.0) * (0.5 + treble + pluckEnv * struck * 0.8);

    // ── Idea 3: standing-wave nodal pins ────────────────────────────
    // Zeros of sin(k x) with this string's own wavenumber k (the same
    // tension*(1+0.15 fs) the travelling term uses): the points the mode
    // never moves. Pins sit on the string row and pulse with the mids.
    let kStr = tension * (1.0 + fs * 0.15);
    let pinPhase = p.x * kStr / 3.14159265;
    let pinDx = (pinPhase - round(pinPhase)) * 3.14159265 / kStr;
    let pinDy = p.y - sy;
    pinField = pinField + exp(-(pinDx * pinDx + pinDy * pinDy) * 420.0) * (0.55 + mids * 1.2 + sympathy * 2.5);
  }

  // Treble sparkle on nodes
  let sparkle = step(0.88, hash21(uv * 150.0 + time * 10.0)) * treble * nodeField * 3.0;
  let depthSample = textureLoad(readDepthTexture, coord, 0).r;
  let ao = exp(-depthSample * 3.0);

  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.9, 0.55, 0.2) * stringField * resonance * (1.0 + bass * 0.15);
  color = color + vec3<f32>(0.25, 0.75, 0.95) * harmonicField * (1.0 + mids * 0.2);
  color = color + vec3<f32>(1.0, 0.95, 0.85) * nodeField * (0.5 + treble * 0.3);
  color = color + vec3<f32>(0.85, 0.95, 1.0) * pinField * 0.8;
  color = color + vec3<f32>(1.0, 0.9, 0.7) * sparkle;
  color = color + vec3<f32>(0.95, 0.8, 0.5) * pluckEnv * pluckGauss * 0.35;

  // Temporal accumulation with bass-reactive feedback; resonance sets sustain.
  let sustain = mix(0.90, 0.965, sat(resonance / 1.5));
  var accum = mix(color, prev.rgb * sustain, 0.03 + bass * 0.015);
  // Clamp the feedback loop pre-tint at ~1.2 (luma-echo-warp lesson).
  accum = min(accum, vec3<f32>(1.2));
  color = accum * (1.0 + lumaBoost) * (0.6 + 0.4 * ao);

  let presence = sat(stringField * 0.85 + harmonicField * 0.6 + nodeField * 0.9 + pinField * 0.3);
  let mouseProx = exp(-mDist * 2.0);
  let alpha = sat(0.08 + presence * 0.65 + mouseProx * 0.2 + bass * 0.12);
  let trailAge = prev.a * 0.96;
  let finalAlpha = max(alpha, trailAge * 0.6);

  let depth = sat(0.92 - stringField * 0.5 - nodeField * 0.3);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  var aOut = vec4<f32>(bass, harmonicField, nodeField, finalAlpha);
  // State texels persist the spring well (see the map at the top).
  if (gid.y == 0u && gid.x == 0u) { aOut = vec4<f32>(wellPos, wVel); }
  if (gid.y == 0u && gid.x == 1u) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
  textureStore(dataTextureA, coord, aOut);
}
