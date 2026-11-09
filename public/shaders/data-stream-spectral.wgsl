// ═══════════════════════════════════════════════════════════════════
//  Data Stream Spectral — Batch 67
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: Schmitt-trigger stall lock (§12.2B: per-strip latch with hysteresis, stutter-step scroll + full digital tint while locked); dropout bursts (§12.2B: scrolling data blanked behind a white leading edge, exponential tail, treble raises the odds)
//  A packing: A.rgb = ACES display RGB; A.a = per-strip lock latch (Schmitt state, read back from exact C.a; HEAD wrote display alpha there and never read it)
//  Strip flow, head packets, capped click wakes, ACES + semantic alpha.
//  Spectral tilt across strips rides plasmaBuffer[0] (bass left, mids centre, treble right).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 { return Fp128(x, 0.0); }
fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  return Fp128(t, e - (t - s));
}
fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  return Fp128(t, e - (t - p));
}
fn fp128_val(x: Fp128) -> f32 { return x.base + x.mant; }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Schmitt thresholds for the stall lock (hysteresis band 0.52..0.74).
const LOCK_HI: f32 = 0.74;
const LOCK_LO: f32 = 0.52;
const STALL_HZ: f32 = 6.0;       // stutter-step rate of a locked strip
const BURST_EPOCH: f32 = 1.25;   // seconds per dropout epoch (staggered per strip)

