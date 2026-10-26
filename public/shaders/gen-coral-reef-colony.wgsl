// ═══════════════════════════════════════════════════════════════════
//  Coral Reef Colony
//  Category: generative
//  Features: coral, organic, generative, audio-reactive, mouse-interactive, semantic-alpha, simulation-like, temporal, upgraded-rgba
//  Complexity: Very High
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (4-Agent Swarm Upgrade)
//  Upgraded: 2026-10-11, 2026-10-25
//  Ideas: coherent forking branches (value-noise fix); C.a skeleton accretion + bleaching memory; star-lobed polyp mouths that retract at the pointer; apical pallor; zooxanthellae speckles; golden-angle corallite field (§12.2E); Beer-Lambert water column (§12.2F); capsule-normal limb roundness + crotch occlusion
//  A packing: A.rgb = ACES display colour (temporal history); A.a = skeleton memory stored as skel*0.9 (NOT display alpha); writeTexture.a = semantic alpha
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// Value noise (smooth, interpolated). The previous fbm summed raw hash21 per pixel,
// so branchNoise/branchAngle were white noise (grain), not branches.
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p + vec2<f32>(0.0, time * 0.01);
  for (var i: i32 = 0; i < 5; i = i + 1) {
    v += a * vnoise(pp + vec2<f32>(f32(i) * 7.3, 0.0));
    pp = pp * 2.1 + vec2<f32>(3.2, 1.7);
    a *= 0.5;
  }
  return v;
}

fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// IDEA 1 helper: distance to a segment, .y = 0..1 position along it (for tip taper).
// .zw = perpendicular offset from the axis (the limb's cross-section normal, Idea 3).
fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec4<f32> {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
  let q = pa - ba * h;
  return vec4<f32>(length(q), h, q);
}

fn limb(d: f32, w: f32) -> f32 {
  return min((1.0 - smoothstep(w * 0.55, w, d)) + 0.3 * (1.0 - smoothstep(w, w * 3.5, d)), 1.0);
}

// IDEA 2 helper: skeleton memory lives in C.a as skel*0.9. Values above 0.9 are foreign
// (e.g. hardcoded alpha 1.0 left by a previous shader) and read as 0; zero-init C reads 0.
fn skelAt(c: vec2<i32>, dim: vec2<i32>) -> f32 {
  let cc = clamp(c, vec2<i32>(0), dim - vec2<i32>(1));
  let a = textureLoad(dataTextureC, cc, 0).a;
  return select(clamp(a, 0.0, 0.9) / 0.9, 0.0, !(a <= 0.9001));
}

