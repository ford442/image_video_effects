// ═══════════════════════════════════════════════════════════════════
//  Temporal Frequency Decomposition
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-02 (Algorithmist — swarm b26), 2026-09-21, 2026-11-09
//  Ideas: Hann-windowed DFT; DFT phase -> glow hue; DC notch; second-harmonic voice; treble shimmer bands
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a hardcoded 8
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Discrete temporal Fourier analysis across the 8-frame history ring.
//  Each pixel accumulates a weighted sum where weights follow
//  sin/cos at the target temporal frequency. Static pixels cancel to
//  zero; pixels flickering or oscillating near the target frequency
//  produce large magnitude responses and glow brightly.
//  The result is overlaid on the current frame.
//
//  Interaction (the 'mouse-driven' tag is now honestly wired):
//    - Analysis lens: inside a soft disc around the cursor the
//      frequency response is sharpened and the glow widened.
//    - Click tuning-fork pings: each click injects a decaying
//      oscillation at the target frequency into the DFT accumulators.
//    - Treble shimmer bands: 8 vertical bands flicker with treble.
//
//  zoom_params layout:
//    x = target frequency (0→0.05 cycles/frame, 1→0.5, default 0.25→~0.18)
//    y = glow brightness  (0→dim, 1→blazing, default 0.6)
//    z = glow color hue   (0→red/orange, 0.5→cyan, 1→red again, default 0.17→yellow)
//    w = base blend       (0→glow only, 1→base+glow, default 0.8)
//
//  extraBuffer: only [4] = historyHead is read. Audio = plasmaBuffer[0].
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=freq, y=glowBright, z=glowHue, w=baseBlend
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

const TAU: f32 = 6.28318530718;
const MAX_FRAMES: u32 = 8u;  // current + up to 7 history layers
const LENS_RADIUS: f32 = 0.35;     // aspect-corrected lens radius
const PING_RADIUS: f32 = 0.2;      // aspect-corrected click ping radius

