// ═══════════════════════════════════════════════════════════════════
//  Aurora Borealis Loom
//  Category: generative
//  Features: generative, audio-reactive, temporal, chromatic, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28, 2026-11-21
//  Ideas: fell line + reed beat-up; slub yarn light pools; pulsating aurora patches; plain-weave over/under interlacement (the under thread is occluded at each crossing); selvedge hem on every curtain edge (doubled warp ends, picks turn back as beads, only on woven cloth)
//  A packing: raw HDR RGB (pre-ACES, pre-CA) + semantic alpha, read back as the advected peak-hold trail; ACES on writeTexture only (HEAD stored post-ACES display RGBA and re-read it as HDR energy)
// ═══════════════════════════════════════════════════════════════════
//  Aurora curtains woven like fabric on a celestial loom. Bass swells the
//  weave and drives the reed beat, mids shift hue, treble adds ion beads
//  and streaks. Mouse pulls the fabric. Curtain Flow also advances the fell.

#include "_prelude.wgsl"

const PI = 3.14159265;
const TAU = 6.2831853;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v += a * noise2(p * f);
    a *= 0.5;
    f *= 2.01;
  }
  return v;
}

// Aurora curtain SDF
// returns (curtain, selvedge ridge)
fn auroraCurtain(uv: vec2<f32>, xPos: f32, width: f32, time: f32, speed: f32) -> vec2<f32> {
  // (Rescue) period-1 distance in x. The conveyor adds an unbounded offset to uv.x while the
  // curtains sit at fixed x in [0.15, 0.87], so at HEAD every curtain scrolled off the left edge
  // after ~6 s and never came back. Wrapping the distance makes the cloth loop forever; it is
  // identical to HEAD whenever |uv.x - xPos| < 0.5.
  let dx = fract(uv.x - xPos + 0.5) - 0.5;
  // Curtain waves
  let wave1 = sin(uv.y * 4.0 + time * speed + xPos * 3.0) * 0.08;
  let wave2 = sin(uv.y * 7.0 - time * speed * 0.7 + xPos * 5.0) * 0.04;
  let wave3 = sin(uv.y * 2.5 + time * speed * 0.3) * 0.12;
  let curtainEdge = dx - wave1 - wave2 - wave3;
  let curtain = smoothstep(width, 0.0, abs(curtainEdge));
  // Vertical fade
  let vFade = smoothstep(0.0, 0.3, uv.y) * smoothstep(1.0, 0.7, uv.y);
  // ── Idea 5: selvedge hem ──────────────────────────────────────────────────────────
  // A cloth strip's edge is a self-finished selvedge: the outer warp ends are doubled and the
  // weft turns back there. |curtainEdge| was already computed and thrown away; a thin ridge at
  // 0.8 half-widths marks it (independent of the soft glow, which is only ~10% there).
  let selvedge = smoothstep(width * 0.18, 0.0, abs(abs(curtainEdge) - width * 0.8));
  return vec2<f32>(curtain * vFade, selvedge * vFade);
}

// Weft thread pattern
fn weftPattern(uv: vec2<f32>, density: f32, time: f32) -> f32 {
  let threadY = fract(uv.y * density);
  let thread = smoothstep(0.15, 0.0, abs(threadY - 0.5));
  // Slight weave offset per row
  let row = floor(uv.y * density);
  let offset = sin(row * 1.7 + time * 0.2) * 0.02;
  let threadX = fract(uv.x * density + offset);
  let crossThread = smoothstep(0.12, 0.0, abs(threadX - 0.5));
  return max(thread, crossThread * 0.6);
}

// Warp thread pattern
fn warpPattern(uv: vec2<f32>, density: f32, time: f32) -> f32 {
  let threadX = fract(uv.x * density);
  let col = floor(uv.x * density);
  let offset = sin(col * 2.3 + time * 0.15) * 0.02;
  let threadY = fract(uv.y * density + offset);
  let warp = smoothstep(0.1, 0.0, abs(threadX - 0.5));
  let weftCross = smoothstep(0.12, 0.0, abs(threadY - 0.5));
  return max(warp, weftCross * 0.5);
}

