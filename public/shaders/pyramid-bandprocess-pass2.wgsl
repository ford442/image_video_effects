// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 2: Laplacian Band Processing
//  Category: image
//  Features: multi-pass-2, laplacian, audio-reactive, frequency-domain, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-18
//  Ideas: anti-halo envelope; edge-directed chroma fringe
//  A packing: does not write A or B. C is the previous blur. Display is writeTexture.
// ═══════════════════════════════════════════════════════════════════════════
//  This pass extracts the Laplacian (high-frequency residual) by computing
//    highFreq = original − prev_frame_blur
//  where prev_frame_blur is the Gaussian blur written by pass 1 in the previous
//  frame and propagated through dataTexB → dataTexC by the post-slot copy.
//
//  Three frequency bands receive independent creative processing:
//    L0 high-freq  → edge detection + neon saturation + chromatic glow
//    L1 mid-freq   → audio-bass hue rotation (plasmaBuffer[0].x)
//    L2 low-freq   → slow LFO colour breathing (sin-driven hue + saturation)
//
//  The processed result is written to writeTexture only. It does not write
//  dataTextureA: A would win the feedback copy and replace pass 1's blur.
//
//  Uniforms:
//    u.zoom_params.x = high-frequency amplitude  (0–2, default 0.7)
//    u.zoom_params.y = mid-frequency amplitude   (0–2, default 0.5)
//    u.zoom_params.z = low-frequency amplitude   (0–2, default 0.3)
//    u.zoom_params.w = ROI radius                (used only in pass 3)
//  Audio (via plasmaBuffer):
//    plasmaBuffer[0].x = bass   → drives mid-freq hue rotation
//    plasmaBuffer[0].y = mids   → modulates high-freq edge brightness
//    plasmaBuffer[0].z = treble → sharpens edge neon
// ═══════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=HighFreqAmp, y=MidFreqAmp, z=LowFreqAmp, w=ROIRadius

// ─── Colour helpers ───────────────────────────────────────────────────────────

fn rgb2hsl(c: vec3<f32>) -> vec3<f32> {
  let maxC = max(c.r, max(c.g, c.b));
  let minC = min(c.r, min(c.g, c.b));
  let l = (maxC + minC) * 0.5;
  let delta = maxC - minC;
  if (delta < 0.001) { return vec3<f32>(0.0, 0.0, l); }
  let s = select(delta / (2.0 - maxC - minC), delta / (maxC + minC), l < 0.5);
  var h: f32;
  if (maxC == c.r) {
    h = (c.g - c.b) / delta + select(6.0, 0.0, c.g >= c.b);
  } else if (maxC == c.g) {
    h = (c.b - c.r) / delta + 2.0;
  } else {
    h = (c.r - c.g) / delta + 4.0;
  }
  return vec3<f32>(h / 6.0, s, l);
}

fn hue2rgb(p: f32, q: f32, t_: f32) -> f32 {
  var t = t_;
  if (t < 0.0) { t = t + 1.0; }
  if (t > 1.0) { t = t - 1.0; }
  if (t < 1.0/6.0) { return p + (q - p) * 6.0 * t; }
  if (t < 0.5)     { return q; }
  if (t < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t) * 6.0; }
  return p;
}

fn hsl2rgb(hsl: vec3<f32>) -> vec3<f32> {
  if (hsl.y < 0.001) { return vec3<f32>(hsl.z); }
  let q = select(hsl.z * (1.0 + hsl.y), hsl.z + hsl.y - hsl.z * hsl.y, hsl.z < 0.5);
  let p = 2.0 * hsl.z - q;
  return vec3<f32>(
    hue2rgb(p, q, hsl.x + 1.0/3.0),
    hue2rgb(p, q, hsl.x),
    hue2rgb(p, q, hsl.x - 1.0/3.0)
  );
}

// Rotate hue by `shift` (0–1 range wraps back to itself).
fn rotateHue(rgb: vec3<f32>, shift: f32) -> vec3<f32> {
  var hsl = rgb2hsl(rgb);
  hsl.x = fract(hsl.x + shift);
  return hsl2rgb(hsl);
}

// Boost saturation by `factor` (1.0 = no change).
fn saturate(rgb: vec3<f32>, factor: f32) -> vec3<f32> {
  var hsl = rgb2hsl(rgb);
  hsl.y = clamp(hsl.y * factor, 0.0, 1.0);
  return hsl2rgb(hsl);
}

// Neon palette: map a magnitude 0–1 to a vivid HSV-style colour.
fn neonPalette(t: f32) -> vec3<f32> {
  // Cycling through cyan → magenta → yellow at high saturation.
  let hue = fract(t * 1.5 + 0.55);
  return hsl2rgb(vec3<f32>(hue, 1.0, 0.6));
}

// ─── Band extraction helpers ──────────────────────────────────────────────────

// High-frequency residual: difference between original and Gaussian blur.
// Returns signed residual per channel (can be negative).
fn highFreq(orig: vec3<f32>, blur: vec3<f32>) -> vec3<f32> {
  return orig - blur;
}

// Magnitude of the high-frequency residual (edge strength 0–∞).
fn edgeMag(hf: vec3<f32>) -> f32 {
  return length(hf);
}

// ─── Per-band creative processing ─────────────────────────────────────────────