// Simple hue→RGB conversion
fn hue2rgb(h: f32) -> vec3<f32> {
  let h6 = fract(h) * 6.0;
  let r  = clamp(abs(h6 - 3.0) - 1.0, 0.0, 1.0);
  let g  = clamp(2.0 - abs(h6 - 2.0), 0.0, 1.0);
  let b  = clamp(2.0 - abs(h6 - 4.0), 0.0, 1.0);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv     = (vec2<f32>(global_id.xy) + 0.5) / res;
  let aspect = res.x / res.y;
  let time   = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Parameters; bass boosts glow brightness, mids rotate hue for spectral color
  let freq       = 0.05 + u.zoom_params.x * 0.45;
  let glowBright = u.zoom_params.y * 2.0 * (1.0 + bass * 0.6);
  let glowHue    = fract(u.zoom_params.z + mids * 0.15);
  let baseBlend  = u.zoom_params.w;

  // Rescue: the extraBuffer[133..137] spring was zeroed every frame by
  // the engine upload, so it was a no-op — the lens follows the raw cursor.
  let lensPos = u.zoom_config.yz;
  let treble = plasmaBuffer[0].z;

  // Aspect-corrected lens mask (~0.35 radius, soft edge)
  let lensVec  = (uv - lensPos) * vec2<f32>(aspect, 1.0);
  let lensMask = 1.0 - smoothstep(0.0, LENS_RADIUS, length(lensVec));

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Floor fix: the ring holds 8, 4 or 1 layers (VRAM probe) and the
  // renderer wraps its head at that count. HEAD assumed 8, so on a 4-layer
  // device half the DFT samples came from the wrong frames.
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let frames    = min(histDepth, MAX_FRAMES);
  let fN        = f32(frames);

  // ── Idea 1: Hann-windowed DFT ─────────────────────────────────────
  // An unwindowed 8-sample DFT leaks badly: its sidelobes are only ~13 dB
  // down, so a pixel changing at almost ANY rate — or just sitting bright
  // and still — lights up at the selected frequency, and the selector
  // barely selects. A Hann window pushes the sidelobes to ~31 dB. It is
  // normalised by the window's own sum so a pure tone keeps HEAD's scale.
  // Real part (cosine weights) and imaginary part (sine weights).
  // ── New idea: DC notch ────────────────────────────────────────────
  // Pass 1 gathers the windowed temporal mean; pass 2 runs the DFT on
  // (sample - mean). A static pixel now cancels EXACTLY instead of leaking
  // through the window sidelobes — and on a 1-layer ring (VRAM floor) the
  // old single-sample "DFT" was just the frame itself, so the whole picture
  // glowed (yellow wash). With the notch it correctly reads as silence.
  let w0 = 0.5 - 0.5 * cos(TAU * 0.5 / fN);
  var samples: array<vec3<f32>, 8>;
  var weights: array<f32, 8>;
  samples[0] = current.rgb;
  weights[0] = w0;
  var meanAcc = current.rgb * w0;
  var sumW = w0;
  for (var age: u32 = 1u; age < frames; age = age + 1u) {
    let layer = (historyHead + histDepth - age) % histDepth;
    let hist  = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let w     = 0.5 - 0.5 * cos(TAU * (f32(age) + 0.5) / fN);
    samples[age] = hist.rgb;
    weights[age] = w;
    meanAcc += hist.rgb * w;
    sumW += w;
  }
  let dcMean = meanAcc / max(sumW, 1e-4);

  var realAcc = vec3<f32>(0.0);
  var imagAcc = vec3<f32>(0.0);
  // ── New idea: second-harmonic voice (2 × freq bin, same samples) ──
  var real2 = vec3<f32>(0.0);
  var imag2 = vec3<f32>(0.0);
  for (var age: u32 = 0u; age < frames; age = age + 1u) {
    let t = f32(age);
    let v = (samples[age] - dcMean) * weights[age];
    realAcc += v * cos(TAU * freq * t);
    imagAcc += v * sin(TAU * freq * t);
    real2   += v * cos(TAU * freq * 2.0 * t);
    imag2   += v * sin(TAU * freq * 2.0 * t);
  }
  // Pings were tuned against a /8 normalisation; keep their brightness.
  let pingScale = sumW / fN;

  // ── Click tuning-fork pings ──────────────────────────────────────
  // Each live ripple injects a decaying oscillation at the target
  // frequency into the DFT accumulators, lighting the click point up
  // at `freq` even when the underlying scene is perfectly static.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple    = u.ripples[i];
    let rippleAge = time - ripple.z;
    if (rippleAge < 0.0 || rippleAge > 4.0) { continue; }
    let pingVec   = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
    let pingMask  = 1.0 - smoothstep(0.0, PING_RADIUS, length(pingVec));
    let decay     = exp(-rippleAge * 1.5);
    let ageFrames = rippleAge * 60.0;          // seconds → frames
    realAcc += vec3<f32>(cos(TAU * freq * ageFrames)) * pingMask * decay * pingScale;
    imagAcc += vec3<f32>(sin(TAU * freq * ageFrames)) * pingMask * decay * pingScale;
  }

  // Frequency magnitude (normalised by sample count)
  let magnitude = sqrt(realAcc * realAcc + imagAcc * imagAcc) / max(sumW, 1e-4);

  // Scalar energy level for glow brightness
  let energy = (magnitude.r + magnitude.g + magnitude.b) / 3.0;

  // ── Lens focus: sharpen response, widen glow inside the lens ─────
  var energyFocused = energy * (1.0 + lensMask * 0.8);
  energyFocused = pow(clamp(energyFocused, 0.0, 4.0), 1.0 - lensMask * 0.25);

  // ── New idea: treble shimmer bands ───────────────────────────────
  // Rescue: HEAD read plasmaBuffer[1..8] per band, but only index 0 is
  // ever uploaded, so the band voices were dead. Each of 8 vertical bands
  // now flickers on its own hashed clock, gated by real treble.
  let band       = floor(uv.x * 8.0);
  let flick      = 0.5 + 0.5 * sin(time * (9.0 + band * 3.7) + band * 2.3);
  let voice      = treble * flick * 0.5;
  let voiceBoost = 1.0 + bass * 0.6 + voice;

  // ── Idea 2: DFT phase -> glow hue ─────────────────────────────────
  // HEAD computed the phase and threw it away. Rotating the glow hue by it
  // (up to a quarter turn either side of the user's hue) makes regions that
  // oscillate in sync share a colour, and a travelling wave shows up as a
  // hue sweep across the frame. Where the magnitude is tiny the phase is
  // noise, so the rotation fades out with energy.
  let lumaW   = vec3<f32>(0.2126, 0.7152, 0.0722);
  let phase   = atan2(dot(imagAcc, lumaW), dot(realAcc, lumaW)) / TAU;   // -0.5..0.5
  let phaseHue = fract(glowHue + phase * 0.5 * smoothstep(0.01, 0.06, energy));

  // Harmonic share: energy in the 2× bin pushes the glow toward the
  // complementary hue — hard strobes (rich in harmonics) read magenta/blue
  // against smooth sine motion's base hue.
  let mag2      = sqrt(real2 * real2 + imag2 * imag2) / max(sumW, 1e-4);
  let energy2   = (mag2.r + mag2.g + mag2.b) / 3.0;
  let harmShare = clamp(energy2 / max(energy + energy2, 1e-4), 0.0, 1.0);
  let hueCol    = mix(hue2rgb(phaseHue), hue2rgb(phaseHue + 0.5), harmShare * 0.8);
  let glowColor = hueCol * (energyFocused + energy2 * 0.6) * glowBright * voiceBoost;

  // Composite: base + glow
  let base   = current.rgb * baseBlend;
  let output = base + glowColor;
  let alpha = clamp(energy * 2.5 + baseBlend * 0.3 + bass * 0.2, 0.0, 1.0);
  let finalOut = vec4<f32>(output, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
