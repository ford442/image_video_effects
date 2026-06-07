// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 3: ROI Magnifying-Glass Composite
//  Category: image
//  Features: multi-pass-3, roi, mouse-driven, frequency-domain, composite
//  Complexity: Medium
//  Part of chain: pyramid-downsample-pass1 → pyramid-bandprocess-pass2 → pyramid-composite-pass3
//
//  This is the final pass of the pyramid chain.  It applies the full Laplacian
//  pyramid frequency-domain effect with a ROI (region-of-interest) magnifying-
//  glass twist:
//
//    • OUTSIDE the ROI circle  — subtle band processing (mild sharpening,
//                                low-freq breathing, gentle hue shift)
//    • INSIDE the ROI circle   — full amplified band processing (strong neon
//                                edges, heavy hue rotation, bright breathing)
//    • ROI BORDER              — thin luminous ring to mark the boundary
//
//  The ROI centre tracks the mouse cursor (zoom_config.yz, normalised 0–1).
//  The ROI radius is controlled by zoom_params.w.
//
//  Inputs:
//    readTexture   — original slot input (same for all passes in the chain)
//    dataTextureC  — previous-frame Gaussian blur from pass 1 (via dataTexB→C)
//  Outputs:
//    writeTexture  — final composited frame (sent to screen)
//
//  Uniforms:
//    u.zoom_config.y / .z  = normalised mouse X / Y (ROI centre)
//    u.zoom_config.w       = mouse button down (> 0.5 = pressed)
//    u.zoom_params.x       = high-frequency amplitude  (L0)
//    u.zoom_params.y       = mid-frequency amplitude   (L1)
//    u.zoom_params.z       = low-frequency amplitude   (L2)
//    u.zoom_params.w       = ROI radius (normalised, e.g. 0.2)
//  Audio (via plasmaBuffer):
//    plasmaBuffer[0].x = bass   → mid-freq hue rotation driver
//    plasmaBuffer[0].y = mids   → high-freq edge brightness
//    plasmaBuffer[0].z = treble → high-freq edge sharpness
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

// ─── Colour helpers (shared with pass 2) ─────────────────────────────────────

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

fn rotateHue(rgb: vec3<f32>, shift: f32) -> vec3<f32> {
  var hsl = rgb2hsl(rgb);
  hsl.x = fract(hsl.x + shift);
  return hsl2rgb(hsl);
}

fn neonPalette(t: f32) -> vec3<f32> {
  let hue = fract(t * 1.5 + 0.55);
  return hsl2rgb(vec3<f32>(hue, 1.0, 0.6));
}

// ─── Pyramid band processing (parametric, used at two amplitudes) ─────────────