// L0 — High-frequency band: edge neon
// Amplifies edges and maps their magnitude to a neon colour palette.
// treble modulates sharpness (more treble → harder edge threshold).
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn processHighFreq(orig: vec3<f32>, hf: vec3<f32>, amp: f32, treble: f32, mids: f32, lo: vec3<f32>, hi: vec3<f32>) -> vec3<f32> {
  let mag = edgeMag(hf);
  // Soft threshold: edges below 0.05 are suppressed.
  let threshold = 0.03 + treble * 0.06;
  let edgeWeight = smoothstep(threshold, threshold + 0.15, mag) * amp;
  // Neon colour chosen by edge direction + magnitude.
  let neonCol = neonPalette(mag * (1.5 + treble) + 0.3);
  var boosted = orig + hf * amp * (1.0 + mids * 0.5);
  // ── Idea 1: anti-halo envelope ──────────────────────────────────────
  // The residual boost cannot leave the neighborhood of the photo, so
  // the sharpen does not ring.
  boosted = clamp(boosted, lo - vec3<f32>(0.02), hi + vec3<f32>(0.02));
  return mix(boosted, boosted + neonCol * edgeWeight, edgeWeight);
}

// L1 — Mid-frequency band: audio-bass hue rotation
// The blur already represents mid+low frequencies.  We rotate its hue
// proportionally to the bass level, creating a colour-shifting "colour pump"
// on the smooth parts of the image.
fn processMidFreq(blur: vec3<f32>, amp: f32, bass: f32, time: f32) -> vec3<f32> {
  // Hue rotation driven by bass + slow LFO component.
  let hueShift = bass * 0.4 * amp + sin(time * 0.7) * 0.05 * amp;
  return rotateHue(blur, hueShift);
}

// L2 — Low-frequency band: slow LFO colour breathing
// Modulates saturation and lightness with a very slow sine oscillation.
fn processLowFreq(blur: vec3<f32>, amp: f32, time: f32) -> vec3<f32> {
  let lfoSat  = 1.0 + sin(time * 0.31) * 0.3 * amp;
  let lfoLigh = 1.0 + sin(time * 0.19 + 1.2) * 0.15 * amp;
  var hsl = rgb2hsl(blur);
  hsl.y = clamp(hsl.y * lfoSat, 0.0, 1.0);
  hsl.z = clamp(hsl.z * lfoLigh, 0.0, 1.0);
  return hsl2rgb(hsl);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv  = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;

  // ── Uniform parameters ──────────────────────────────────────────────────
  let highAmp = max(u.zoom_params.x, 0.0);  // high-freq amplitude
  let midAmp  = max(u.zoom_params.y, 0.0);  // mid-freq amplitude
  let lowAmp  = max(u.zoom_params.z, 0.0);  // low-freq amplitude
  let roiRadius = max(u.zoom_params.w, 0.0); // owned by pass 3

  // ── Audio reactivity (plasmaBuffer[0] = bass/mid/treble) ────────────────
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // ── Sample textures ─────────────────────────────────────────────────────
  let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  // C is the previous frame's blur (pass 1 writes B and this pass does not
  // write A, so A cannot replace the blur in the feedback copy).
  let blurTex = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  let blur = blurTex.rgb;

  let hf = highFreq(orig, blur);

  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let pc = vec2<i32>(gid.xy);
  let tL = textureLoad(readTexture, clamp(pc + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0).rgb;
  let tR = textureLoad(readTexture, clamp(pc + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0).rgb;
  let tU = textureLoad(readTexture, clamp(pc + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1)), 0).rgb;
  let tD = textureLoad(readTexture, clamp(pc + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1)), 0).rgb;
  let lo = min(orig, min(tL, min(tR, min(tU, tD))));
  let hi = max(orig, max(tL, max(tR, max(tU, tD))));

  let l0 = processHighFreq(orig, hf, highAmp, treble, mids, lo, hi);
  let l1 = processMidFreq(blur,  midAmp, bass, time);
  let l2 = processLowFreq(blur,  lowAmp, time);

  let base     = mix(blur, l2, clamp(lowAmp, 0.0, 1.0));
  let withMid  = mix(base, l1, clamp(midAmp * 0.5, 0.0, 1.0));

  let highWeight = clamp(highAmp * 0.4, 0.0, 1.0);
  var result = mix(withMid, l0, highWeight);

  // ── Idea 2: edge-directed chroma fringe ─────────────────────────────
  // The residual's photo gradient splits red and blue. High Freq Amp
  // is how far that fringe reaches.
  let lumaW = vec3<f32>(0.2126, 0.7152, 0.0722);
  let grad = vec2<f32>(dot(tR - tL, lumaW), dot(tD - tU, lumaW));
  let glen = length(grad);
  let dir = grad / max(glen, 1e-4);
  let shift = dir * (1.4 * highAmp) / resolution;
  let fringe = smoothstep(0.04, 0.22, edgeMag(hf)) * clamp(highAmp * 0.35, 0.0, 0.7);
  let uvR = clamp(uv - shift, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + shift, vec2<f32>(0.0), vec2<f32>(1.0));
  result.r = mix(result.r, textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r, fringe);
  result.b = mix(result.b, textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b, fringe);

  result = acesToneMap(clamp(result, vec3<f32>(0.0), vec3<f32>(1.0)));
  let alpha = clamp(0.62 + edgeMag(hf) * 0.45 + fringe * 0.2 + roiRadius * 0.0, 0.0, 1.0);
  textureStore(writeTexture, gid.xy, vec4<f32>(result, alpha));
  let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
