// ═══════════════════════════════════════════════════════════════════
//  Waveform Glitch
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: waveform-monitor trace of the source row under the cursor; beam-dwell phosphor brightness on the Lissajous; treble block glitch that slides whole quantisation cells
//  A packing: pre-ACES linear display RGB + semantic alpha; C read back as that linear colour for the phosphor trail mix (ACES on writeTexture only)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// 64-step Lissajous SDF (kept from HEAD), now evaluated in aspect-corrected scope space so the
// figure is not squashed on wide canvases. Returns (normalised distance-glow, beam speed at the
// nearest point) — the speed feeds the beam-dwell brightness (idea 2).
fn lissajous(scopeP: vec2<f32>, t: f32, freqX: f32, freqY: f32, phase: f32, thickness: f32) -> vec2<f32> {
  var minDist = 1.0;
  var speedAtMin = 1.0;
  let steps = 64.0;
  for (var i = 0.0; i < steps; i += 1.0) {
    let pt = i * TAU / steps;
    let lx = sin(freqX * pt + t);
    let ly = sin(freqY * pt + t + phase);
    let dist = length(scopeP - vec2<f32>(lx, ly) * 0.8);
    if (dist < minDist) {
      minDist = dist;
      // d/dpt of the beam position: how fast the spot is moving here.
      let vx = freqX * cos(freqX * pt + t);
      let vy = freqY * cos(freqY * pt + t + phase);
      speedAtMin = length(vec2<f32>(vx, vy)) / max(length(vec2<f32>(freqX, freqY)), 0.001);
    }
  }
  return vec2<f32>(smoothstep(thickness, thickness * 0.2, minDist), speedAtMin);
}