// Apply the full Gaussian-Laplacian pyramid effect at a given amplitude scale.
// `ampScale` = 1.0 outside ROI, > 1.0 inside ROI.
fn applyPyramid(
  orig:     vec3<f32>,
  blur:     vec3<f32>,
  highAmp:  f32,
  midAmp:   f32,
  lowAmp:   f32,
  bass:     f32,
  mids:     f32,
  treble:   f32,
  time:     f32
) -> vec3<f32> {
  // High-frequency residual (Laplacian).
  let hf  = orig - blur;
  let mag = length(hf);

  // L0 — Edge neon.
  let threshold  = 0.03 + treble * 0.06;
  let edgeWeight = smoothstep(threshold, threshold + 0.15, mag) * highAmp;
  let neonCol    = neonPalette(mag * (1.5 + treble) + 0.3);
  let l0 = orig + hf * highAmp * (1.0 + mids * 0.5) + neonCol * edgeWeight;

  // L1 — Mid-frequency hue rotation.
  let hueShift = bass * 0.4 * midAmp + sin(time * 0.7) * 0.05 * midAmp;
  let l1 = rotateHue(blur, hueShift);

  // L2 — Low-frequency LFO breathing.
  var hsl = rgb2hsl(blur);
  hsl.y = clamp(hsl.y * (1.0 + sin(time * 0.31) * 0.3 * lowAmp), 0.0, 1.0);
  hsl.z = clamp(hsl.z * (1.0 + sin(time * 0.19 + 1.2) * 0.15 * lowAmp), 0.0, 1.0);
  let l2 = hsl2rgb(hsl);

  // Reconstruct.
  let base      = mix(blur, l2, clamp(lowAmp, 0.0, 1.0));
  let withMid   = mix(base, l1, clamp(midAmp * 0.5, 0.0, 1.0));
  let highBlend = clamp(highAmp * 0.4, 0.0, 1.0);
  let result    = mix(withMid, l0, highBlend);
  return clamp(result, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Width of the ROI boundary ring in normalised distance units (not a fraction
// of roiR, but an absolute threshold in the normDist = dist/roiR space).
// At normDist = 1.0 the ring peaks; it fades over ±RING_WIDTH from that peak.
const RING_WIDTH: f32 = 0.06;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv   = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;

  // ── Parameters ─────────────────────────────────────────────────────────
  let highAmp  = max(u.zoom_params.x, 0.0);
  let midAmp   = max(u.zoom_params.y, 0.0);
  let lowAmp   = max(u.zoom_params.z, 0.0);
  let roiR     = max(u.zoom_params.w, 0.01);   // ROI radius, minimum 0.01

  // ── Mouse position → ROI centre ─────────────────────────────────────────
  // zoom_config.yz holds normalised mouse position (0–1 in both axes).
  let mousePos = u.zoom_config.yz;

  // ── Audio ───────────────────────────────────────────────────────────────
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // ── Sample textures ─────────────────────────────────────────────────────
  let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let blur = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // ── ROI radial distance (aspect-ratio corrected) ─────────────────────────
  // Scale the X component by the aspect ratio so that a given normalised
  // offset in X covers the same number of screen pixels as the same offset
  // in Y.  Scaling by vec2(aspect, 1.0) achieves a circular ROI regardless
  // of canvas dimensions (wider-than-tall canvases have aspect > 1).
  let aspect  = resolution.x / resolution.y;
  let delta   = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist    = length(delta);

  // Normalised distance relative to roiR (0 = centre, 1 = rim, >1 = outside).
  let normDist = dist / roiR;

  // ── Inside ROI — enhanced processing ────────────────────────────────────
  // Amplify all bands significantly to create the "magnifying glass of
  // psychedelic detail" described in the issue.
  let roiScale  = 2.5 + bass * 1.0;  // 2.5× base + audio boost
  let innerResult = applyPyramid(
    orig, blur,
    highAmp * roiScale,
    midAmp  * roiScale,
    lowAmp  * roiScale,
    bass, mids, treble, time
  );

  // ── Outside ROI — subtle processing ─────────────────────────────────────
  let outerResult = applyPyramid(
    orig, blur,
    highAmp * 0.3,
    midAmp  * 0.2,
    lowAmp  * 0.15,
    bass, mids, treble, time
  );

  // ── Smooth blend across the ROI boundary ────────────────────────────────
  // smoothstep from fully-inner (normDist=0.8) to fully-outer (normDist=1.1)
  // gives a soft falloff rather than a hard ring cut.
  let blend = smoothstep(0.85, 1.1, normDist);  // 0 inside, 1 outside
  var composed = mix(innerResult, outerResult, blend);

  // ── ROI border ring — thin luminous outline ──────────────────────────────
  // Peaks at normDist ≈ 1.0, width = RING_WIDTH of the normalised radius.
  let ringPeak   = 1.0 - abs(normDist - 1.0) / RING_WIDTH;
  let ringAlpha  = clamp(ringPeak, 0.0, 1.0) * 0.6;
  // Ring colour pulses gently with time and bass.
  let ringHue    = fract(time * 0.08 + bass * 0.3);
  let ringCol    = hsl2rgb(vec3<f32>(ringHue, 0.9, 0.7));
  composed = mix(composed, ringCol, ringAlpha);

  // ── Final output ─────────────────────────────────────────────────────────
  let finalColor = clamp(composed, vec3<f32>(0.0), vec3<f32>(1.0));
  textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));

  // Propagate depth for downstream effects.
  // r32float only stores the R channel; other vec4 components are discarded.
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