// Narkowicz ACES fit. The old Hable-shaped curve had no exposure bias (0.27 -> 0.14),
// which left the default frame at ~0.08 mean luminance.
fn acesToneMap(v: vec3<f32>) -> vec3<f32> {
  let x = max(v, vec3<f32>(0.0));
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn aragoniteColor(density: f32) -> vec3<f32> {
  let pH = mix(7.3, 8.5, clamp(density, 0.0, 1.0));
  let t1 = clamp((pH - 7.5) / 0.5, 0.0, 1.0);
  let t2 = clamp((pH - 8.0) / 0.5, 0.0, 1.0);
  let stressed = vec3<f32>(0.92, 0.9, 0.88);
  let transitional = vec3<f32>(0.95, 0.75, 0.55);
  let healthy = vec3<f32>(0.15, 0.85, 0.6);
  return mix(mix(stressed, transitional, t1), healthy, t2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let growth = u.zoom_params.x;
  let polypSize = u.zoom_params.y;
  let colorVariety = u.zoom_params.z;
  let mouseAttraction = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let aspect = resolution.x / resolution.y;
  let depth = smoothstep(0.0, 1.0, uv.y);

  // IDEA 2: skeleton memory read (exact loads), slight diffusion so accretion spreads.
  let coord = vec2<i32>(global_id.xy);
  let dim = vec2<i32>(resolution);
  let skelC = skelAt(coord, dim);
  let skelN = 0.25 * (skelAt(coord + vec2<i32>(1, 0), dim) + skelAt(coord - vec2<i32>(1, 0), dim)
                    + skelAt(coord + vec2<i32>(0, 1), dim) + skelAt(coord - vec2<i32>(0, 1), dim));
  let skelBlur = mix(skelC, skelN, 0.25);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.5) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let front = abs(length(delta) - age * (0.12 + growth * 0.08));
      clickFront += (1.0 - smoothstep(0.0, 0.025, front)) * (1.0 - age / 3.5);
    }
  }
  clickFront = min(clickFront, 2.0);

  // HEAD floor of 0.6 left the reef near-black when no audio plays (coralDensity ~0.27).
  let nutrient = growth * (0.95 + bass * 0.8);
  let current = vec2<f32>(sin(time * 0.2 + mids * 2.0), cos(time * 0.15 - mids * 1.5)) * 0.3;
  let spawnPulse = step(0.82, treble);

  let colonyUV = uv * 6.0 + current * time * 0.08;
  let branchNoise = fbm(colonyUV, time);
  let branchAngle = branchNoise * 6.2831;

  let nodePos = fract(colonyUV) - 0.5;

  // IDEA 1: each colony cell is a small tree. Trunk angle comes from smooth cell-level noise
  // (neighbours lean alike), sways in the current, forks ~35 deg into two tapering sub-branches.
  // Accreted skeleton (IDEA 2) thickens the limbs.
  let cellId = floor(colonyUV);
  let cellNoise = fbm(cellId * 0.45 + vec2<f32>(2.3, 5.1), time);
  let sway = sin(time * 0.6 + hash21(cellId) * 6.2831 + current.x * 2.0) * 0.07;
  let brDir = vec2<f32>(cos(cellNoise * 6.2831 + sway), sin(cellNoise * 6.2831 + sway));
  let forkAng = 0.61 + (hash21(cellId + vec2<f32>(1.7, 4.3)) - 0.5) * 0.2;
  let girth = 1.0 + 0.5 * skelBlur;
  let rootP = -brDir * 0.44;
  let forkP = brDir * 0.10;
  let tipA = forkP + rot2(brDir, forkAng) * 0.34;
  let tipB = forkP + rot2(brDir, -forkAng) * 0.34;
  let sT = segDist(nodePos, rootP, forkP);
  let sA = segDist(nodePos, forkP, tipA);
  let sB = segDist(nodePos, forkP, tipB);
  let wT = mix(0.085, 0.06, sT.y) * girth;
  let wA = mix(0.06, 0.012, sA.y) * girth;
  let wB = mix(0.06, 0.012, sB.y) * girth;
  let lT = limb(sT.x, wT);
  let lA = limb(sA.x, wA);
  let lB = limb(sB.x, wB);
  let branch = max(lT, max(lA, lB));

  // ── Idea 3: capsule-normal limb roundness + crotch occlusion ─────────
  // The winning limb's perpendicular offset (discarded by HEAD) is the cross-section
  // normal of a round stem: lambert from the upper left makes the flat ribbons round.
  // Where both fork arms are close (the crotch) the light is occluded.
  let useA = lA > lT;
  let qA = select(sT.zw, sA.zw, useA);
  let wQ = select(wT, wA, useA);
  let lQ = select(lT, lA, useA);
  let useB = lB > lQ;
  let qLimb = select(qA, sB.zw, useB) / max(select(wQ, wB, useB) * 1.4, 1e-4);
  let r2 = min(dot(qLimb, qLimb), 1.0);
  let lam = clamp(dot(vec3<f32>(qLimb, sqrt(1.0 - r2)), vec3<f32>(-0.5, -0.55, 0.65) * 1.2), 0.0, 1.0);
  let crotchAO = 1.0 - 0.35 * exp(-(sA.x + sB.x) * 8.0);
  let limbShade = mix(1.0, mix(0.62, 1.22, lam) * crotchAO, smoothstep(0.35, 0.95, branch));
  // HEAD offset the DLA noise by a per-cell hash, which cut every colony tile along a hard
  // square edge; a continuous offset keeps the same scale without the seams.
  let dla = fbm(uv * 12.0 + current * 0.6, time * 0.5);
  let dlaBranch = smoothstep(0.35, 0.7, dla) * nutrient;

  let mousePull = (1.0 - smoothstep(0.0, 0.55, length((uv - mouse) * vec2<f32>(aspect, 1.0)))) * mouseAttraction * (0.35 + held * 0.9);
  let coralDensity = clamp((branch * 0.7 + dlaBranch * 0.5 + spawnPulse * 0.3) * nutrient + mousePull + clickFront * 0.32, 0.0, 1.0);

  // IDEA 2: fed pixels accrete skeleton; it erodes slowly (per-frame rates, not dt based).
  // Where the colony is starved now but skeleton remains, it bleaches to a pale ghost.
  let skelNew = clamp(skelBlur * 0.9992 + smoothstep(0.08, 0.3, coralDensity) * 0.003, 0.0, 1.0);
  let bleach = skelNew * (1.0 - smoothstep(0.05, 0.3, coralDensity));
  let body = max(coralDensity, skelNew * 0.5);

  // IDEA 3 (HEAD): star-lobed polyp mouths. 8 lobes with per-cell phase and sway, a dark mouth pit;
  // lobes retract near the pointer (stronger when held) and extend with treble.
  // ── Idea 1: golden-angle corallite field (§12.2E) ────────────────────
  // HEAD tiled polyps on a square screen lattice (a visible dot grid). Corallites of a
  // real head sit on a Vogel spiral: p_k = R*sqrt((k+.5)/N) at k*137.5 deg, so each colony
  // cell grows its own phyllotactic cluster (and drifts with the colony). The nearest seed
  // supplies polyp-local coordinates in spacing units, so the lobe/mouth maths is unchanged.
  let polypScale = 18.0 + polypSize * 14.0;
  let nSeeds = clamp(floor(polypScale * polypScale / 36.0), 8.0, 28.0);
  let vogelR = 0.40;
  let seedSpacing = vogelR * sqrt(3.14159 / nSeeds);
  let vogelRot = hash21(cellId + vec2<f32>(9.1, 2.7)) * 6.2831;
  var bestD2 = 1e9;
  var bestK = 0.0;
  var bestP = vec2<f32>(0.0);
  // Seeds step by a constant 137.5 deg turn, so rotate (cos, sin) by a recurrence instead of
  // calling cos/sin 28 times per pixel.
  let ga = vec2<f32>(cos(2.39996), sin(2.39996));
  var dirK = vec2<f32>(cos(vogelRot), sin(vogelRot));
  for (var k = 0; k < 28; k = k + 1) {
    let kf = f32(k);
    let sp = vogelR * sqrt((kf + 0.5) / nSeeds) * dirK;
    dirK = vec2<f32>(dirK.x * ga.x - dirK.y * ga.y, dirK.x * ga.y + dirK.y * ga.x);
    let dv = nodePos - sp;
    let d2 = select(1e9, dot(dv, dv), kf < nSeeds);
    let better = d2 < bestD2;
    bestD2 = select(bestD2, d2, better);
    bestK = select(bestK, kf, better);
    bestP = select(bestP, sp, better);
  }
  let polypGrid = (nodePos - bestP) / seedSpacing;
  let polypDist = length(polypGrid);
  let polypPh = hash21(vec2<f32>(bestK, cellId.x * 1.7 + cellId.y * 3.1)) * 6.2831;
  let polypAng = atan2(polypGrid.y, polypGrid.x);
  let nearPtr = 1.0 - smoothstep(0.0, 0.3, length((uv - mouse) * vec2<f32>(aspect, 1.0)));
  let retract = nearPtr * clamp(mouseAttraction, 0.0, 1.0) * (0.45 + held * 0.4);
  let extend = clamp(1.0 + treble * 0.45 - retract * 0.8, 0.3, 1.5);
  let lobe = 1.0 + 0.3 * cos(8.0 * polypAng + polypPh + sin(time * 0.7 + polypPh) * 0.5);
  let mouthR = polypSize * 0.5 * lobe * extend;
  let polyp = (1.0 - smoothstep(mouthR * 0.16, mouthR, polypDist)) * coralDensity;
  let mouthPit = 1.0 - smoothstep(mouthR * 0.05, mouthR * 0.2, polypDist);

  let caustics = abs(sin(uv.x * 40.0 + time * 0.6) + sin(uv.y * 35.0 - time * 0.4)) * 0.5;
  let causticLight = caustics * (0.15 + depth * 0.25) * (1.0 + treble * 0.5);

  let hue = fract(uv.x * 0.35 + uv.y * 0.25 + time * 0.015 + colorVariety * 0.6 + mids * 0.12);
  var coral = vec3<f32>(
    0.5 + 0.5 * sin(hue * 6.28),
    0.25 + 0.55 * sin(hue * 6.28 + 2.2),
    0.35 + 0.65 * sin(hue * 6.28 + 4.1)
  );
  coral = mix(coral, vec3<f32>(0.1, 0.9, 0.7), spawnPulse * 0.4);
  coral = mix(coral, aragoniteColor(mix(coralDensity, 0.0, bleach)), 0.4 + 0.5 * bleach);
  // Apical pallor — the fork tips are paler than the trunk.
  let tipProx = exp(-min(length(nodePos - tipA), length(nodePos - tipB)) * 14.0) * coralDensity;
  coral = mix(coral, vec3<f32>(0.86, 0.95, 0.82), tipProx * 0.55);
  // Zooxanthellae speckles — green dots in living tissue, gone where it has bleached.
  let zoo = step(0.78, hash21(floor(uv * 90.0))) * coralDensity * (1.0 - bleach);
  coral = mix(coral, vec3<f32>(0.12, 0.52, 0.1), zoo * 0.7);

  let sss = smoothstep(0.0, 0.4, body) * 0.35;
  var color = coral * (body * 0.8 * limbShade + polyp * 1.4 * (1.0 - 0.45 * mouthPit) + sss);

  let bloom = polyp * vec3<f32>(0.6, 1.0, 0.8) * (0.5 + bass * 0.6);
  color += bloom * 0.6;
  color += vec3<f32>(0.1, 0.3, 0.5) * causticLight;
  color += vec3<f32>(0.15, 1.0, 0.72) * clickFront * (0.25 + treble * 0.6);

  let sparkle = pow(abs(sin(caustics * 12.0 + time * 2.0 + branchNoise * 30.0)), 20.0) * 1.68 * coralDensity;
  color += vec3<f32>(0.7, 0.9, 1.0) * sparkle * 0.2;

  let waterTint = vec3<f32>(0.02, 0.08, 0.14);
  let depthAtten = mix(0.25, 0.85, depth);
  // ── Idea 2: Beer-Lambert water column (§12.2F) ───────────────────────
  // HEAD only greyed the colour toward waterTint. Water absorbs red first: T = exp(-sigma*z)
  // per channel, z from the same depth that already dims the reef (top of frame = deep), and
  // the absorbed light returns as a blue-green in-scatter veil (energy moved, not lost).
  let column = 0.1 + 1.2 * (1.0 - depth);
  let trans = exp(-vec3<f32>(0.75, 0.26, 0.10) * column);
  color = color * trans;
  let veil = vec3<f32>(0.02, 0.10, 0.16) * (1.0 - trans) * 0.6;
  color = mix(waterTint * depthAtten + veil, color, clamp(body + polyp * 0.5, 0.0, 1.0));

  let biolum = polyp * (0.4 + bass * 0.5);
  let semantic_alpha = clamp(body * (0.25 + biolum) * depthAtten + clickFront * 0.2, 0.05, 0.98);

  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  color = acesToneMap(color * (1.0 + bass * 0.25));

  let prev = textureLoad(dataTextureC, coord, 0);
  let decay = 0.96;
  let temporal = mix(prev.rgb * decay, color, 0.25);
  color = temporal;

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
  // A.rgb = display colour history; A.a = skeleton memory (skel*0.9), NOT display alpha.
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, skelNew * 0.9));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(body * depthAtten, 0.0, 0.0, 0.0));
}