fn signalAliasing(uv: vec2<f32>, sampleRate: f32) -> vec2<f32> {
  return floor(uv * sampleRate) / sampleRate;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  // Direct pointer (HEAD's extraBuffer spring read re-zeroed state every frame; removed).
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let waveIntensity = u.zoom_params.x * (1.0 + bass * 0.8) * select(1.0, 1.3, held);
  let vhsIntensity = u.zoom_params.y * (1.0 + mids * 0.5);
  let aliasingFactor = mix(200.0, 20.0, u.zoom_params.z);
  let scopeIntensity = u.zoom_params.w;

  var rippleWarp = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      rippleWarp += smoothstep(0.14, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age * 0.85);
    }
  }

  let mousePull = (uv - mouse) * exp(-length((uv - mouse) * vec2<f32>(aspect, 1.0)) * 6.0) * 0.02 * select(0.0, 1.0, held);
  let sampleRate = aliasingFactor + treble * 50.0;
  var aliasedUV = signalAliasing(uv + mousePull, sampleRate);

  // IDEA 3 — block glitch (the z slider's promised name). Treble spikes slide whole quantisation
  // cells sideways by a per-cell hash; the cell row re-rolls 8x/s so blocks stutter rather than
  // smear. A sparse silent burst keeps the slider alive without audio.
  let cell = floor((uv + mousePull) * sampleRate);
  let cellTick = floor(time * 8.0);
  let cellRoll = hash21(vec2<f32>(cell.y, cellTick));
  let silentBurst = step(0.94, hash21(vec2<f32>(cellTick, cell.y * 0.37 + 3.1)));
  let glitchGate = max(smoothstep(0.35, 0.9, treble), silentBurst * 0.6) * step(0.5, cellRoll);
  let blockShift = (hash21(vec2<f32>(cell.x + cellTick, cell.y)) - 0.5) * glitchGate * u.zoom_params.z * 0.12;
  aliasedUV.x = clamp(aliasedUV.x + blockShift, 0.0, 1.0);

  // Wobble: accumulated phase — bass now offsets phase instead of scaling the rate (no jumps).
  let beatFreq = time + bass * 0.6;
  let waveX = sin(aliasedUV.y * 50.0 + beatFreq) * 0.05 * waveIntensity;
  let waveY = cos(aliasedUV.x * 40.0 - beatFreq * 0.8) * 0.03 * waveIntensity;
  let displacedUV = clamp(aliasedUV + vec2<f32>(waveX + rippleWarp * 0.03, waveY), vec2<f32>(0.0), vec2<f32>(1.0));

  let baseSample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(0.01 * vhsIntensity, 0.0), 0.0).r;
  let g = baseSample.g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(0.01 * vhsIntensity, 0.0), 0.0).b;
  var col = vec3<f32>(r, g, b);

  // Scope space: aspect-corrected, figure scaled to fit the shorter axis (floor fix).
  let scopeP = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0) / min(aspect, 1.0);

  let lissX = 3.0 + floor(mids * 2.0);
  let lissY = 2.0 + floor(bass * 2.0);
  let lissPhase = PI * 0.25 * treble;
  let liss = lissajous(scopeP, time * 2.0, lissX, lissY, lissPhase, 0.02 + bass * 0.02);
  // IDEA 2 — beam-dwell brightness: phosphor energy per unit length is 1/beam-speed, so slow
  // lobes burn bright and fast crossings go faint. Normalised so the mean is close to HEAD.
  let dwell = clamp(0.42 / (liss.y + 0.28), 0.45, 1.5);
  let lissPattern = liss.x * dwell;
  col += vec3<f32>(0.2, 1.0, 0.4) * lissPattern * scopeIntensity * 2.0;

  // IDEA 1 — waveform-monitor trace: plots the luma of the SOURCE row under the cursor Y as a
  // video waveform (x = column, y = luma). Per pixel we need only the luma at (uv.x, mouseY) and
  // its two horizontal neighbours to draw an anti-aliased, slope-aware line.
  let traceRow = mouse.y;
  let px = 1.0 / res.x;
  let l0 = luma(textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, traceRow), 0.0).rgb);
  let lm = luma(textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x - px, traceRow), 0.0).rgb);
  let lp = luma(textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x + px, traceRow), 0.0).rgb);
  let plotTop = 0.10;
  let plotSpan = 0.80;
  let traceY = (plotTop + plotSpan) - clamp(l0, 0.0, 1.0) * plotSpan;   // screen y grows downward
  let slopePx = (clamp(lm, 0.0, 1.0) - clamp(lp, 0.0, 1.0)) * plotSpan * res.y * 0.5;
  let distPx = abs(uv.y - traceY) * res.y / sqrt(1.0 + slopePx * slopePx);
  let traceCore = smoothstep(2.2, 0.0, distPx);
  let traceHalo = exp(-distPx * 0.35) * 0.18;
  // Faint cursor-row marker so the operator can see which line is being scanned.
  let rowMarker = smoothstep(1.5, 0.0, abs(uv.y - traceRow) * res.y) * 0.12;
  let waveformTrace = (traceCore + traceHalo) * (0.85 + treble * 0.3) + rowMarker;
  col += vec3<f32>(0.25, 1.0, 0.45) * waveformTrace * scopeIntensity * 1.6;

  let scanline = sin(uv.y * res.y * PI) * 0.2 + 0.8;
  let blanking = step(0.05, fract(time * 5.0 + uv.y * 2.0));
  col = col * scanline * mix(1.0, blanking, vhsIntensity * 0.5);

  // Three-band tint bars (HEAD read plasmaBuffer[1..8], which is never written).
  let bandIdx = min(u32(uv.x * 3.0), 2u);
  let bandLevel = select(select(treble, mids, bandIdx == 1u), bass, bandIdx == 0u);
  col += vec3<f32>(0.0, bandLevel * 0.08, bandLevel * 0.04) * scopeIntensity;

  // Phosphor trail: C holds last frame's pre-ACES linear colour (same packing as A).
  let prev = clamp(textureLoad(dataTextureC, pixel, 0), vec4<f32>(0.0), vec4<f32>(4.0));
  let persistence = mix(0.15, 0.55, u.zoom_params.z);
  let trail = mix(col, prev.rgb, persistence * (0.85 + bass * 0.1));
  col = mix(col, trail, 0.55 + bass * 0.15);

  let scopeGlow = lissPattern * scopeIntensity + waveformTrace * scopeIntensity * 0.6;
  let waveMag = abs(waveX) + abs(waveY) + scopeGlow;
  let alpha = clamp(baseSample.a * (1.0 - waveMag * 0.2) + waveMag * 0.35 + rippleWarp * 0.15, 0.0, 1.0);

  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  let display = acesToneMap(col * (0.95 + bass * 0.05));
  textureStore(writeTexture, pixel, vec4<f32>(display, alpha));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
