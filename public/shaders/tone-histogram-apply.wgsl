// ═══════════════════════════════════════════════════════════════════
//  Tone Histogram Apply (Pass 2)
//  Category: post-processing
//  Features: multi-pass-2, histogram, auto-exposure, color-grade
//  Complexity: Medium
//  Upgraded: 2026-11-21
//  Ideas: clip-limited CDF equalisation blend (CLAHE clip, §12.2A); percentile-anchored levels — extended-Reinhard white point at p95, post-curve p05..p95 contrast span pivoted on the tone-mapped mean and re-anchored to Target Luma as far as the exposure clamp can deliver, soft-rolled tails (§12.2A)
//  A packing: raw stats field (exposure/3.5, meanLuma, peakBinNorm, saturation) — never ACES
//  Rescue: the 256-bin histogram HEAD read from extraBuffer[1..258] was never written by
//          anything (tone-histogram is single-pass since v2), so exposure pinned at 3.5 and
//          contrast at ×63. The histogram is now built in-pass (workgroup atomics over a
//          stratified whole-frame sample grid); the HEAD reduction runs on it unchanged.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// 32×32 stratified grid over the WHOLE frame, 4 samples per invocation of the
// 16×16 workgroup. Every workgroup sees the same grid → identical histogram in
// every tile (no seams), integer counts → order-independent → no shimmer.
const GRID: u32 = 32u;
const HIST_SAMPLES: f32 = 1024.0;
const CLIP_MULT: f32 = 3.0;       // CLAHE clip limit: bins above 3× the mean bin are clipped
const GAIN_CAP: f32 = 3.0;        // ceiling on the 255/span auto-contrast gain

var<workgroup> wgHist: array<atomic<u32>, 256>;
var<workgroup> wgCdf: array<f32, 256>;
var<workgroup> wgExposure: f32;
var<workgroup> wgMeanLuma: f32;
var<workgroup> wgContrast: f32;
var<workgroup> wgSaturation: f32;
var<workgroup> wgPeakBinNorm: f32;
var<workgroup> wgPeakBin: u32;
var<workgroup> wgWhite: f32;
var<workgroup> wgPivot: f32;
var<workgroup> wgAnchor: f32;
var<workgroup> wgEqAmount: f32;
var<workgroup> wgSpread: f32;

// ─ _std/_std_hash.wgsl (body-identical copies) ─
fn pcg2d(v_in: vec2<u32>) -> vec2<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  return v;
}

fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}

