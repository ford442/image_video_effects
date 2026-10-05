// ═══════════════════════════════════════════════════════════════════
//  Neon Cursor Trace
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha,
//            temporal-persistence, spring-physics, gravity-well, click-burst,
//            phosphor-decay, electric-arc, multi-point-trail, particle-spawn,
//            velocity-smear, ripple-spark, depth-aware, aces-tone-map
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: arc forking above a spring-velocity threshold; white-hot beads cooling through the hue; overshoot spark burst when the spring passes the cursor
//  A packing: linear phosphor RGB + bassEnv alpha; (0,0) = (lagPos.xy, lagVel.xy); (1,0) = (arcPhase, 0, 0, sentinel -7)
// ═══════════════════════════════════════════════════════════════════
//  Electric bead chain from the cursor to a spring-lagged point, jittered by
//  chaos, decaying as phosphor. The spring state used to live in a per-pixel
//  extraBuffer slot that was overwritten from the CPU every frame (so the lag
//  point never moved); it now lives in two state texels of dataTextureA/C.
//  Every thread integrates the same spring from the same C state (so the
//  chain is identical across the frame); only the (0,0) and (1,0) threads
//  store the new state.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SENTINEL: f32 = -7.0;
const DT: f32 = 1.0 / 60.0;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn safeNormalize(v: vec2<f32>) -> vec2<f32> { return v / max(length(v), 1e-4); }

fn bass_env(prev: f32, bass: f32) -> f32 {
  let k = select(0.15, 0.8, bass > prev);
  return mix(prev, bass, k);
}

fn springDamp(targetPos: vec2<f32>, pos: vec2<f32>, vel: vec2<f32>, k: f32, damping: f32, dt: f32) -> vec4<f32> {
  let force = (targetPos - pos) * k;
  let newVel = (vel + force * dt) * (1.0 - damping);
  return vec4<f32>(pos + newVel * dt, newVel);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  let kick = safeNormalize(d) * strength / (dot(d, d) + 0.0001);
  // Cap the per-frame kick so a lag point sitting on the well cannot explode.
  return kick / max(1.0, length(kick) / 0.05);
}

fn gauss(d2: f32, s2: f32) -> f32 { return exp(-d2 / (2.0 * s2)); }