// Ionization nodes (beads of light)
fn ionizationNodes(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  var nodes = 0.0;
  let nodeCount = 6;
  for (var i: i32 = 0; i < nodeCount; i = i + 1) {
    let fi = f32(i);
    let nx = fi / f32(nodeCount) + sin(time * 0.4 + fi * 2.1) * 0.08;
    let ny = 0.3 + sin(time * 0.3 + fi * 1.3) * 0.15 + fbm2(vec2<f32>(fi, time * 0.1), 2) * 0.1;
    let nPos = vec2<f32>(nx, ny);
    let d = length(vec2<f32>(fract(uv.x - nPos.x + 0.5) - 0.5, uv.y - nPos.y));   // (rescue) periodic in x
    let flash = step(0.7, sin(time * 3.0 + fi * 4.7) * 0.5 + 0.5) * intensity;
    nodes += exp(-d * d * 300.0) * flash;
  }
  return nodes;
}

fn hueToRGB(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 2 — Slub yarn: hand-spun thickness along one thread (1-D noise along
// the thread, independent per row/column lane). 0 = spun thin, 1 = thick slub.
fn slubAmount(along: f32, lane: f32) -> f32 {
  let n = noise2(vec2<f32>(along, lane * 17.0)) * 0.65
        + noise2(vec2<f32>(along * 2.3 + 5.0, lane * 17.0 + 3.0)) * 0.35;
  return smoothstep(0.42, 0.78, n);
}

// Idea 2 — one thread whose half-width swells with its slub (0.7x .. 2.2x base).
fn slubThread(across: f32, baseWidth: f32, slub: f32) -> f32 {
  let w = baseWidth * (0.7 + 1.5 * slub);
  return smoothstep(w, 0.0, abs(fract(across) - 0.5));
}

// Idea 3 — Pulsating aurora: each patch cell blinks on its own quasi-period
// (3..12 s) and phase; on/off shaped like real pulsating aurora.
fn cellPulse(cell: vec2<f32>, time: f32) -> f32 {
  let h1 = hash21(cell + vec2<f32>(13.7, 5.1));
  let h2 = hash21(cell + vec2<f32>(2.3, 41.9));
  let period = 3.0 + 9.0 * h1;
  let s = 0.5 + 0.5 * sin(TAU * (time / period + h2));
  return smoothstep(0.3, 0.8, s);
}

// Idea 3 — soft cellular patches: smooth blend of the four nearest cell pulses.
fn pulsatingPatches(p: vec2<f32>, time: f32) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(cellPulse(i, time), cellPulse(i + vec2<f32>(1.0, 0.0), time), w.x),
    mix(cellPulse(i + vec2<f32>(0.0, 1.0), time), cellPulse(i + vec2<f32>(1.0, 1.0), time), w.x),
    w.y
  );
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
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv01 = vec2<f32>(gid.xy) / res;
  var uv = uv01;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let weaveDensity = u.zoom_params.x * 20.0 + 8.0;
  let hueSpeed = u.zoom_params.y * 0.5 + 0.05;
  let ionization = u.zoom_params.z;
  let curtainFlow = u.zoom_params.w * 0.55 + 0.25;
  let warpT = time + 0.4 * sin(time * 0.29);

  // Mouse pulls the fabric (warps UV toward mouse)
  let mouseDist = length(uv01 - mouse);
  let pullStrength = exp(-mouseDist * mouseDist * 4.0) * 0.08;
  uv += (mouse - uv01) * pullStrength;
  // Curtain conveyor scroll — closed-form horizontal transport.
  uv.x += warpT * curtainFlow * 0.35;
  uv.y += sin(warpT * 0.8 + uv.x * 4.0) * curtainFlow * 0.04;

  // Vertical ion drift streaks racing along curtains.
  var ionStreaks = 0.0;
  for (var si = 0; si < 5; si++) {
    let fs = f32(si);
    let lane = fract(hash21(vec2<f32>(fs, 2.1)) + warpT * curtainFlow * (0.4 + fs * 0.05));
    let streakX = lane;
    // (Rescue) x distance is periodic so the streaks keep crossing the scrolled frame.
    ionStreaks += exp(-abs(fract(uv.x - streakX + 0.5) - 0.5) * 120.0) *
                    exp(-abs(uv.y - fract(warpT * 0.5 + fs * 0.17)) * 80.0) * treble * ionization;
  }

  // Bass swells the weave width
  let swell = 1.0 + bass * 0.5;

  // Multiple aurora curtains
  var curtains = 0.0;
  var curtainCol = vec3<f32>(0.0);
  var selvedgeCol = vec3<f32>(0.0);
  let numCurtains = 5;
  for (var i: i32 = 0; i < numCurtains; i = i + 1) {
    let fi = f32(i);
    let xPos = 0.15 + fi * 0.18 + sin(time * curtainFlow + fi * 1.3) * 0.06;
    let width = (0.04 + fi * 0.005) * swell;
    let cs = auroraCurtain(uv, xPos, width, warpT, curtainFlow * 4.5 + 0.35);
    let c = cs.x;

    // Mids shift hue through spectrum per curtain
    let hue = fract(fi * 0.15 + time * hueSpeed + mids * 0.2);
    let cCol = hueToRGB(hue);
    curtains += c;
    curtainCol += cCol * c;
    selvedgeCol += mix(cCol, vec3<f32>(1.0), 0.35) * cs.y;   // Idea 5: selvedge ridge, hue of its curtain
  }

  // Normalize curtain color
  curtainCol = select(curtainCol / max(curtains, 0.001), vec3<f32>(0.0), curtains < 0.001);

  // Idea 3 — Pulsating aurora patches ride the curtain conveyor (scrolled uv).
  let patchLvl = pulsatingPatches(uv * vec2<f32>(6.0, 4.0), time);
  let patchGain = mix(0.5, 1.3, patchLvl);

  // Weave pattern overlay (HEAD functions, verbatim)
  let weft = weftPattern(uv, weaveDensity, time);
  let warp = warpPattern(uv, weaveDensity * 0.8, time);

  // Idea 2 — Slub yarn: per-row weft slubs along x, per-column warp slubs along y.
  let warpDensity = weaveDensity * 0.8;
  let sWeft = slubAmount(uv.x * weaveDensity * 0.25, floor(uv.y * weaveDensity));
  let sWarp = slubAmount(uv.y * warpDensity * 0.25 + 50.0, floor(uv.x * warpDensity));
  let weftSlub = slubThread(uv.y * weaveDensity, 0.15, sWeft);
  let warpSlub = slubThread(uv.x * warpDensity, 0.10, sWarp);
  let thinWeft = mix(0.7, 1.0, sWeft);
  let thinWarp = mix(0.7, 1.0, sWarp);

  // Idea 1 — Fell line: the cloth ends at a fell that advances down the frame
  // with Curtain Flow and wraps. fellD = how far above the fell this row is
  // (0 = newest pick). Rows within 0.7 of the frame above it are woven; below
  // it only bare warp threads are strung.
  let reedPhase = fract(time * 0.9);
  let reedBeat = exp(-reedPhase * 7.0);                 // sharp attack per beat
  let fellY = fract(warpT * curtainFlow * 0.07) + reedBeat * 0.004;
  let fellD = fract(fellY - uv.y);
  let woven = smoothstep(0.8, 0.7, fellD);
  let fellDist = min(fellD, 1.0 - fellD);

  // ── Idea 4: plain-weave interlacement ────────────────────────────────────────────
  // HEAD's cloth was a lattice of lines (max of weft and warp). In a real plain weave each
  // crossing cell has exactly one thread OVER and one UNDER, alternating like a checkerboard
  // (row + column parity). A thread that passes under is hidden across the whole span of that
  // cell and re-surfaces in the gaps, so each thread reads as alternating dashes. Same rows and
  // columns as the slub lanes above; no new noise.
  let overWeft = f32((i32(floor(uv.y * weaveDensity)) + i32(floor(uv.x * warpDensity))) & 1);
  let underSpanX = smoothstep(0.5, 0.15, abs(fract(uv.x * warpDensity) - 0.5));   // dips at a column centre
  let underSpanY = smoothstep(0.5, 0.15, abs(fract(uv.y * weaveDensity) - 0.5));  // dips at a row centre
  let weftOcc = 1.0 - 0.8 * underSpanX * (1.0 - overWeft);   // weft under -> hidden by the warp
  let warpOcc = 1.0 - 0.8 * underSpanY * overWeft;           // warp under -> hidden by the weft
  let wovenWeave = max(max(weft * thinWeft * weftOcc, warp * 0.7 * thinWarp * warpOcc),
                       max(weftSlub * weftOcc, warpSlub * 0.7 * warpOcc));
  let bareWarp = smoothstep(0.1, 0.0, abs(fract(uv.x * warpDensity) - 0.5)) * thinWarp;
  let bareWeave = max(bareWarp, warpSlub) * 0.7;
  let weave = mix(bareWeave, wovenWeave, woven);

  // Weave glow tinted by curtain color
  var weaveCol = curtainCol * weave * 0.5;
  // Idea 2 — aurora light pools in the thick slubs.
  let pool = weftSlub * sWeft * woven + warpSlub * sWarp * 0.7;
  weaveCol += curtainCol * pool * curtains * patchGain * 0.6;

  // Idea 1 — Reed beat-up: bright compaction band on the newest pick, stronger on bass.
  let band = exp(-(fellDist * fellDist) / (0.012 * 0.012));
  let bandCol = mix(vec3<f32>(0.5, 0.82, 1.0), curtainCol, clamp(curtains * 2.0, 0.0, 1.0)) * 0.8
              + vec3<f32>(0.2);
  let reedGlow = bandCol * band * (0.12 + 0.55 * reedBeat) * (1.0 + 1.5 * bass);

  // Idea 5 — selvedge: finished edge only exists on woven cloth (below the fell the weft is
  // absent); the weft turning back shows as a bead at every pick.
  let pickBead = 0.5 + 0.5 * smoothstep(0.35, 0.0, abs(fract(uv.y * weaveDensity) - 0.5));
  let selvedgeLit = selvedgeCol * woven * pickBead * patchGain * 0.4;

  // Ionization nodes from treble
  let nodes = ionizationNodes(uv, time, treble * ionization);
  let nodeCol = vec3<f32>(0.9, 0.95, 1.0) * nodes * (1.0 + ionization);

  // Starfield background
  let starNoise = hash21(floor(uv * 200.0));
  let stars = step(0.995, starNoise) * hash21(floor(uv * 200.0) + vec2<f32>(1.0, 0.0));
  let bg = vec3<f32>(0.02, 0.03, 0.06) + vec3<f32>(0.6, 0.7, 0.9) * stars * 0.5;

  // Combine
  var col = bg;
  col += curtainCol * curtains * 0.8 * patchGain;          // Idea 3
  col += weaveCol * swell;
  col += nodeCol;
  col += vec3<f32>(0.4, 0.85, 1.0) * ionStreaks * 0.6;
  col += reedGlow;                                         // Idea 1
  col += selvedgeLit;                                      // Idea 5

  // Atmospheric noise
  let atmos = fbm2(uv * 4.0 + time * 0.05, 3) * 0.1;
  col += vec3<f32>(0.1, 0.2, 0.3) * atmos * curtains * patchGain;

  // Advected HDR curtain trails (textureLoad only, bounded).
  let flowDir = vec2<f32>(curtainFlow * 0.5, sin(warpT * 0.6) * 0.2);
  let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
  let histCoord = clamp(vec2<i32>(gid.xy) - vec2<i32>(flowDir * (3.0 + curtainFlow * 5.0)), vec2<i32>(0), maxCoord);
  let prev = textureLoad(dataTextureC, histCoord, 0).rgb;
  // (Rescue) HEAD summed `col + prev*0.85` with `prev` = the previous frame's POST-ACES display
  // colour and then ran ACES again inside the loop. ACES's toe slope is > 1 above x ~ 0.1, so the
  // loop was bistable: frame 1 is a dark sky (mean luma 0.08) and by frame ~12 every pixel had
  // ratcheted to a flat 0.74 grey. A now stores the raw HDR value and the trail is a peak-hold
  // (`max`) with the same advection and the same 0.85 + 0.03*bass decay: static cloth converges
  // to its own frame-1 look, moving light still leaves the advected tail.
  var fbCol = clamp(max(col, prev * (0.85 + bass * 0.03)), vec3<f32>(0.0), vec3<f32>(5.5));

  // Semantic alpha: based on curtain intensity and weave presence
  let alpha = clamp(curtains * 0.8 * patchGain + weave * 0.3 + nodes * 0.5 + band * 0.3, 0.0, 1.0);

  // Depth: curtains in front, stars behind
  let depth = clamp(0.8 - curtains * 0.5 + weave * 0.1, 0.0, 1.0);

  // A = raw HDR trail (pre-CA, pre-ACES); ACES and the chromatic tint only on the displayed value.
  textureStore(dataTextureA, gid.xy, vec4<f32>(fbCol, alpha));

  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  var disp = max(vec3<f32>(fbCol.r + caStr, fbCol.g, fbCol.b - caStr * 0.5), vec3<f32>(0.0));   // (rescue) never negative into ACES
  disp = acesToneMap(disp * 1.1);
  textureStore(writeTexture, gid.xy, vec4<f32>(disp, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
