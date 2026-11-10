// ═══════════════════════════════════════════════════════════════════
//  digital-reveal-guided — Batch 60
//  Matrix rain + depth-guided filter: spring brush, held widen, capped
//  click ripples, exact C trail mask, audio glyph density, ACES.
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-09
//  Ideas: rain head + decaying tail per column (native Matrix code rain); glyph-cell reveal front (mask sampled at the glyph-cell centre so the reveal steps in cell units, photo shows through the glyph stencil with a lit cell rim)
//  A packing: mask state — r = trail mask (constant per glyph cell), g = guided-filter confidence, b = glyph, a = 1.
//    Texels (0,0) = brush glide [pos.xy, vel.xy] and (1,0) = [fract(time), 0, 0, 0.7371 sentinel] are STATE, not pixels.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENT: f32 = 0.7371;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx+p3.yz)*p3.zy);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn glyphShape(cellUV: vec2<f32>, id: f32) -> f32 {
  let bars = step(0.3, cellUV.x) * step(cellUV.x, 0.7) * step(0.2, cellUV.y);
  let dots = step(length(cellUV - vec2<f32>(0.5)), 0.18);
  return max(bars, dots * step(fract(id * 0.37), 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let aspect = res.x / res.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let density = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + treble * 0.3);
  let revealSize = u.zoom_params.y;
  let trailFade = u.zoom_params.z;
  let depthInfluence = u.zoom_params.w;

  // ── Brush glide, persisted in two A texels ──────────────────────
  // HEAD kept this spring in extraBuffer[133..138], which the host re-uploads as ZERO every frame: the
  // spring never persisted (the first-frame snap branch ran every frame and other workgroups raced on
  // the zeroed slots), so the reveal brush was pinned/racy. Texel (0,0) = (pos.xy, vel.xy), texel (1,0)
  // = (fract(lastTime), 0, 0, SENT). Every thread integrates the same critically damped step (omega 10,
  // as HEAD); the sentinel guards the first frame / inherited C. fract(time) stays exact on rgba16float.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var smoothMouse = select(mouse, st0.xy, stateOk);
  var springVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  let omega = 10.0;
  springVel += ((mouse - smoothMouse) * (omega * omega) - springVel * (2.0 * omega)) * springDt;
  smoothMouse += springVel * springDt;
  // f16 rest-snap: a spring stored in rgba16float stalls just short of the cursor with a residual
  // velocity that never decays; settle exactly once near and slow.
  let settled = all(abs(mouse - smoothMouse) < vec2<f32>(0.004)) && length(springVel) < 0.06;
  smoothMouse = select(smoothMouse, mouse, settled);
  springVel = select(springVel, vec2<f32>(0.0), settled);

  // ── Glyph grid (shared by the rain and the reveal front) ────────
  // Columns are quantised to whole numbers so treble breathes the grid in steps, not a shimmer
  // (density 0.5 -> 30 columns, identical to HEAD at the default).
  let cols = floor(18.0 + density * 24.0 + 0.5);
  let gridSize = vec2<f32>(cols, cols * aspect);
  let cellUV = fract(uv * gridSize);
  let cellID = floor(uv * gridSize);

  // ── Idea 2 (part 1): the reveal mask lives on the glyph cells ───
  // The trail mask is read at, and the brush/click reveal evaluated at, the glyph-cell CENTRE, so every
  // pixel of a cell computes the same value and the reveal steps in cell units. One C load and one
  // ripple loop per pixel, exactly as HEAD (just at the cell centre instead of the pixel).
  let ccUV = min((cellID + 0.5) / gridSize, vec2<f32>(1.0));
  let ccCoord = clamp(vec2<i32>(ccUV * res), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
  let ccIsState = ccCoord.y == 0 && ccCoord.x < 2;
  let prevVal = select(textureLoad(dataTextureC, ccCoord, 0).r, 0.0, ccIsState);
  let ccCorrected = vec2<f32>(ccUV.x * aspect, ccUV.y);
  let mouseCorrected = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let dist = distance(ccCorrected, mouseCorrected);
  let brushRadius = (revealSize * 0.32 + 0.05) * select(1.0, 1.35, held);
  let brush = smoothstep(brushRadius, brushRadius * 0.45, dist);
  let fadeFactor = 0.78 + trailFade * 0.21;

  var rippleReveal = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      rippleReveal += smoothstep(0.14, 0.0, distance(ccCorrected, rAspect)) * max(1.0 - age * 0.85, 0.0);
    }
  }

  let newVal = clamp(max(prevVal * fadeFactor, brush + rippleReveal), 0.0, 1.0);

  let radiusBase = i32(mix(2.0, 7.0, revealSize));
  let epsilonBase = mix(0.0001, 0.05, depthInfluence);
  let mouseDist = length(uv - smoothMouse);
  let mouseFactor = exp(-mouseDist * mouseDist * 6.0);
  let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.35, mouseFactor));
  let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.08, mouseFactor);
  let maxRadius = min(radius, 6);

  var sumGuide = 0.0;
  var sumInput = vec3<f32>(0.0);
  var sumGuideInput = vec3<f32>(0.0);
  var sumGuide2 = 0.0;
  var count = 0.0;

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
      let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
      let inputVal = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      sumGuide += guideVal;
      sumInput += inputVal;
      sumGuideInput += inputVal * guideVal;
      sumGuide2 += guideVal * guideVal;
      count += 1.0;
    }
  }

  let meanGuide = sumGuide / max(count, 1.0);
  let meanInput = sumInput / max(count, 1.0);
  let meanGI = sumGuideInput / max(count, 1.0);
  let meanGuide2 = sumGuide2 / max(count, 1.0);
  let varGuide = meanGuide2 - meanGuide * meanGuide;

  let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
  let b = meanInput - a * meanGuide;
  let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let filtered = a * guide + b;
  let confidence = length(a) * depthInfluence;

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let filteredResult = mix(original, filtered, depthInfluence * newVal);

  // Glyph churn is HEAD's: each cell cycles through glyphs at colSpeed (mids speed it up).
  let colHash = hash22(vec2<f32>(cellID.x, 0.0));
  let colSpeed = colHash.y * (3.0 + mids * 2.0);
  let verticalPos = cellID.y + time * colSpeed;
  let charID = floor(verticalPos);
  let charHash = hash22(vec2<f32>(cellID.x, charID));
  let flicker = step(0.08, charHash.x);
  let glyph = glyphShape(cellUV, charHash.x);

  // ── Idea 1: rain head + decaying tail ───────────────────────────
  // HEAD lit every cell of a column in lock-step (dropVal depends only on time, cellID.y is an integer
  // offset) so the column pulsed with no head and no fall. Real Matrix code rain is a white-hot HEAD
  // falling down the column with a long fading tail of glyphs behind it. Three drops per column, own
  // phase; fall speed is audio-free so mids never teleport the head (glyph churn keeps colSpeed).
  let tailLen = 9.0 + 14.0 * hash22(vec2<f32>(cellID.x, 5.0)).x;
  let dropSpeed = 3.0 + colHash.y * 6.0;            // cell rows per second
  let period = gridSize.y + tailLen;                // head runs past the bottom so the tail leaves the frame
  var streak = 0.0;
  var headness = 0.0;
  for (var k = 0; k < 3; k = k + 1) {
    let ph = hash22(vec2<f32>(cellID.x, 17.0 + f32(k))).x;
    let headPos = fract(ph + time * dropSpeed / period) * period;
    let behind = headPos - cellID.y;                // rows behind the head (>= 0 inside the drop)
    let inDrop = step(0.0, behind) * (1.0 - smoothstep(tailLen - 2.0, tailLen, behind));
    let rise = smoothstep(0.0, 0.6, behind);
    let lit = rise * exp(-behind * (2.4 / tailLen)) * inDrop;
    streak = max(streak, lit);
    headness = max(headness, lit * (1.0 - smoothstep(0.6, 1.4, behind)));
  }
  let rainGreen = vec3<f32>(0.05, 0.95, 0.35);
  let rainHot = vec3<f32>(0.85, 1.0, 0.75);
  var rainColor = mix(rainGreen, rainHot, headness) * streak * flicker * glyph;
  // HEAD painted ~9 % of cells as solid pale squares regardless of glyph; keep the pale highlight
  // but as a glyph, brightest where a streak passes (a lit character inside the tail).
  let sparkle = step(0.97 - density * 0.12, charHash.y);
  rainColor = mix(rainColor, rainHot * glyph * (0.2 + 0.8 * streak), sparkle);
  rainColor += vec3<f32>(0.1, 0.0, 0.15) * bass;

  // ── Idea 2 (part 2): glyph-cell reveal front ────────────────────
  // newVal is constant per cell. Where it is mid-way (the brush rim and a fading trail) the photo shows
  // only through the cell's glyph stencil, outlined by a lit cell rim; the interior (newVal -> 1) is the
  // full guided-filter image and newVal -> 0 is rain. Reveal and fade both read as cells flipping.
  let m = clamp(newVal, 0.0, 1.0);
  let frontBand = smoothstep(0.0, 0.25, m) * (1.0 - smoothstep(0.75, 1.0, m));
  let reveal = mix(m, glyph, frontBand);
  let edgeD = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
  // rim only on the outer half of the front (mask 0.05..0.5) so a wide fading trail is not a mesh
  let rimBand = smoothstep(0.02, 0.15, m) * (1.0 - smoothstep(0.35, 0.6, m));
  let rim = rainGreen * rimBand * (1.0 - smoothstep(0.0, 0.07, edgeD)) * 0.55;

  var finalColor = mix(rainColor, filteredResult, reveal) + rim;
  // the guided-filter model a*g+b can leave [0,1]; the catalog ACES fit maps negatives to bright
  finalColor = acesToneMap(max(finalColor * (0.96 + bass * 0.06), vec3<f32>(0.0)));
  let alpha = clamp(confidence * reveal + 0.35, 0.0, 1.0);

  var aOut = vec4<f32>(m, confidence, glyph, 1.0);
  if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(smoothMouse, springVel); }
  if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
