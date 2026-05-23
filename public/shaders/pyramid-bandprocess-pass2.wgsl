// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 2: Laplacian Band Processing
//  Category: image
//  Features: multi-pass-2, laplacian, audio-reactive, frequency-domain
//  Complexity: Medium
//  Part of chain: pyramid-downsample-pass1 → pyramid-bandprocess-pass2 → pyramid-composite-pass3
//
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
//  The processed result is written to writeTexture (intermediate, will be
//  overwritten by pass 3 which adds the ROI magnifying glass) and to
//  dataTextureA for potential debugging / future multi-slot reads.
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
  config:      vec4<f32>,   // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,   // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,   // x=HighFreqAmp, y=MidFreqAmp, z=LowFreqAmp, w=ROIRadius
  ripples:     array<vec4<f32>, 50>,
};

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
fn processHighFreq(orig: vec3<f32>, hf: vec3<f32>, amp: f32, treble: f32, mids: f32) -> vec3<f32> {
  let mag = edgeMag(hf);
  // Soft threshold: edges below 0.05 are suppressed.
  let threshold = 0.03 + treble * 0.06;
  let edgeWeight = smoothstep(threshold, threshold + 0.15, mag) * amp;
  // Neon colour chosen by edge direction + magnitude.
  let neonCol = neonPalette(mag * (1.5 + treble) + 0.3);
  // Brighten existing colour at edge locations (adds glow on top of original).
  let boosted = orig + hf * amp * (1.0 + mids * 0.5);
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

  // ── Audio reactivity (plasmaBuffer[0] = bass/mid/treble) ────────────────
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // ── Sample textures ─────────────────────────────────────────────────────
  let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  // dataTextureC holds the previous frame's Gaussian blur written by pass 1.
  // On the very first frame it is black, which produces orig as the
  // high-freq residual — a reasonable cold-start behaviour.
  let blur = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;

  // ── Frequency decomposition ─────────────────────────────────────────────
  let hf = highFreq(orig, blur);   // high-freq (Laplacian residual)

  // ── Per-band creative processing ─────────────────────────────────────────
  let l0 = processHighFreq(orig, hf, highAmp, treble, mids);
  let l1 = processMidFreq(blur,  midAmp, bass, time);
  let l2 = processLowFreq(blur,  lowAmp, time);

  // ── Reconstruct: blend processed bands ───────────────────────────────────
  // Base = low-freq breathing (replaces the plain blur).
  // Add mid-freq hue-rotated contribution (weighted by midAmp).
  // Add high-freq neon edges on top.
  let base     = mix(blur, l2, clamp(lowAmp, 0.0, 1.0));
  let withMid  = mix(base, l1, clamp(midAmp * 0.5, 0.0, 1.0));
  let withHigh = l0;  // processHighFreq already blends orig + neon edges

  // Final blend: weight high-freq result against the mid+low composite.
  let highWeight = clamp(highAmp * 0.4, 0.0, 1.0);
  var result = mix(withMid, withHigh, highWeight);
  result = clamp(result, vec3<f32>(0.0), vec3<f32>(1.0));

  // ── Store processed result ───────────────────────────────────────────────
  // Write to writeTexture as intermediate output (will be overwritten by pass 3
  // which adds the ROI magnifying glass effect).
  textureStore(writeTexture, gid.xy, vec4<f32>(result, 1.0));

  // Store a copy in dataTextureA for potential debugging / future multi-slot use.
  // (dataTextureB is left unchanged — it holds the Gaussian blur from pass 1
  //  and must not be overwritten here so the post-slot copy propagates it.)
  textureStore(dataTextureA, gid.xy, vec4<f32>(result, edgeMag(hf)));
}
