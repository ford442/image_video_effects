// ═══════════════════════════════════════════════════════════════════
//  audio-voronoi-gabor
//  Category: advanced-hybrid
//  Features: audio-reactive, voronoi, gabor-texture, displacement-mapping,
//            mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Chunks From: audio-voronoi-displacement (audio Voronoi cells,
//               displacement), conv-gabor-texture-analyzer (oriented
//               texture detection, 4-orientation filter bank)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
//  Upgraded: 2026-11-09
//  Ideas: grain-lit cell membranes (F2−F1 wall embossed and lit along the Gabor texture orientation: walls facing the grain brighten, walls across it darken, walls parallel to the grain glow); rigid cell translation (displacement direction uses the Gabor orientation sampled at the cell's own seed, so each cell slides as one plate and tears only at its membrane)
//  A packing: display RGBA (ACES) + semantic alpha; C is not read
// ═══════════════════════════════════════════════════════════════════
//  Audio-reactive Voronoi displacement modulated by Gabor texture
//  analysis. Gabor responses detect local texture orientation and
//  strength, which rotate and scale Voronoi cell displacement.
//  Edges and textured regions displace differently than smooth areas.
//
//  Audio is plasmaBuffer[0].xyz (bass/mids/treble). Silence = no audio
//  terms; the cells keep a slow breathing floor (IDLE_*) so the picture
//  is a living mosaic at rest, never a strobe.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Gabor bank constants (unchanged from the analyser chunk)
const GABOR_FREQ: f32 = 0.15;
const GABOR_SIGMA: f32 = 2.5;
const GABOR_R: i32 = 4;               // min(ceil(3σ), 4)
// Silence floor: slow, per-cell breathing — feeds cell wander / displacement only
const IDLE_WANDER: vec3<f32> = vec3<f32>(0.5, 0.4, 0.0);
const IDLE_DISP: f32 = 0.3;
// Bounds for the unnormalised Gabor strength (HEAD let it run past 1 and past a whole cell)
const SEED_SHIFT_CAP: f32 = 0.35;     // max Gabor shift of a seed, in cells
const STRENGTH_CAP: f32 = 3.0;

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hash22 (from gen_grid.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: Gabor bank on a SHARED tap grid ═══
// HEAD ran four gaborResponse() calls (4 × 81 filtered loads, 324 exp, 324 cos). The
// Gaussian is rotation-invariant (same σ on both axes) and separable, and the four
// sinusoids only depend on x, y, (x+y)/√2 and (x−y)/√2 — so one 9×9 luma grid plus three
// small tables gives the identical four responses.
struct GaborTables {
  cx: array<f32, 9>,    // cos(2πf·d), d = -4..4          (θ = 0° with x, θ = 90° with y)
  cd: array<f32, 17>,   // cos(2πf·s/√2), s = -8..8       (θ = 45° with x+y, θ = 135° with x−y)
  ge: array<f32, 5>,    // exp(-d²/(2σ²+0.001)), d = 0..4 (Gaussian factor per axis)
};

fn makeGaborTables() -> GaborTables {
  var t: GaborTables;
  let w = 2.0 * 3.14159265 * GABOR_FREQ;
  let inv2s = 1.0 / (2.0 * GABOR_SIGMA * GABOR_SIGMA + 0.001);
  for (var i = 0; i < 9; i = i + 1) { t.cx[i] = cos(w * f32(i - GABOR_R)); }
  for (var j = 0; j < 17; j = j + 1) { t.cd[j] = cos(w * f32(j - 8) * 0.70710678); }
  for (var k = 0; k < 5; k = k + 1) { t.ge[k] = exp(-f32(k * k) * inv2s); }
  return t;
}

// returns (r0, r45, r90, r135)
fn gaborBank(uv: vec2<f32>, pixelSize: vec2<f32>, t: GaborTables) -> vec4<f32> {
  var r0 = 0.0;
  var r45 = 0.0;
  var r90 = 0.0;
  var r135 = 0.0;
  for (var dy = -GABOR_R; dy <= GABOR_R; dy = dy + 1) {
    for (var dx = -GABOR_R; dx <= GABOR_R; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
      let g = luma * t.ge[abs(dx)] * t.ge[abs(dy)];
      r0 = r0 + g * t.cx[dx + GABOR_R];
      r90 = r90 + g * t.cx[dy + GABOR_R];
      r45 = r45 + g * t.cd[dx + dy + 8];
      r135 = r135 + g * t.cd[dx - dy + 8];
    }
  }
  return vec4<f32>(r0, r45, r90, r135);
}

// dominant orientation (radians) and texture strength from a bank result (HEAD's definitions)
fn bankAngle(r: vec4<f32>) -> f32 {
  return atan2(r.y + r.w - r.x - r.z, r.x + r.y - r.z - r.w);
}
fn bankStrength(r: vec4<f32>) -> f32 {
  return (abs(r.x) + abs(r.y) + abs(r.z) + abs(r.w) + 0.001) * 0.5;
}

// ═══ VORONOI WITH AUDIO & GABOR ═══
struct Vor {
  d1: f32,
  d2: f32,
  cellId: vec2<f32>,
  anchor: vec2<f32>,   // uv of the nearest cell's *unshifted* seed — stable per cell
  p1: vec2<f32>,       // nearest / second-nearest seed, cell-local
  p2: vec2<f32>,
};

fn voronoiAudioGabor(p: vec2<f32>, cellSize: f32, wander: vec3<f32>, gaborOrient: f32, gaborStrength: f32, time: f32) -> Vor {
  let i = floor(p * cellSize);
  let f = fract(p * cellSize);
  var v: Vor;
  v.d1 = 1000.0;
  v.d2 = 1000.0;
  let bassMod = wander.x * 0.3;
  let midMod = wander.y * 0.2;
  // Gabor influence: rotate cell centers by texture orientation (shift bounded to stay in the 3×3 window)
  let gaborRot = vec2<f32>(cos(gaborOrient), sin(gaborOrient)) * (SEED_SHIFT_CAP * tanh(min(gaborStrength * 0.3 / SEED_SHIFT_CAP, 8.0)));  // soft cap: slope 0.3 at 0, saturates at the cap, slider stays live
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let cell = i + neighbor;
      let base = hash22(cell);
      var hashVal = base + vec2<f32>(
        sin(time * (1.0 + base.x) + cell.x * 0.5) * bassMod,
        cos(time * (1.0 + base.y) + cell.y * 0.5) * midMod
      );
      hashVal = hashVal + gaborRot;
      let point = neighbor + hashVal;
      let dist = length(point - f);
      if (dist < v.d1) {
        v.d2 = v.d1;
        v.p2 = v.p1;
        v.d1 = dist;
        v.p1 = point;
        v.cellId = cell;
        v.anchor = (cell + base) / cellSize;
      } else if (dist < v.d2) {
        v.d2 = dist;
        v.p2 = point;
      }
    }
  }
  return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let pixelSize = 1.0 / resolution;

  // Parameters
  let cellCount = mix(5.0, 30.0, u.zoom_params.x);
  let audioReact = u.zoom_params.y * 2.0;
  let displacement = mix(0.0, 0.1, u.zoom_params.z);
  let gaborInfluence = u.zoom_params.w * 2.0;

  // Mouse interaction
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let distToMouse = length(uv - mousePos);
  let mouseGravity = 1.0 - smoothstep(0.0, 0.25, distToMouse);
  let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 35.0 - time * 7.0) * exp(-distToMouse * 5.0);

  // ═══ AUDIO BANDS (R1: real audio; silence is silence) ═══
  let audioBands = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  // ═══ GABOR TEXTURE ANALYSIS (shared tap grid) ═══
  let tables = makeGaborTables();
  let bankPix = gaborBank(uv, pixelSize, tables);
  let dominantAngle = bankAngle(bankPix);
  let textureStrength = bankStrength(bankPix);

  // ═══ VORONOI WITH TEXTURE-AWARE DISPLACEMENT ═══
  let wander = max(audioBands * audioReact, IDLE_WANDER);
  let gaborStrength = textureStrength * gaborInfluence;
  let vor = voronoiAudioGabor(uv, cellCount, wander, dominantAngle, gaborStrength, time);
  let dist1 = vor.d1;
  let dist2 = vor.d2;
  // R6: stable per-cell hash (HEAD hashed the pixel-shifted, time-wandering seed, so the
  // per-cell tints flickered per pixel and per frame)
  let cellHash = hash12(vor.cellId);

  // Cell boundary
  let gap = dist2 - dist1;
  let edge = smoothstep(0.05, 0.15, gap);

  // ── Idea 2: rigid cell translation ─────────────────────────────
  // The orientation that steers a cell's displacement is read where the cell *is* (its
  // seed), not per pixel: the whole cell slides as one plate and tears only at its wall.
  let bankSeed = gaborBank(clamp(vor.anchor, vec2<f32>(0.0), vec2<f32>(1.0)), pixelSize, tables);
  let seedAngle = bankAngle(bankSeed);
  let seedStrength = bankStrength(bankSeed);
  let seedG = min(seedStrength * gaborInfluence, STRENGTH_CAP);
  let toCenter = vec2<f32>(cos(cellHash * 6.28 + seedAngle * gaborInfluence), sin(cellHash * 6.28 + seedAngle * gaborInfluence));
  let breath = 0.5 + 0.5 * sin(time * 0.9 + cellHash * 6.28318);
  let dispDrive = max(audioBands.x, IDLE_DISP * breath);
  let audioDisplacement = toCenter * dispDrive * displacement * (1.0 + seedG);

  // Cursor displacement
  let cursorDisplacement = normalize(uv - mousePos + 0.001) * mouseGravity * 0.05 + clickPulse * 0.03;
  let displacedUV = clamp(uv + audioDisplacement + cursorDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));

  // Sample image at displaced position
  var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Gabor-color mapping per cell
  let gaborColor = vec3<f32>(
    0.5 + 0.5 * cos(dominantAngle + 0.0),
    0.5 + 0.5 * cos(dominantAngle + 2.09),
    0.5 + 0.5 * cos(dominantAngle + 4.18)
  );

  // Color based on frequency bands per cell
  let freqColor = vec3<f32>(
    audioBands.x * cellHash * 1.5,
    audioBands.y * fract(cellHash * 1.618) * 1.5,
    audioBands.z * fract(cellHash * 2.618) * 1.5
  );

  // Blend: base + audio freq + Gabor texture color (R3: mix factor bounded; HEAD extrapolated past 1)
  color = mix(color, color * (1.0 + freqColor), audioReact * 0.5);
  color = mix(color, color * gaborColor, clamp(gaborStrength * 0.3, 0.0, 1.0));
  color *= (1.0 + mouseGravity * 0.5);

  // ── Idea 1: grain-lit cell membranes ───────────────────────────
  // The wall between two cells is a ridge (F2−F1 → 0). Its slope points along p2−p1 (toward
  // the neighbour across the wall), opposite on the two sides, so lighting it from the
  // texture-grain direction embosses each wall: one face brightens, the other darkens; a wall
  // running parallel to the grain also catches a crest glint. Strength follows the grain's
  // own strength at the seed, so smooth regions keep quiet walls.
  let ridge = 1.0 - smoothstep(0.0, 0.18, gap);
  let slopeAmt = 4.0 * ridge * (1.0 - ridge);
  let nW = v2norm((vor.p2 - vor.p1) * resolution);   // cell space → pixel space (aspect-correct)
  let grain = vec2<f32>(cos(seedAngle), sin(seedAngle));
  let lit = dot(nW, grain);
  let gate = 0.25 + 0.75 * (seedG / STRENGTH_CAP);
  let parallel = 1.0 - abs(lit);
  color = color * (1.0 + 0.45 * lit * slopeAmt * gate);
  color = color + vec3<f32>(0.85, 0.9, 1.0) * ridge * ridge * parallel * gate * 0.22;

  // Cell edge glow
  let edgeGlow = (1.0 - edge) * audioBands.y * 0.5;
  color += vec3<f32>(edgeGlow * 0.8, edgeGlow * 0.6, edgeGlow);
  color += vec3<f32>(mouseGravity * 0.3, mouseGravity * 0.2, mouseGravity * 0.4);

  // Treble sparkle (R6: per cell, stepped clock; HEAD hashed cellId.x only, so whole columns flashed)
  let sparkle = step(0.95, hash12(vor.cellId + vec2<f32>(floor(time * 6.0) * 7.13, 3.7))) * audioBands.z;
  color += vec3<f32>(sparkle);

  // R4: display ACES (HEAD only clamped to 0..2)
  let finalColor = aces(max(color, vec3<f32>(0.0)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = mix(0.7, 1.0, clamp(audioBands.x * audioReact + edgeGlow + min(textureStrength, STRENGTH_CAP) * 0.2, 0.0, 1.0));

  textureStore(writeTexture, id, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, id, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - audioBands.x * 0.1), 0.0, 0.0, 0.0));
}

// safe normalize for the wall direction (p1 == p2 only before any neighbour is found)
fn v2norm(a: vec2<f32>) -> vec2<f32> {
  return a / max(length(a), 1e-5);
}
