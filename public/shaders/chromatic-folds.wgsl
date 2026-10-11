// ────────────────────────────────────────────────────────────────────────────────
//  Chromatic Folds – mind‑bending psychedelic topology
//  Color as a physical dimension: each pixel is a point in 4‑D (x, y, depth, hue).
//  Warps image along local hue‑gradient, bends depth into curvature tensor.
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: fold creases at pivot and antipode; re-folding feedback; cursor pinch pivot
//  A packing: linear pre-ACES display RGB + fold-coverage alpha (C read as colour)
// ────────────────────────────────────────────────────────────────────────────────
#include "_prelude.wgsl"

// ───────────────────────────────────────────────────────────────────────────────
//  RGB ↔ HSV conversion
// ───────────────────────────────────────────────────────────────────────────────
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
  var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
  let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let h6 = h * 6.0;
  var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else               { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Fold the hue around a pivot – creates the "fold" effect
// ───────────────────────────────────────────────────────────────────────────────
fn foldHue(h: f32, pivot: f32, strength: f32) -> f32 {
  let delta = h - pivot;
  return fract(pivot + sign(delta) * pow(abs(delta), strength));
}

// ───────────────────────────────────────────────────────────────────────────────
//  Simple 2‑D noise (hash)
// ───────────────────────────────────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> f32 {
  var p2 = fract(p * vec2<f32>(123.456, 789.012));
  p2 = p2 + dot(p2, p2 + 45.678);
  return fract(p2.x * p2.y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Wrap-around modulo for hue gradients
// ───────────────────────────────────────────────────────────────────────────────
fn wrapMod(x: f32, y: f32) -> f32 {
  if (y == 0.0) { return x; }
    return x - y * floor(x / y);
}

// Signed shortest hue distance a - b in [-0.5, 0.5)
fn hueDelta(a: f32, b: f32) -> f32 {
  return wrapMod(a - b + 0.5, 1.0) - 0.5;
}

// Idea 1: Fold creases — anti-aliased line where the hue sits at `at`.
// `w` is the local hue change per pixel, so the line stays ~1.5 px wide in screen space.
fn creaseLine(hue: f32, at: f32, w: f32) -> f32 {
  let d = abs(hueDelta(hue, at));
  return 1.0 - smoothstep(0.0, 1.5 * w, d);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Main compute entry point
// ───────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

  var uv = vec2<f32>(gid.xy) / dims;
  let texel = 1.0 / dims;
  let time = u.config.x;

  // ──────────────────────────────────────────────────────────────────────────
  //  Parameters
  // ──────────────────────────────────────────────────────────────────────────
  // Bass breathes the fold (≤ +30%). plasmaBuffer[0].x = bass.
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let foldStrength = (u.zoom_params.x * 1.5 + 0.5) * (1.0 + 0.3 * bass); // 0.5 - 2.0 (+bass)
  let pivotHue = u.zoom_params.y;                            // 0 - 1
  let satScale = u.zoom_params.z * 0.5 + 0.75;              // 0.75 - 1.25
  let depthInfluence = u.zoom_params.w;                      // 0 - 1
  // HEAD read these from zoom_config (time / mouse) — now the old midpoints.
  let noiseAmount = 0.0015;                                  // noise displacement
  let feedbackStrength = 0.875;                              // feedback mix
  let rippleStrength = 0.0025;                               // ripple amplitude
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  // ──────────────────────────────────────────────────────────────────────────
  //  1. Read source color & depth
  // ──────────────────────────────────────────────────────────────────────────
  let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // ──────────────────────────────────────────────────────────────────────────
  //  2. Compute local hue gradient (finite differences)
  // ──────────────────────────────────────────────────────────────────────────
  let h = rgb2hsv(srcColor).x;
  let hR = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
  let hL = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
  let hU = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb).x;
  let hD = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb).x;

  // Wrap‑around gradient (handle hue discontinuity at 0/1)
  let gradX = wrapMod(hR - hL + 1.5, 1.0) - 0.5;
  let gradY = wrapMod(hU - hD + 1.5, 1.0) - 0.5;
  let hueGrad = vec2<f32>(gradX, gradY);

  // ──────────────────────────────────────────────────────────────────────────
  //  3. Depth curvature – treat depth as a curvature tensor
  // ──────────────────────────────────────────────────────────────────────────
  let curvature = pow(depthVal, 2.0) * depthInfluence;

  // ──────────────────────────────────────────────────────────────────────────
  //  4. Ambient "fold" displacement
  // ──────────────────────────────────────────────────────────────────────────
  // Map hue gradient to a displacement vector in screen space
  let dispBase = hueGrad * foldStrength * 0.05 * (1.0 + curvature);

  // Add subtle noise to the displacement
  let noise = hash2(uv * 100.0 + time);
  let noiseDisp = vec2<f32>(
    sin(time + noise * 6.28318),
    cos(time + noise * 6.28318)
  ) * noiseAmount;

  var totalDisp = dispBase + noiseDisp;

  // ──────────────────────────────────────────────────────────────────────────
  //  5. Ripple effect (click-driven)
  // ──────────────────────────────────────────────────────────────────────────
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[min(i, 49u)];
    let dist = distance(uv, r.xy);
    let t = time - r.z;
    if (t > 0.0 && t < 3.0) {
      let wave = sin(dist * 30.0 - t * 4.0);
      let amp = rippleStrength * (1.0 - dist) * (1.0 - t / 3.0);
      if (dist > 0.001) {
        totalDisp = totalDisp + normalize(uv - r.xy) * wave * amp;
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  6. Sample displaced UV for color
  // ──────────────────────────────────────────────────────────────────────────
  let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // ──────────────────────────────────────────────────────────────────────────
  //  7. Fold the hue of the sampled color
  // ──────────────────────────────────────────────────────────────────────────
  // Idea 3: Cursor pinch — near the pointer the pivot slides toward the hue
  // under the cursor while the mouse is held, so the user grabs a
  // colour and the image folds around it.
  let aspect = dims.x / max(dims.y, 1.0);
  let mDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouseHue = rgb2hsv(textureSampleLevel(readTexture, u_sampler, clamp(mouse, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb).x;
  // Hold-only: an idle pointer sits at (0.5, 0.5), so a hover pinch would be baked
  // into the default look.
  let pinch = (1.0 - smoothstep(0.0, 0.3, length(mDelta))) * select(0.0, 1.0, mouseDown);
  let localPivot = fract(pivotHue + hueDelta(mouseHue, pivotHue) * pinch);

  var hsv = rgb2hsv(displacedColor);
  let rawHue = hsv.x;
  hsv.x = foldHue(hsv.x, localPivot, foldStrength);
  hsv.y = clamp(hsv.y * satScale, 0.0, 1.0);
  var foldedColor = hsv2rgb(hsv.x, hsv.y, hsv.z);

  // Idea 1: Fold creases — a bright crease where the sampled hue sits on the
  // pivot and a softer shadow seam at the antipode (pivot + 0.5). Width follows
  // the local hue-gradient (hueGrad spans 2 texels). Grey pixels have no hue → no crease.
  let huePerPx = clamp(length(hueGrad) * 0.5, 0.002, 0.05);
  let satGate = smoothstep(0.06, 0.25, hsv.y);
  let creaseAmt = clamp(abs(foldStrength - 1.0) * 1.6 + 0.2, 0.0, 1.0) * satGate;
  let crease = creaseLine(rawHue, localPivot, huePerPx) * creaseAmt;
  let seam = creaseLine(rawHue, fract(localPivot + 0.5), huePerPx * 2.0) * creaseAmt;
  let creaseCol = hsv2rgb(localPivot, 0.3, max(hsv.z, 0.6) * 1.15);
  foldedColor = mix(foldedColor, creaseCol, crease * 0.75);
  foldedColor = foldedColor * (1.0 - 0.45 * seam);

  // ──────────────────────────────────────────────────────────────────────────
  //  8. Feedback: blend with previous frame
  // ──────────────────────────────────────────────────────────────────────────
  let cDims = vec2<i32>(textureDimensions(dataTextureC));
  let cCoord = clamp(vec2<i32>(gid.xy), vec2<i32>(0), cDims - vec2<i32>(1));
  var prev = max(textureLoad(dataTextureC, cCoord, 0).rgb, vec3<f32>(0.0));

  // Idea 2: Re-folding feedback — the history is folded again each frame
  // (gentle strength, slowly drifting pivot), so bands nest into deeper folds
  // instead of only smearing.
  var prevHsv = rgb2hsv(prev);
  let refoldStrength = mix(1.0, foldStrength, 0.15);
  let pivotDrift = 0.02 * sin(time * 0.3);
  prevHsv.x = foldHue(prevHsv.x, fract(localPivot + pivotDrift), refoldStrength);
  prev = hsv2rgb(prevHsv.x, prevHsv.y, prevHsv.z);

  let finalColor = max(mix(foldedColor, prev, feedbackStrength), vec3<f32>(0.0));

  // Semantic alpha: how much the fold moved this pixel (hue shift × saturation) or creased it.
  let foldShift = abs(hueDelta(hsv.x, rawHue)) * 4.0 * hsv.y;
  let alpha = clamp(0.7 + 0.3 * max(foldShift, crease), 0.0, 1.0);

  // ──────────────────────────────────────────────────────────────────────────
  //  9. Write outputs
  // ──────────────────────────────────────────────────────────────────────────
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(aces_tonemap(finalColor), alpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalColor, alpha));
}