fn neonColor(hue: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3<f32>(hue * TAU, hue * TAU + 2.094, hue * TAU + 4.188));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let traceIntensity = u.zoom_params.x;
  let traceWidth = u.zoom_params.y * 0.12 + 0.005;
  // Stiffness: the saved slider role is unchanged; the ×36 scale makes the
  // kept springDamp underdamped at dt = 1/60 so the lag point overshoots.
  let springK = (u.zoom_params.z * 5.0 + 0.2) * 36.0;
  let chaos = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // History: linear phosphor RGB + bassEnv alpha. Guard against NaN/garbage
  // left in C by a previous shader.
  let prevRaw = textureLoad(dataTextureC, pixel, 0);
  let prevOut = clamp(select(vec4<f32>(0.0), prevRaw, prevRaw == prevRaw), vec4<f32>(0.0), vec4<f32>(8.0));
  let bassEnv = bass_env(clamp(prevOut.a, 0.0, 1.0), bass);
  let midsMorph = 1.0 + mids * 0.5;
  let trebleSpark = clamp(treble * 2.0, 0.0, 1.0);

  // ── Spring state texels (replaces the dead per-pixel extraBuffer slot) ──
  let s0Raw = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let s1Raw = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let s0 = select(vec4<f32>(0.0), s0Raw, s0Raw == s0Raw);
  let s1 = select(vec4<f32>(0.0), s1Raw, s1Raw == s1Raw);
  let stateValid = (s1.w == SENTINEL) && (s0.w == s0.w);
  var lagPos = select(mousePos, clamp(s0.xy, vec2<f32>(-0.5), vec2<f32>(1.5)), stateValid);
  var lagVel = select(vec2<f32>(0.0), clamp(s0.zw, vec2<f32>(-20.0), vec2<f32>(20.0)), stateValid);
  var arcPhase = select(0.0, s1.x, stateValid);

  let wellStrength = mouseDown * bassEnv * 0.0008;
  lagVel = lagVel + gravityWell(lagPos, mousePos, wellStrength);
  // Idea 3 (overshoot sparks): sample the overshoot BEFORE integrating so the
  // burst fires on the frame the lag point passes the cursor.
  let toMouse = mousePos - lagPos;
  let overshoot = clamp(-dot(lagVel, safeNormalize(toMouse)) * 0.6, 0.0, 1.0)
                * smoothstep(0.0, 0.02, length(toMouse));
  let spring = springDamp(mousePos, lagPos, lagVel, springK, 0.08, DT);
  lagPos = spring.xy;
  lagVel = spring.zw;
  let velMag = length(lagVel);
  arcPhase = (arcPhase + (velMag * 8.0 + bassEnv * 2.0) * DT * midsMorph) % 1000.0;

  let stretchDir = select(vec2<f32>(0.0), lagVel / velMag, velMag > 0.001);
  let chainPerp = vec2<f32>(-stretchDir.y, stretchDir.x);

  // Idea 1 (arc forking): above a spring-velocity threshold a second branch
  // leaves the cursor with opposite jitter and rejoins at the lag point.
  let forkAmount = smoothstep(0.5, 1.4, velMag);
  // Idea 2 (cooling afterimage): the chain is hottest at the cursor end and
  // when the spring is moving fast; hot beads are stored white.
  let heat = clamp(0.25 + velMag * 0.35 + bassEnv * 0.4, 0.0, 1.0);

  var glow = vec3<f32>(0.0);
  var accum = 0.0;
  let segments = 12;

  for (var i: i32 = 0; i <= segments; i = i + 1) {
    let t = f32(i) / f32(segments);
    let n = valueNoise(vec2<f32>(t * 13.0, arcPhase)) - 0.5;
    let n2 = valueNoise(vec2<f32>(t * 17.0 + 50.0, arcPhase * 1.3)) - 0.5;
    let jitter = vec2<f32>(n, n2) * chaos * 0.24 * t * (1.0 - t) * (1.0 + trebleSpark);
    let well = gravityWell(mix(mousePos, lagPos, t), mousePos, wellStrength * 0.5);
    let velStretch = stretchDir * velMag * t * (1.0 - t) * chaos * 0.6;
    let spine = mix(mousePos, lagPos, t);
    let trailPoint = spine + jitter + velStretch + well;

    let dVec = uv - trailPoint;
    let d2 = dot(dVec, dVec);
    let w = traceWidth * (0.35 + 0.65 * t);
    let falloff = gauss(d2, w * w);

    let hue = fract(time * 0.07 * midsMorph + t * 0.2 + bassEnv * 0.25 + arcPhase * 0.015);
    let brightness = 1.0 + mids * 0.5 * sin(t * TAU + time * 3.0);
    // Idea 2: white-hot core on the bead; the wide skirt keeps the neon hue.
    let core = falloff * falloff * heat * (1.0 - t * 0.6);
    let beadColor = mix(neonColor(hue), vec3<f32>(1.0), core);

    accum = accum + falloff;
    glow = glow + beadColor * falloff * brightness;

    // Idea 1: the fork branch — second noise seed, opposite jitter sign, bulged
    // to the other side of the spine so the two arcs visibly separate.
    if (forkAmount > 0.001) {
      let fn1 = valueNoise(vec2<f32>(t * 11.0 + 200.0, arcPhase * 0.9 + 7.0)) - 0.5;
      let fn2 = valueNoise(vec2<f32>(t * 19.0 + 250.0, arcPhase * 1.1 + 3.0)) - 0.5;
      let forkJitter = -vec2<f32>(fn1, fn2) * chaos * 0.24 * t * (1.0 - t) * (1.0 + trebleSpark);
      let bulge = chainPerp * sin(t * PI) * (0.03 + chaos * 0.03) * forkAmount;
      let forkPoint = spine - velStretch * 0.5 + forkJitter + bulge + well;
      let fVec = uv - forkPoint;
      let fFalloff = gauss(dot(fVec, fVec), w * w * 0.6);
      let fHue = fract(hue + 0.08);
      let fCore = fFalloff * fFalloff * heat * (1.0 - t * 0.6);
      let fColor = mix(neonColor(fHue), vec3<f32>(1.0), fCore);
      let fWeight = 0.6 * forkAmount;
      accum = accum + fFalloff * fWeight;
      glow = glow + fColor * fFalloff * brightness * fWeight;
    }
  }

  let rippleCount = min(u32(u.config.y), 50u);
  for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 1.5) {
      let rd = distance(uv, ripple.xy);
      let rw = traceWidth * (1.0 + elapsed * 2.0);
      let rFalloff = gauss(rd * rd, rw * rw) * (1.0 - elapsed * 0.66);
      let rHue = fract(ripple.z * 0.13 + elapsed * 0.4 + bassEnv * 0.1);
      glow = glow + neonColor(rHue) * rFalloff * traceIntensity * 0.6;
      accum = accum + rFalloff;
    }
  }

  let clickPulse = mouseDown * bassEnv;
  var particleGlow = vec3<f32>(0.0);
  if (clickPulse > 0.02) {
    for (var i: i32 = 0; i < 7; i = i + 1) {
      let seed = vec2<f32>(f32(i), fract(time));
      let ang = hash21(seed) * TAU;
      let rad = hash21(seed + vec2<f32>(1.0, 0.0)) * traceWidth * 4.5 * (1.0 + bassEnv * 3.0);
      let pPos = mousePos + vec2<f32>(cos(ang), sin(ang)) * rad;
      let pd = distance(uv, pPos);
      let pFalloff = exp(-pd * pd / (traceWidth * traceWidth * 0.18));
      let pHue = fract(f32(i) / 7.0 + time * 0.1 + bassEnv);
      particleGlow = particleGlow + neonColor(pHue) * pFalloff * clickPulse;
    }
  }

  if (trebleSpark > 0.15) {
    for (var i: i32 = 0; i < 5; i = i + 1) {
      let seed = vec2<f32>(f32(i) + 100.0, fract(time));
      let ang = hash21(seed) * TAU;
      let rad = hash21(seed + vec2<f32>(1.0, 0.0)) * traceWidth * 3.0 * (1.0 + trebleSpark);
      let pPos = mix(mousePos, lagPos, 0.5) + vec2<f32>(cos(ang), sin(ang)) * rad;
      let pd = distance(uv, pPos);
      let pFalloff = exp(-pd * pd / (traceWidth * traceWidth * 0.08));
      let pHue = fract(f32(i) / 5.0 + time * 0.2 + treble);
      particleGlow = particleGlow + neonColor(pHue) * pFalloff * trebleSpark * 0.5;
    }
  }

  // Idea 3 (overshoot sparks): when the lag point has passed the cursor
  // (velocity points away from it) a burst of white-hot sparks flies out of
  // the lag point along the overshoot direction, fanned ±35°.
  if (overshoot > 0.02) {
    let fly = safeNormalize(lagVel);
    for (var i: i32 = 0; i < 6; i = i + 1) {
      let seed = vec2<f32>(f32(i) + 300.0, floor(time * 20.0) / 20.0);
      let spread = (hash21(seed) - 0.5) * 1.2;
      let dirS = vec2<f32>(fly.x * cos(spread) - fly.y * sin(spread), fly.x * sin(spread) + fly.y * cos(spread));
      let rad = (0.2 + hash21(seed + vec2<f32>(1.0, 0.0))) * traceWidth * 5.0 * overshoot;
      let pPos = lagPos + dirS * rad;
      let pd = distance(uv, pPos);
      let pFalloff = exp(-pd * pd / (traceWidth * traceWidth * 0.06));
      let pHue = fract(f32(i) / 6.0 + arcPhase * 0.05);
      let sparkColor = mix(neonColor(pHue), vec3<f32>(1.0), 0.6 * overshoot);
      particleGlow = particleGlow + sparkColor * pFalloff * overshoot * 0.9;
    }
  }

  let rDecay = 0.88 + 0.1 * sin(time * 1.3);
  let gDecay = 0.86 + 0.1 * sin(time * 1.9 + 2.0);
  let bDecay = 0.84 + 0.1 * sin(time * 2.7 + 4.0);

  let baseVideo = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let baseLuma = dot(baseVideo.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = 1.0 + baseLuma * 0.3;

  let audioIntensity = traceIntensity * (1.0 + bassEnv * 0.5);

  // Idea 2 (cooling): the stored phosphor decays per channel (white → warm →
  // red ember) and each frame slides 8% toward the trail hue of its own
  // luminance, so a white-hot bead cools through the neon hue as it fades.
  var cooled = prevOut.rgb * vec3<f32>(rDecay, gDecay, bDecay);
  let coolHue = fract(time * 0.07 * midsMorph + bassEnv * 0.25 + arcPhase * 0.015 + 0.3);
  cooled = mix(cooled, neonColor(coolHue) * luma(cooled) * 1.15, 0.08);

  var phosphor = cooled + glow * audioIntensity * 0.2 * lumaBoost + particleGlow;
  phosphor = clamp(phosphor, vec3<f32>(0.0), vec3<f32>(8.0));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthMix = max(clamp(depth * 2.5, 0.0, 1.0), 0.5);
  var outRGB = mix(baseVideo.rgb * 0.15, phosphor, depthMix);

  let caStr = 0.003 * (1.0 + bassEnv) + depth * 0.001;
  let dir = safeNormalize(uv - vec2<f32>(0.5));
  outRGB = vec3<f32>(
    outRGB.r + dir.x * caStr,
    outRGB.g,
    outRGB.b - dir.y * caStr * 0.5
  );

  // Single ACES on display only; A keeps the linear phosphor.
  outRGB = acesToneMap(clamp(outRGB * (0.9 + mids * 0.2), vec3<f32>(0.0), vec3<f32>(16.0)));
  let alpha = clamp(luma(outRGB) * 1.5 * (0.5 + depthMix * 0.5), 0.15, 0.95);

  textureStore(writeTexture, pixel, vec4<f32>(outRGB, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

  if (pixel.x == 0 && pixel.y == 0) {
    textureStore(dataTextureA, pixel, vec4<f32>(lagPos, lagVel));
  } else if (pixel.x == 1 && pixel.y == 0) {
    textureStore(dataTextureA, pixel, vec4<f32>(arcPhase, 0.0, 0.0, SENTINEL));
  } else {
    textureStore(dataTextureA, pixel, vec4<f32>(phosphor, bassEnv));
  }
}