fn hashCell22(c: vec2<i32>) -> vec2<f32> {
  let h = pcg2d(bitcast<vec2<u32>>(c));
  return vec2<f32>(u32ToUnit(h.x), u32ToUnit(h.y));
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let p = select(vec4<f32>(c.bg, -1.0, 2.0 / 3.0), vec4<f32>(c.gb, 0.0, -1.0 / 3.0), c.b < c.g);
  let q = select(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), p.x < c.r);
  let d = q.x - min(q.w, q.y);
  let e = 1e-5;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let rgb = clamp(abs(fract(c.x + vec3<f32>(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
  return c.z * mix(vec3<f32>(1.0), rgb, c.y);
}

// Idea 2: extended Reinhard c·(1 + c/W²)/(1 + c); W→∞ is HEAD's c/(1+c).
fn toneCurve(c: vec3<f32>, white2: f32) -> vec3<f32> {
  return c * (vec3<f32>(1.0) + c / white2) / (vec3<f32>(1.0) + c);
}

// Idea 2 (tails): identity on [0.12, 0.88]; the outer tails roll off smoothly
// toward 0 / 1 instead of the hard clamp HEAD used (value- and slope-continuous).
fn softEnds(x: vec3<f32>) -> vec3<f32> {
  let lo = 0.12;
  let hi = 0.88;
  let top = vec3<f32>(hi) + (1.0 - hi) * tanh(clamp((x - vec3<f32>(hi)) / (1.0 - hi), vec3<f32>(-8.0), vec3<f32>(8.0)));
  let bot = lo * (vec3<f32>(1.0) + tanh(clamp((x - vec3<f32>(lo)) / lo, vec3<f32>(-8.0), vec3<f32>(8.0))));
  return select(select(x, bot, x < vec3<f32>(lo)), top, x > vec3<f32>(hi));
}

@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(local_invocation_index) lidx: u32,
) {
  let res = u.config.zw;
  let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let coord = vec2<i32>(gid.xy);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lumaW = vec3<f32>(0.2126, 0.7152, 0.0722);

  // ── Rescue: build the luma histogram in-pass (HEAD read an unwritten buffer) ──
  atomicStore(&wgHist[lidx], 0u);
  workgroupBarrier();
  for (var j = 0u; j < 4u; j = j + 1u) {
    let p = lidx + 256u * j;
    let cell = vec2<i32>(i32(p & (GRID - 1u)), i32(p / GRID));
    let jit = hashCell22(cell);                                    // static jitter: no frame shimmer
    let suv = (vec2<f32>(cell) + 0.1 + 0.8 * jit) / f32(GRID);
    let sl = clamp(dot(textureSampleLevel(readTexture, u_sampler, suv, 0.0).rgb, lumaW), 0.0, 1.0);
    atomicAdd(&wgHist[min(255u, u32(sl * 255.0 + 0.5))], 1u);
  }
  workgroupBarrier();

  if (lidx == 0u) {
    let totalPixels = HIST_SAMPLES;
    let clipLimit = CLIP_MULT * totalPixels / 256.0;
    var weighted = 0.0;
    var cumulative = 0.0;
    var p05 = 0u;
    var p95 = 255u;
    var peakBin = 0u;
    var peakCount = 0.0;
    var excess = 0.0;
    var clippedRun = 0.0;

    let lowCut = totalPixels * 0.05;
    let highCut = totalPixels * 0.95;

    // HEAD reduction (weighted mean, p05/p95, peak bin) — unchanged, now fed real counts.
    // ── Idea 1: clip-limited CDF (CLAHE clip), built in the same pass ───
    // Every bin is clipped at 3× the mean bin; the clipped mass is spread uniformly
    // (analytically, at lookup: spread·(bin+0.5)); the CDF is the cumulative sum at
    // each bin's mid-rank. A spike bin (sky, black letterbox) can no longer dominate.
    for (var b = 0u; b < 256u; b = b + 1u) {
      let count = f32(atomicLoad(&wgHist[b]));
      weighted = weighted + f32(b) * count;
      cumulative = cumulative + count;
      if (cumulative <= lowCut) { p05 = b; }
      if (cumulative <= highCut) { p95 = b; }
      if (count > peakCount) { peakCount = count; peakBin = b; }
      excess = excess + max(count - clipLimit, 0.0);
      let clipped = min(count, clipLimit);
      wgCdf[b] = clippedRun + 0.5 * clipped;
      clippedRun = clippedRun + clipped;
    }
    wgSpread = excess / 256.0;

    let meanLuma = clamp((weighted / totalPixels) / 255.0, 0.001, 1.0);
    let targetLum = mix(0.35, 0.65, clamp(u.zoom_params.x, 0.0, 1.0));
    let exposure = clamp(targetLum / meanLuma, 0.5, 3.5);

    // ── Idea 2: percentile-anchored levels ──────────────────────────────
    // The 95th-percentile luma after exposure is Reinhard's white point, so the
    // top of the histogram lands at display white and mid-tones do not sag. The
    // p05..p95 span is then measured AFTER that curve (HEAD measured it on the
    // source and pivoted at a fixed 0.5, which double-counts once the curve has
    // done its work), and the stretch pivots on the tone-mapped MEAN, which is then
    // re-anchored to Target Luma only as far as the exposure clamp (0.5…3.5) could
    // really deliver it (`reach`): a normal frame lands on Target Luma, while a
    // fade-to-black / fade-to-white frame is not invented into mid-grey.
    let p05n = f32(p05) / 255.0;
    let p95n = f32(p95) / 255.0;
    let white = max(p95n * exposure, 0.6);
    let w2 = white * white;
    let third = vec3<f32>(0.3333333);
    let lowT = dot(toneCurve(vec3<f32>(p05n * exposure), w2), third);
    let highT = dot(toneCurve(vec3<f32>(p95n * exposure), w2), third);
    let meanT = dot(toneCurve(vec3<f32>(meanLuma * exposure), w2), third);
    // Rescue: HEAD let a flat frame take ×63 contrast (span clamped at 4/255); cap the gain.
    let toneSpan = max(highT - lowT, 0.08);
    let contrast = mix(0.85, 1.55, clamp(u.zoom_params.y, 0.0, 1.0)) * min(1.0 / toneSpan, GAIN_CAP);
    let saturation = mix(0.80, 1.55, clamp(u.zoom_params.z, 0.0, 1.0));

    wgMeanLuma = meanLuma;
    wgExposure = exposure;
    wgContrast = contrast;
    wgSaturation = saturation;
    wgPeakBinNorm = f32(peakBin) / 255.0;
    wgPeakBin = peakBin;
    wgWhite = white;
    wgPivot = meanT;
    let reachA = meanLuma * exposure / max(targetLum, 0.01);
    wgAnchor = mix(meanT, targetLum, min(reachA, 1.0 / max(reachA, 1e-3)));
    wgEqAmount = 0.5 * clamp(u.zoom_params.y, 0.0, 1.0);          // rides the Contrast slider; 0 ⇒ HEAD behaviour
  }
  workgroupBarrier();

  var color = src.rgb * wgExposure;
  color = toneCurve(color, wgWhite * wgWhite);
  color = softEnds((color - vec3<f32>(wgPivot)) * wgContrast + vec3<f32>(wgAnchor));

  // ── Idea 1: blend the graded luma toward the clipped-CDF rank of the source luma ──
  let srcLuma = clamp(dot(src.rgb, lumaW), 0.0, 1.0);
  let eqPos = srcLuma * 255.0;
  let i0 = u32(min(floor(eqPos), 255.0));
  let i1 = min(i0 + 1u, 255u);
  let eqLuma = clamp((mix(wgCdf[i0], wgCdf[i1], fract(eqPos)) + wgSpread * (eqPos + 0.5)) / HIST_SAMPLES, 0.0, 1.0);
  let gradedLuma = dot(color, lumaW);
  let targetLuma = mix(gradedLuma, eqLuma, wgEqAmount);
  color = clamp(color * clamp((targetLuma + 0.01) / (gradedLuma + 0.01), 0.0, 3.0), vec3<f32>(0.0), vec3<f32>(1.0));

  var hsv = rgb2hsv(color);
  hsv.y = clamp(hsv.y * wgSaturation, 0.0, 1.0);

  let peakBin = wgPeakBin;
  let psychoMode = u.zoom_params.w > 0.5;
  if (psychoMode && (peakBin < 40u || peakBin > 215u)) {
    let shift = 0.08 * sin(u.config.x * 0.9 + f32(peakBin) * 0.05);
    hsv.x = fract(hsv.x + shift);
  }

  let outColor = hsv2rgb(hsv);

  if (inBounds) {
    // Alpha is the source coverage (HEAD hardcoded 1.0 and erased an upstream pass's alpha).
    textureStore(writeTexture, coord, vec4<f32>(outColor, clamp(src.a, 0.0, 1.0)));
    textureStore(dataTextureA, coord, vec4<f32>(wgExposure / 3.5, wgMeanLuma, wgPeakBinNorm, wgSaturation));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  }
}
