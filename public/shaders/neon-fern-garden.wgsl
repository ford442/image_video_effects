// ═══════════════════════════════════════════════════════════════════
//  Neon Fern Garden
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, upgraded-rgba, semantic-alpha, depth-aware
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: fiddlehead unfurl (live growthPhase clips the tip and coils the last 20% into a crozier); dew on leaflet tips; soil glow-bed under each base
//  A packing: linear pre-ACES RGB + presence alpha (exact C load, 2.5% ghost)
// ═══════════════════════════════════════════════════════════════════
//  Procedurally generated fern fronds unfurling in neon colors against
//  dark soil. Bass drives growth animation, mids brighten the soil glow-bed,
//  treble creates dewdrop sparkles. Mouse attracts or repels frond tips.
//  Frame: p.y = +1 at the top, -1 at the bottom (zoom_config.yz has y=0 at
//  the top, so both p and the mouse are flipped) — bases sit on the soil.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530717958647692;

fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0;
  return mix(
    mix(hash2(vec2<f32>(n)), hash2(vec2<f32>(n + 1.0)), u.x),
    mix(hash2(vec2<f32>(n + 57.0)), hash2(vec2<f32>(n + 58.0)), u.x),
    u.y
  );
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn smoothstepf32(edge0: f32, edge1: f32, x: f32) -> f32 {
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

// Per-fern placement (base / angle / scale formulas unchanged from HEAD) plus the
// live growth phase that drives the fiddlehead unfurl.
struct FernParams {
  base: vec2<f32>,
  angle: f32,
  scale: f32,
  unfurl: f32,   // 0 = tight crozier, 1 = fully open frond
};

fn fernParams(fi: f32, time: f32, bass: f32, growthPhase: f32) -> FernParams {
  var fp: FernParams;
  // Angle formula as HEAD; angles that would point below the soil are mirrored
  // into the upper half-plane so every frond fans upward from its base.
  var a = fi * 2.5;
  a = a - 3.14159 * floor(a / 3.14159);
  a = clamp(a, 0.5, 3.14159 - 0.5);
  fp.angle = a + sin(time * 0.1 + fi) * 0.2;
  fp.base = vec2<f32>(
    sin(fi * 1.3) * 0.4,
    -0.85 + sin(fi * 0.7) * 0.05
  );
  fp.scale = 0.5 + sin(fi * 2.1 + time * 0.15) * 0.15 +
             bass * 0.1 * sin(time * 2.0 + fi);
  // ── Idea 1: fiddlehead unfurl — growthPhase is live; each fern is staggered
  // by a hash, opens over the first half of its cycle, holds, then re-furls.
  let phase = fract(growthPhase + hash2(vec2<f32>(fi * 7.31, 2.17)));
  fp.unfurl = smoothstepf32(0.0, 0.5, phase) * (1.0 - smoothstepf32(0.92, 1.0, phase));
  return fp;
}

// Bezier control points of one frond (HEAD's tip / mouse bend / mid formulas).
struct FrondCtl {
  mid: vec2<f32>,
  tip: vec2<f32>,
  growth: f32,
};

fn frondControl(base: vec2<f32>, angle: f32, scale: f32,
                time: f32, bass: f32, mouse: vec2<f32>, attract: f32) -> FrondCtl {
  let tip = base + vec2<f32>(cos(angle), sin(angle)) * scale;

  // Mouse attraction/repulsion on tip (FIX: safe normalize)
  let tipToMouse = mouse - tip;
  let tipDist = length(tipToMouse);
  let tipInfluence = smoothstepf32(0.5, 0.0, tipDist);
  let tipOffset = (tipToMouse / max(tipDist, 1e-4)) * tipInfluence * attract * 0.15;
  let bentTip = tip + tipOffset;

  // Bend the frond with growth (bass-driven)
  let growth = 0.6 + bass * 0.4;
  let bend = sin(time * 0.5) * 0.08 * growth;
  let mid = mix(base, bentTip, 0.5) + vec2<f32>(cos(angle + 1.57), sin(angle + 1.57)) * bend;

  var c: FrondCtl;
  c.mid = mid;
  c.tip = bentTip;
  c.growth = growth;
  return c;
}

fn bezierPt(base: vec2<f32>, mid: vec2<f32>, tip: vec2<f32>, t: f32) -> vec2<f32> {
  let oneMinusT = 1.0 - t;
  return base * (oneMinusT * oneMinusT) +
         mid * (2.0 * oneMinusT * t) +
         tip * (t * t);
}

// ── Idea 1: crozier — the last 20% of the drawn frond (t in [0.8*tEnd, tEnd])
// is wound into an inward spiral tangent to the stem at the pivot. `curl`
// (1 - unfurl) is both the mix weight and the number of turns, so the coil
// straightens continuously into the plain Bezier as the fern opens.
fn crozierPt(base: vec2<f32>, mid: vec2<f32>, tip: vec2<f32>, t: f32, tEnd: f32, curl: f32) -> vec2<f32> {
  let tc = min(t, tEnd);
  let pt = bezierPt(base, mid, tip, tc);
  let t0 = tEnd * 0.8;
  let s = clamp((tc - t0) / max(tEnd * 0.2, 1e-3), 0.0, 1.0);
  let pivot = bezierPt(base, mid, tip, t0);
  let tail = bezierPt(base, mid, tip, tEnd) - pivot;
  let len = length(tail);
  let d = tail / max(len, 1e-4);
  let n = vec2<f32>(-d.y, d.x);
  let theta = curl * 8.0;                       // up to ~1.3 turns when fully furled
  // coil radius from arc length, floored so the furled spiral stays wider
  // than the stem instead of collapsing into a knob
  let rad = max(len / (0.65 * max(theta, 0.6)), 0.06 * length(tip - base));
  let ang = s * theta;
  let radius = rad * (1.0 - 0.7 * s);           // spiral inward, tip at the centre
  let v = -n;
  let c = cos(ang);
  let sn = sin(ang);
  let rv = vec2<f32>(v.x * c - v.y * sn, v.x * sn + v.y * c);
  let spiral = pivot + n * rad + radius * rv;
  return mix(pt, spiral, curl * step(0.0, s - 1e-5));
}

// Barnsley fern approximator for organic frond shape
fn fernFrond(p: vec2<f32>, base: vec2<f32>, angle: f32, scale: f32,
             time: f32, bass: f32, mouse: vec2<f32>, attract: f32, unfurl: f32) -> vec4<f32> {
  let ctl = frondControl(base, angle, scale, time, bass, mouse, attract);
  let mid = ctl.mid;
  let bentTip = ctl.tip;
  let growth = ctl.growth;

  // Idea 1: unfurl clips the drawn t-range and sets the curl amount.
  let tEnd = mix(0.35, 1.0, unfurl);
  let curl = 1.0 - unfurl;

  // Quadratic bezier approximation distance
  var d = 999.0;
  let segs = 8u;
  var prevPt = base;
  for (var i = 1u; i <= segs; i = i + 1u) {
    let t = f32(i) / f32(segs) * tEnd * 0.8;
    let pt = bezierPt(base, mid, bentTip, t);
    d = min(d, sdSegment(p, prevPt, pt));
    prevPt = pt;
  }
  // Idea 1: the last 20% of the frond gets its own 8 segments so the crozier
  // coil is a smooth spiral rather than a polygon.
  let tailSegs = 8u;
  for (var j = 1u; j <= tailSegs; j = j + 1u) {
    let t = tEnd * (0.8 + 0.2 * f32(j) / f32(tailSegs));
    let pt = crozierPt(base, mid, bentTip, t, tEnd, curl);
    d = min(d, sdSegment(p, prevPt, pt));
    prevPt = pt;
  }

  let frondWidth = 0.012 * scale * (1.0 + growth * 0.3);
  let frondStr = smoothstepf32(frondWidth, 0.0, d);

  // FIX: early-return bound widened past the leaflet reach (0.04*scale + its
  // soft edge) so leaflets survive where the stem itself has faded out.
  if (d > frondWidth + 0.05 * scale) {
    return vec4<f32>(0.0);
  }

  // Leaflets along the frond
  var leafletStr = 0.0;
  let leafletCount = u32(mix(6.0, 18.0, growth));
  for (var i = 0u; i < leafletCount; i = i + 1u) {
    let lt = (f32(i) + 0.5) / f32(leafletCount);
    let lOneMinusT = 1.0 - lt;
    let lPos = base * (lOneMinusT * lOneMinusT) +
               mid * (2.0 * lOneMinusT * lt) +
               bentTip * (lt * lt);
    let lDir = normalize(bentTip - base);
    let lPerp = vec2<f32>(-lDir.y, lDir.x);
    // Idea 1: leaflets vanish past the clip and shrink into the coil.
    let leafMask = (1.0 - smoothstepf32(tEnd * 0.75, tEnd, lt) * curl) * (1.0 - smoothstepf32(tEnd - 0.02, tEnd, lt));
    let lSize = 0.04 * scale * sin(lt * 3.14159) * growth * leafMask;
    let lTip = lPos + lPerp * lSize * select(-1.0, 1.0, (i % 2u) == 0u);
    let ld = sdSegment(p, lPos, lTip);
    leafletStr = max(leafletStr, smoothstepf32(lSize * 0.15, 0.0, ld));
  }

  // Chromatic: neon magenta core, green mid, cyan edge
  let core = smoothstepf32(frondWidth * 0.4, 0.0, d);
  let edge = smoothstepf32(frondWidth, frondWidth * 0.5, d);
  let r = core * 0.9 + edge * 0.3 + leafletStr * 0.5;
  let g = core * 0.2 + edge * 0.8 + leafletStr * 0.9;
  let b = core * 0.5 + edge * 1.0 + leafletStr * 0.7;

  return vec4<f32>(r, g, b, max(frondStr, leafletStr * 0.7));
}

// ── Idea 2: dew on leaflet tips — the dew points are this frond's leaflet tips
// (same Bezier / leaflet formulas), a hashed fraction of them carrying a drop.
fn leafletDew(p: vec2<f32>, base: vec2<f32>, angle: f32, scale: f32,
              time: f32, bass: f32, mouse: vec2<f32>, attract: f32, unfurl: f32,
              dewFrac: f32, treble: f32, fi: f32) -> f32 {
  if (length(p - base) > scale * 1.4 + 0.25) {
    return 0.0;
  }
  let ctl = frondControl(base, angle, scale, time, bass, mouse, attract);
  let mid = ctl.mid;
  let bentTip = ctl.tip;
  let growth = ctl.growth;
  let tEnd = mix(0.35, 1.0, unfurl);
  let curl = 1.0 - unfurl;
  let lDir = normalize(bentTip - base);
  let lPerp = vec2<f32>(-lDir.y, lDir.x);
  let dewSize = 0.006 + treble * 0.003;
  var dew = 0.0;
  let leafletCount = u32(mix(6.0, 18.0, growth));
  for (var i = 0u; i < leafletCount; i = i + 1u) {
    let lt = (f32(i) + 0.5) / f32(leafletCount);
    let lOneMinusT = 1.0 - lt;
    let lPos = base * (lOneMinusT * lOneMinusT) +
               mid * (2.0 * lOneMinusT * lt) +
               bentTip * (lt * lt);
    let leafMask = (1.0 - smoothstepf32(tEnd * 0.75, tEnd, lt) * curl) * (1.0 - smoothstepf32(tEnd - 0.02, tEnd, lt));
    let lSize = 0.04 * scale * sin(lt * 3.14159) * growth * leafMask;
    let lTip = lPos + lPerp * lSize * select(-1.0, 1.0, (i % 2u) == 0u);
    let hasDrop = step(hash2(vec2<f32>(fi * 3.7 + 1.3, f32(i) * 1.9)), dewFrac) * step(0.004, lSize);
    let dewDist = length(p - lTip);
    let dewTwinkle = sin(time * 4.0 + fi * 3.7 + f32(i) * 1.3) * 0.5 + 0.5;
    dew = max(dew, smoothstepf32(dewSize, 0.0, dewDist) * dewTwinkle * hasDrop);
  }
  return dew;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let growthSpeed = mix(0.2, 1.5, u.zoom_params.x);
  let frondDensity = mix(3.0, 12.0, u.zoom_params.y);
  let dewAmount = mix(0.0, 1.0, u.zoom_params.z);
  // FIX: bipolar without a dead zone — 0 repels, 0.5 is a mild attract, 1 pulls hard.
  let mouseInfluence = mix(-0.7, 1.3, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  // FIX: flip the vertical axis so p.y = -1 is the bottom row (soil) and the
  // mouse lives in the same aspect-corrected, flipped frame.
  var p = vec2<f32>(uv.x * 2.0 - 1.0, -(uv.y * 2.0 - 1.0));
  p.x = p.x * aspect;
  let mouse = vec2<f32>((u.zoom_config.y * 2.0 - 1.0) * aspect, -(u.zoom_config.z * 2.0 - 1.0));

  // Dark soil background with subtle grain
  let soilNoise = noise2(p * 8.0 + vec2<f32>(time * 0.02, 0.0));
  var color = vec3<f32>(0.03, 0.04, 0.02) + vec3<f32>(0.01, 0.008, 0.005) * soilNoise;

  // ═══ Fern Fronds (bass growth; mids feed the soil glow-bed) ═══
  var frondColor = vec4<f32>(0.0);
  let fernCount = u32(frondDensity);
  let growthPhase = fract(time * growthSpeed * 0.1);

  // ── Idea 3: soil glow-bed — each base casts a 1-D gaussian pool of its own
  // hue (blend of the frond palette) onto the soil, brightening as it unfurls.
  var bed = vec3<f32>(0.0);

  for (var i = 0u; i < fernCount; i = i + 1u) {
    let fi = f32(i);
    let fp = fernParams(fi, time, bass, growthPhase);
    let fern = fernFrond(p, fp.base, fp.angle, fp.scale,
                         time, bass, mouse, mouseInfluence, fp.unfurl);
    frondColor = max(frondColor, fern);

    let hueSel = fract(fi * 0.618);
    let fernHue = mix(mix(vec3<f32>(0.9, 0.2, 0.5), vec3<f32>(0.5, 0.9, 0.7), smoothstepf32(0.0, 0.5, hueSel)),
                      vec3<f32>(0.3, 0.8, 1.0), smoothstepf32(0.5, 1.0, hueSel));
    let poolX = (p.x - fp.base.x) / (0.22 * fp.scale);
    let above = max(p.y - fp.base.y, 0.0);
    let poolY = exp(-above * above / 0.004);
    let pool = exp(-poolX * poolX) * poolY * (0.3 + 0.7 * fp.unfurl) * (0.7 + 0.3 * bass + 0.4 * mids);
    bed += fernHue * pool * 0.12;
  }
  color += bed;

  // ═══ Chromatic Dispersion: offset R/G/B samples for glow ═══
  let glowSpread = 0.012 + bass * 0.005;
  let rOff = vec2<f32>(glowSpread, glowSpread * 0.3);
  let gOff = vec2<f32>(-glowSpread * 0.5, glowSpread);
  let bOff = vec2<f32>(glowSpread * 0.3, -glowSpread * 0.7);

  var glowR = 0.0;
  var glowG = 0.0;
  var glowB = 0.0;

  for (var i = 0u; i < fernCount; i = i + 1u) {
    let fi = f32(i);
    let fp = fernParams(fi, time, bass, growthPhase);
    let frR = fernFrond(p + rOff, fp.base, fp.angle, fp.scale,
                        time, bass, mouse, mouseInfluence, fp.unfurl);
    let frG = fernFrond(p + gOff, fp.base, fp.angle, fp.scale,
                        time, bass, mouse, mouseInfluence, fp.unfurl);
    let frB = fernFrond(p + bOff, fp.base, fp.angle, fp.scale,
                        time, bass, mouse, mouseInfluence, fp.unfurl);
    glowR = max(glowR, frR.r * frR.a);
    glowG = max(glowG, frG.g * frG.a);
    glowB = max(glowB, frB.b * frB.a);
  }

  color += vec3<f32>(glowR, glowG, glowB) * 0.4;
  color += frondColor.rgb * frondColor.a;

  // ═══ Dewdrop Sparkles (driven by treble) — Idea 2: on leaflet tips ═══
  var dew = 0.0;
  let dewFrac = clamp(dewAmount + treble * 0.5, 0.0, 1.0);
  for (var i = 0u; i < fernCount; i = i + 1u) {
    let fi = f32(i);
    let fp = fernParams(fi, time, bass, growthPhase);
    dew = max(dew, leafletDew(p, fp.base, fp.angle, fp.scale,
                              time, bass, mouse, mouseInfluence, fp.unfurl,
                              dewFrac, treble, fi));
  }

  // Dew with chromatic highlight: cyan center, white hot
  color += vec3<f32>(0.4, 0.9, 1.0) * dew * (0.6 + treble * 0.6);

  // ═══ Temporal Feedback (exact C load; A holds linear pre-ACES colour) ═══
  let prevRaw = textureLoad(dataTextureC, coord, 0);
  let prevRGB = clamp(select(vec3<f32>(0.0), prevRaw.rgb, prevRaw.rgb == prevRaw.rgb), vec3<f32>(0.0), vec3<f32>(16.0));
  let feedbackAmount = 0.025 + bass * 0.008;
  color = mix(color, prevRGB * 0.93, feedbackAmount);

  // ═══ Semantic Alpha ═══
  let presence = clamp(frondColor.a + dew * 0.6, 0.0, 1.0);
  let alpha = clamp(0.06 + presence * 0.94, 0.0, 1.0);

  // Depth: bottom (soil, frond bases) is near; fronds sit slightly in front.
  let depthY = smoothstepf32(-1.0, 1.0, p.y);
  let depth = clamp(0.15 + depthY * 0.55 - frondColor.a * 0.1, 0.0, 1.0);

  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);
  color = max(color, vec3<f32>(0.0));

  textureStore(dataTextureA, coord, vec4<f32>(color, presence));
  let display = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