fn hash11(x: f32) -> f32 {
  return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn vnoise1(x: f32) -> f32 {
  let i = floor(x);
  let f = fract(x);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(hash11(i), hash11(i + 1.0), w);
}

fn strip_head_packet(uv: vec2<f32>, stripIdx: f32, time: f32, speed: f32) -> f32 {
  let head = fract(time * speed * (0.4 + fract(sin(stripIdx * 12.9898) * 43758.5453) * 0.6));
  return pow(max(0.0, 1.0 - abs(uv.y - head) * 20.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 0.001);
  let held = u.zoom_config.w > 0.5;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Audio must NOT enter the time-multiplied scroll phase (tEff * flowSpeed): any audio change would
  // teleport every strip by time * delta (HEAD did this with bass; ~10 s into a session real music strobed
  // the strips instead of scrolling them). Audio drives brightness, alpha, the lock drive and dropout odds.
  let speed = max(u.zoom_params.x, 0.001);
  let density = max(u.zoom_params.y, 0.001);
  let turbulence = clamp(u.zoom_params.z * select(1.0, 1.4, held), 0.0, 1.0);
  let glow = clamp(u.zoom_params.w, 0.0, 1.0);

  // R1: the old extraBuffer[133..138] spring never persisted (the scratch buffer is
  // re-uploaded zeroed every frame), so the cursor was always the raw cursor. Say so.
  let mousePos = u.zoom_config.yz;

  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let interact = smoothstep(0.3, 0.0, mouseDist) * turbulence;

  let numStrips = 20.0 + density * 100.0;
  let stripIdx = floor(uv.x * numStrips);
  let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

  // R2: plasmaBuffer[1..8] is never uploaded (HEAD's per-strip "FFT" read 0). Live
  // replacement: a 3-band tilt across the strips — bass left, mids centre, treble right.
  let tilt = (stripIdx + 0.5) / numStrips;
  let wBass = max(1.0 - 2.0 * tilt, 0.0);
  let wTreb = max(2.0 * tilt - 1.0, 0.0);
  let fftStrip = wBass * bass + (1.0 - wBass - wTreb) * mids + wTreb * treble;

  // ── Idea 1: Schmitt-trigger stall lock (§12.2B) ──────────────────
  // Each strip has a slow drive (value noise, kicked by bass). It latches ON above
  // LOCK_HI and releases only below LOCK_LO; the latch lives in exact C.a (A.a last
  // frame), so a stalled stream stays stalled instead of flickering per frame.
  let prevCell = textureLoad(dataTextureC, pixel, 0);
  let drive = vnoise1(stripIdx * 13.1 + time * 0.45) + bass * 0.15;
  var lock = step(0.5, prevCell.a);
  lock = select(lock, 1.0, drive > LOCK_HI);
  lock = select(lock, 0.0, drive < LOCK_LO);
  // Locked strips stutter-step their scroll clock and hold full digital tint.
  let tEff = select(time, floor(time * STALL_HZ) / STALL_HZ, lock > 0.5);
  let glowEff = max(glow, lock * 0.9);
  let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.5;
  let packet = strip_head_packet(uv, stripIdx, tEff, flowSpeed);

  var clickWake = 0.0;
  var clickGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.6, age));
    let clickVec = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
    let clickDist = length(clickVec);
    let ring = 1.0 - smoothstep(0.018, 0.065, abs(clickDist - safeAge * 0.34));
    let wave = ring * exp(-safeAge * 1.7) * live;
    clickWake += wave * sin(uv.y * 24.0 + rp.x * 19.0 + safeAge * 8.0);
    clickGlow = max(clickGlow, wave);
  }

  let xOffset = interact * sin(uv.y * 10.0 + time * 5.0) * 0.05 + clickWake * turbulence * 0.045;
  let flowPhase = fp128_sum(fp128_mul(fp128(tEff), fp128(flowSpeed)), fp128(-uv.y));
  var sampleUV = uv;
  sampleUV.x = sampleUV.x + xOffset;
  sampleUV.y = fract(fp128_val(flowPhase));

  if (rand > 0.8) {
    sampleUV.y = sampleUV.y + sin(time * 10.0) * 0.01;
  }

  let band = u32(stripIdx) % 4u;
  var color = vec3<f32>(0.0);
  var spectralEnergy = 0.0;

  if (band == 0u) {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 8; i++) {
      let angle = f32(i) * 6.283185307 / 8.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 4.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 8.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(1.0, 0.8, 0.6);
  } else if (band == 1u) {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 6; i++) {
      let angle = f32(i) * 6.283185307 / 6.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 2.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 6.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(0.6, 1.0, 0.7);
  } else if (band == 2u) {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 4; i++) {
      let angle = f32(i) * 6.283185307 / 4.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 1.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 4.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(0.5, 0.7, 1.0);
  } else {
    color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let blurred = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(1.0, 0.0) / res, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = color - blurred * 0.5;
    spectralEnergy = length(color);
    color = color * vec3<f32>(1.0, 1.0, 1.0);
  }

  spectralEnergy = spectralEnergy * (1.0 + fftStrip * 0.35 + mids * 0.15);

  // ── Idea 2: dropout bursts (§12.2B) ──────────────────────────────
  // Per strip and epoch a hash may fire a burst (odds rise with treble). In the strip's
  // own image-space coordinate the data is blanked behind a leading edge and recovers
  // exponentially, so the burst scrolls with the content. Smooth in/out per epoch.
  let epochPh = time / BURST_EPOCH + rand * 7.0;
  let epoch = floor(epochPh);
  let epochEnv = smoothstep(0.0, 0.15, fract(epochPh)) * (1.0 - smoothstep(0.7, 1.0, fract(epochPh)));
  let hBurst = hash21(vec2<f32>(stripIdx * 1.7 + 3.1, epoch));
  let fire = step(1.0 - (0.07 + treble * 0.35), hBurst) * epochEnv;
  let burstD = fract(sampleUV.y - fract(hBurst * 91.7));
  let dropTail = fire * exp(-burstD * 12.0);
  let dropEdge = fire * exp(-burstD * 140.0);
  color = color * (1.0 - 0.92 * dropTail);
  spectralEnergy = spectralEnergy * (1.0 - 0.8 * dropTail);

  let blockY = floor(uv.y * 50.0);
  let noise = fract(sin(dot(vec2<f32>(stripIdx, blockY), vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let bright = step(0.98, noise * (sin(time * 2.0 + stripIdx) * 0.5 + 0.5));

  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let digitalColor = vec3<f32>(0.0, lum * 1.5, lum * 0.2);
  var outputColor = mix(color, digitalColor, glowEff);
  outputColor = outputColor + vec3<f32>(0.0, bright * glowEff, 0.0);
  outputColor += vec3<f32>(0.55, 0.8, 0.9) * dropEdge * (0.4 + 0.6 * glowEff);
  outputColor += vec3<f32>(0.15, 0.35, 0.5) * packet * (0.2 + treble * 0.3);
  outputColor += vec3<f32>(0.1, 0.25, 0.4) * clickGlow * 0.35;

  outputColor = mix(outputColor, prevCell.rgb * 0.9, packet * 0.1);

  outputColor = acesToneMap(max(outputColor, vec3<f32>(0.0)));

  let alpha = clamp(spectralEnergy * mix(0.45, 0.88, glowEff) + packet * 0.08 + clickGlow * 0.1, 0.06, 0.98);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(outputColor, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(outputColor, lock));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
