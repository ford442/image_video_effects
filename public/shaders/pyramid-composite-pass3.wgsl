// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 3: ROI Magnifying-Glass Composite
//  Category: image
//  Features: multi-pass-3, roi, mouse-driven, frequency-domain, composite, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-18
//  Ideas: glass magnification; rim dispersion
//  A packing: display only. Does not write A or B. C is the blur.
// ═══════════════════════════════════════════════════════════════════════════
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

#include "_prelude.wgsl"
// zoom_params: x=HighFreqAmp, y=MidFreqAmp, z=LowFreqAmp, w=ROIRadius

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadBlur(uv: vec2<f32>, res: vec2<f32>) -> vec3<f32> {
  let hi = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
  let p = vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * res);
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0).rgb;
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
  let blur = loadBlur(uv, resolution);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let aspect  = resolution.x / resolution.y;
  let delta   = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist    = length(delta);
  let normDist = dist / roiR;

  // ── Idea 1: glass magnification ─────────────────────────────────────
  // Inside the circle the photo and the blur are sampled closer to the
  // cursor. The radius slider still owns the circle.
  let mag = mix(1.18, 1.0, smoothstep(0.0, 1.0, normDist));
  let uvGlass = clamp(mousePos + (uv - mousePos) / mag, vec2<f32>(0.0), vec2<f32>(1.0));
  let origIn = textureSampleLevel(readTexture, u_sampler, uvGlass, 0.0).rgb;
  let blurIn = loadBlur(uvGlass, resolution);

  let roiScale  = 2.5 + bass * 1.0;
  let innerResult = applyPyramid(
    origIn, blurIn,
    highAmp * roiScale,
    midAmp  * roiScale,
    lowAmp  * roiScale,
    bass, mids, treble, time
  );

  let outerResult = applyPyramid(
    orig, blur,
    highAmp * 0.3,
    midAmp  * 0.2,
    lowAmp  * 0.15,
    bass, mids, treble, time
  );

  let blend = smoothstep(0.85, 1.1, normDist);
  var composed = mix(innerResult, outerResult, blend);

  let ringPeak   = 1.0 - abs(normDist - 1.0) / RING_WIDTH;
  let ringAlpha  = clamp(ringPeak, 0.0, 1.0) * 0.6;
  let ringHue    = fract(time * 0.08 + bass * 0.3);
  let ringCol    = hsl2rgb(vec3<f32>(ringHue, 0.9, 0.7));
  composed = mix(composed, ringCol, ringAlpha);

  // ── Idea 2: rim dispersion ──────────────────────────────────────────
  // The glass edge splits red and blue along the radius of the ring.
  let radial = delta / max(dist, 1e-4);
  let ca = ringAlpha * 2.2 / resolution.x;
  let rimR = textureSampleLevel(readTexture, u_sampler, clamp(uv + radial * ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let rimB = textureSampleLevel(readTexture, u_sampler, clamp(uv - radial * ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  composed.r = mix(composed.r, rimR, ringAlpha * 0.55);
  composed.b = mix(composed.b, rimB, ringAlpha * 0.55);

  let edgeHint = length(orig - blur);
  let alpha = clamp(0.7 + ringAlpha * 0.3 + edgeHint * 0.2, 0.0, 1.0);
  let finalColor = acesToneMap(clamp(composed, vec3<f32>(0.0), vec3<f32>(1.0)));
  textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, alpha));

  // Propagate depth for downstream effects.
  // r32float only stores the R channel; other vec4 components are discarded.
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
