// ═══════════════════════════════════════════════════════════════════
//  Fabric Zipper - Image Effect with Textile and Metal Materials
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28, 2026-11-09
//  Ideas: lit 2/1 twill weave (diagonal ribs + warp crowns, frequency = Weave Frequency, slides with each flap); rolled tape lips (opening edges curl back: roll highlight then dark underside, soft contact shadow cast onto the revealed image); interlocking tooth chain (left/right teeth staggered half a pitch, heads mesh across the closed seam, reveal scallop follows the teeth); lit brass/steel hardware (barrel teeth + dome slider, Blinn + Fresnel-Schlick rim §12.2F, contact shadows); twin lockstitch rows following the tape edge; tape bunching at the slider (chevron folds bend the twill and its normal)
//  A packing: display RGBA (post-ACES colour + HEAD fabric/metal transmission alpha); C not read
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Material Properties
const FABRIC_ALPHA: f32 = 0.82;           // Woven fabric base transparency
const SEAM_ALPHA: f32 = 0.95;             // Seams are more opaque
const METAL_ALPHA: f32 = 0.98;            // Metal teeth are nearly opaque
const FABRIC_DENSITY: f32 = 2.5;          // Thread density
const PI: f32 = 3.14159265;
const TOOTH_HALF: f32 = 0.015;            // tooth band half-width on the tape side of the cut edge (edge_dist units)
const TOOTH_REACH: f32 = 0.012;           // Idea 1: how far a tooth head crosses the cut edge toward the gap
const BRASS_F0: vec3<f32> = vec3<f32>(0.78, 0.58, 0.25);   // Idea 2: Fresnel-Schlick F0 of the brass teeth
const STEEL_F0: vec3<f32> = vec3<f32>(0.56, 0.57, 0.58);   // Idea 2: ... and of the steel slider body
const SLIDER_R: f32 = 0.0325;             // slider disc radius (aspect-corrected, canvas-height units)
const STITCH_ROW0: f32 = 0.038;           // Idea 3: stitch rows sit beyond the rolled lip, measured from the MEAN tape edge
const STITCH_ROW1: f32 = 0.052;           //   (plus the scallop amplitude once the zipper is open, so they clear the spikes)
const STITCH_HALF: f32 = 0.0026;          // Idea 3: half thread width
const FOLD_FREQ: f32 = 38.0;              // Idea 4: bunching fold frequency (cycles per canvas height)
const FOLD_AMP: f32 = 0.0018;             // Idea 4: fold height (canvas-height units)
const TAU: f32 = 6.2831853;
// Key light from the upper-left, toward the viewer (screen y points down).
const LIGHT_DIR: vec3<f32> = vec3<f32>(-0.4523, -0.5528, 0.7035);

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Last-pass Idea 1 — Twill weave height field.
// 2/1 twill: each warp thread floats over two picks and under one, stepping one thread per
// pick, so the floats line up into diagonal ribs with a 3-thread repeat. p is in thread units.
// Returns (height 0..1, dh/dp.x, dh/dp.y). ribFade/threadFade band-limit sub-pixel detail.
fn twillRib(p: vec2<f32>, ribFade: f32, threadFade: f32) -> vec3<f32> {
    let t = fract((p.x + p.y) / 3.0);
    let q = 2.0 * t - 1.0;
    // flat-topped rib (the 2-pick float) with a narrow groove (the 1-pick sink)
    let hRib = 1.0 - q * q * q * q;
    let dRib = -8.0 * q * q * q / 3.0;             // d(hRib)/dp.x == d(hRib)/dp.y
    // rounded warp-thread crowns across the rib
    let fx = fract(p.x);
    let hThr = sin(PI * fx);
    let dThr = PI * cos(PI * fx);
    let h = mix(0.5, hRib, ribFade) * 0.8 + 0.2 * mix(0.5, hThr, threadFade);
    let gx = dRib * ribFade * 0.8 + 0.2 * dThr * threadFade;
    let gy = dRib * ribFade * 0.8;
    return vec3<f32>(h, gx, gy);
}

// Calculate fabric alpha with weave pattern (weavePattern now comes from the twill height)
fn calculateFabricAlpha(weavePattern: f32, isSeam: bool, isTeeth: bool) -> f32 {
    if (isTeeth) {
        return METAL_ALPHA;
    }

    if (isSeam) {
        // Seams have tighter weave = more opaque
        return SEAM_ALPHA;
    }

    // Fabric weave creates varying opacity (ribs opaque, grooves let a little image through)
    let weaveAlpha = mix(FABRIC_ALPHA * 0.9, FABRIC_ALPHA, weavePattern);

    // Thread density affects opacity
    let densityAlpha = exp(-FABRIC_DENSITY * 0.2);
    let finalAlpha = mix(weaveAlpha, weaveAlpha * 0.9, densityAlpha * 0.3);

    return clamp(finalAlpha, 0.65, 0.92);
}

// Fabric SSS for textile areas
fn fabricSSS(baseColor: vec3<f32>, noiseVal: f32) -> vec3<f32> {
    // Fabric has soft diffusion from thread gaps
    let threadTint = vec3<f32>(0.95, 0.95, 0.98);
    let scattered = mix(baseColor, baseColor * threadTint, noiseVal * 0.15);
    return scattered;
}

// ── Idea 1: one tooth of one chain, in its own (across-edge, along-chain) coordinates.
// e = signed distance to this flap's cut edge (+ = onto the tape), ph = along-chain phase (one tooth per
// unit). The tooth is a rounded block anchored on the tape (e = +TOOTH_HALF) whose head reaches
// TOOTH_REACH past the cut edge. Duty is 0.5 so the opposite chain (half a pitch later) fits between.
// Returns (coverage, a, b) with a, b = -1..1 across / along the tooth. fe / ff are one pixel in e / phase.
fn toothBarrel(e: f32, ph: f32, fe: f32, ff: f32) -> vec3<f32> {
    let ec = 0.5 * (TOOTH_HALF - TOOTH_REACH);
    let hw = 0.5 * (TOOTH_HALF + TOOTH_REACH);
    let a = (e - ec) / hw;
    let b = (fract(ph) - 0.5) * 4.0;
    let r = pow(pow(abs(a), 3.0) + pow(abs(b), 3.0), 1.0 / 3.0);   // rounded-rectangle superellipse
    let fw = max(fe / hw, ff * 4.0);                                // pixel footprint in tooth units
    let cov = 1.0 - smoothstep(1.0 - fw, 1.0 + fw, r);
    return vec3<f32>(cov, clamp(a, -1.0, 1.0), clamp(b, -1.0, 1.0));
}

// ── Idea 2: shared metal shading for teeth and slider. Diffuse + Blinn highlight from the SAME key
// light as the twill, plus a Fresnel-Schlick grazing rim (view = +z): F = F0 + (1 - F0)(1 - cos)^5.
fn metalShade(n: vec3<f32>, albedo: vec3<f32>, f0: vec3<f32>) -> vec3<f32> {
    let nn = normalize(n);
    let diff = max(dot(nn, LIGHT_DIR), 0.0) / LIGHT_DIR.z;
    let hv = normalize(LIGHT_DIR + vec3<f32>(0.0, 0.0, 1.0));
    let spec = pow(max(dot(nn, hv), 0.0), 48.0);
    let grazing = 1.0 - clamp(nn.z, 0.0, 1.0);
    let fres = f0 + (vec3<f32>(1.0) - f0) * pow(grazing, 5.0);
    return albedo * (0.38 + 0.8 * diff) + fres * (0.75 * spec + 0.3 * grazing);
}

// ── Idea 3: one row of lockstitch dashes. e = edge_dist, s = distance along the cut edge, pitch =
// stitches per canvas height. Returns (thread coverage, thread shading, groove darkness beside it).
fn stitchRow(e: f32, s: f32, row: f32, fe: f32, pitch: f32) -> vec3<f32> {
    let u = (e - row) / STITCH_HALF;
    let v = (fract(s * pitch) - 0.5) * 2.0 / 0.62;                 // 62 % dash duty
    let r = pow(pow(abs(u), 2.5) + pow(abs(v), 2.5), 0.4);         // capsule-ish: rounded caps
    let fw = max(fe / STITCH_HALF, 0.35);
    let cov = 1.0 - smoothstep(1.0 - fw, 1.0 + fw, r);
    let shade = 0.55 + 0.45 * sqrt(max(1.0 - u * u, 0.0));         // round thread cross-section
    let groove = (1.0 - smoothstep(1.0, 3.5, r)) * (1.0 - cov);
    return vec3<f32>(cov, shade, groove);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Parameters
  let teeth_size = mix(20.0, 100.0, u.zoom_params.x);
  let opening_width = mix(0.1, 1.0, u.zoom_params.y);
  let weave_freq = mix(40.0, 320.0, u.zoom_params.z);   // threads per unit canvas height

  // Mouse
  let mouse = u.zoom_config.yz;
  let aspect = u.config.z / u.config.w;

  // Zipper Logic
  let dx = (uv.x - mouse.x) * aspect;
  let dy = uv.y - mouse.y;

  var width = 0.0;
  if (dy < 0.0) {
      width = -dy * opening_width;
  }
  // HEAD fix: how far the zipper has actually parted here. 0 below the slider, so the
  // closed chain no longer leaks a jagged strip (or a seam-wide sliver) of image.
  let openF = smoothstep(0.0, 0.02, width);

  // ── IDEA 1: interlocking chain ──────────────────────────────────
  // The two chains sit half a pitch apart. The cut-edge scallop of the right flap is the left one
  // flipped (sin(x + pi) = -sin(x)) and both are locked to the tooth phase: each tooth is centred where
  // its own flap's edge is narrowest, so the opening follows the teeth. (HEAD used 6.28 not 2*pi, which
  // drifted the scallop ~0.2 pitch down the page relative to the teeth.)
  let tooth_amp = mix(0.0, 0.1, u.zoom_params.w);
  let scallop = tooth_amp * openF * sin(TAU * uv.y * teeth_size);
  let jwL = width + scallop;
  let jwR = width - scallop;
  let eL = -dx - jwL;                                    // signed distance to the left flap's cut edge
  let eR = dx - jwR;                                     // ... and to the right flap's
  let edge_dist = select(eL, eR, dx > 0.0);

  // Mask
  let mask = (1.0 - smoothstep(0.0, 0.01, edge_dist)) * openF;

  // Zipper Slider (The Metal Piece)
  let slider_dist = distance(vec2<f32>((uv.x - mouse.x) * aspect, uv.y), vec2<f32>(0.0, mouse.y));
  let slider_mask = 1.0 - smoothstep(0.03, 0.035, slider_dist);

  // Fabric Texture with noise
  let noise_val = noise(uv * 50.0);
  var fabric_col = vec3<f32>(0.1, 0.1, 0.15) + vec3<f32>(noise_val * 0.05);

  // Apply fabric SSS
  fabric_col = fabricSSS(fabric_col, noise_val);

  // ── IDEA 4: tape bunching at the slider ─────────────────────────
  // The slider forces the tape through its throat, so the cloth gathers into chevron folds that point
  // at it (phase = along-chain distance + 0.8*|across|), strongest just below the slider and fading out
  // as a Gaussian (e-fold ~0.17 canvas heights along the chain, 0.13 across; still ~12 % at 0.25 below).
  // The folds travel with the slider. The fold bends the threads (weave phase) and tilts the twill normal.
  let pinchV = vec2<f32>(dx / 0.13, dy / 0.17);
  let pinchEnv = exp(-dot(pinchV, pinchV));
  let foldPh = (abs(dx) * 0.8 + dy) * FOLD_FREQ;
  let foldS = sin(TAU * foldPh);
  let foldC = cos(TAU * foldPh);
  let foldSlope = pinchEnv * foldC * TAU * FOLD_FREQ * FOLD_AMP;           // d(height)/d(phase direction)
  let foldTilt = vec2<f32>(0.8 * select(-1.0, 1.0, dx >= 0.0) * foldSlope, foldSlope);

  // ── IDEA 1 (last pass): lit twill weave ─────────────────────────
  // Flap-local coords: each flap is pulled sideways by the opening, so its weave slides with it.
  let flapX = dx - sign(dx) * width;
  var tp = vec2<f32>(flapX, uv.y) * weave_freq;
  tp.y = tp.y + pinchEnv * foldS * FOLD_AMP * weave_freq;                  // Idea 4: threads bend through the fold
  let cellPx = f32(dims.y) / weave_freq;
  let ribFade = smoothstep(1.5, 4.0, cellPx * 2.12);    // rib period = 3 threads / sqrt(2)
  let threadFade = smoothstep(2.5, 6.0, cellPx);
  let tw = twillRib(tp, ribFade, threadFade);
  let twN = normalize(vec3<f32>(-tw.y * 0.45 - foldTilt.x, -tw.z * 0.45 - foldTilt.y, 1.0));
  let twDiff = max(dot(twN, LIGHT_DIR), 0.0) / LIGHT_DIR.z;   // 1.0 on flat cloth
  let twAO = mix(0.6, 1.0, tw.x) * mix(1.0, 0.6, pinchEnv * 0.5 * (1.0 - foldS));   // grooves + fold troughs sit in shadow
  let twHalf = normalize(LIGHT_DIR + vec3<f32>(0.0, 0.0, 1.0));
  let twSheen = pow(max(dot(twN, twHalf), 0.0), 24.0) * 0.06 * tw.x;
  fabric_col = fabric_col * (0.35 + 0.75 * twDiff) * twAO + vec3<f32>(0.85, 0.88, 1.0) * twSheen;

  // Add a seam line
  let seam = 1.0 - smoothstep(0.0, 0.005, abs(dx));
  let isSeam = seam * step(0.0, dy) > 0.5;
  var fabric_final = mix(fabric_col, vec3<f32>(0.05), seam * step(0.0, dy));

  // ── IDEA 2 (last pass, part a): rolled tape lips ────────────────
  // Just outside the tooth band the cut edge curls back on itself: a half-cylinder whose
  // normal swings from facing the viewer (joins flat cloth) through a lit roll crown to the
  // dark underside at the lip. Band width grows with the opening.
  let lipW = min(0.008 + 0.1 * width, 0.03);
  let edgeN = normalize(vec2<f32>(sign(dx), opening_width)); // grad(edge_dist): into the flap
  let lipT = clamp((edge_dist - TOOTH_HALF * 0.8) / lipW, 0.0, 1.0);
  let lipTheta = (1.0 - lipT) * 2.2;                                    // 0 = flat, >pi/2 = underside
  let lipNrm = vec3<f32>(-edgeN * sin(lipTheta), cos(lipTheta));
  let lipDiff = max(dot(lipNrm, LIGHT_DIR), 0.0) / LIGHT_DIR.z;
  let lipCrown = pow(max(dot(lipNrm, twHalf), 0.0), 16.0) * 0.22 * (1.0 - lipT);
  let lipUnder = 1.0 - 0.7 * smoothstep(1.3, 2.1, lipTheta);
  let lipShaded = fabric_final * (0.3 + 0.7 * lipDiff) * lipUnder + vec3<f32>(0.9, 0.9, 1.0) * lipCrown;
  fabric_final = mix(fabric_final, lipShaded, openF * step(0.0, edge_dist));

  // ── IDEA 3: twin lockstitch rows ────────────────────────────────
  // Two dashed thread rows clamp the chain onto each flap's tape. They run parallel to the MEAN tape
  // edge (|dx| - width: the straight seam below the slider, the slanted V above it) at a fixed offset
  // beyond the lip, pushed out by the scallop amplitude once the zipper is open so they clear the
  // cut-edge spikes. One stitch per tooth pitch; the twill groove beside each thread is darkened.
  let fe = 1.0 / f32(dims.y);                                 // one pixel in edge_dist units
  // Along-tape coordinate is anchored to the canvas (uv.y), exactly like the teeth and the twill, so
  // dragging the slider never makes the stitches crawl against the chain (a slider-relative tangent did).
  let sAlong = uv.y;
  let eMean = abs(dx) - width;
  let rowShift = tooth_amp * openF;
  let st0 = stitchRow(eMean, sAlong, STITCH_ROW0 + rowShift, fe, teeth_size);
  let st1 = stitchRow(eMean, sAlong, STITCH_ROW1 + rowShift, fe, teeth_size);
  let onTape = (1.0 - mask) * smoothstep(0.0, 0.01, eMean);
  let stitchCov = max(st0.x, st1.x) * onTape;
  let threadShade = select(st1.y, st0.y, st0.x >= st1.x);
  let threadCol = vec3<f32>(0.58, 0.56, 0.50) * (0.65 + 0.35 * threadShade);
  fabric_final = fabric_final * (1.0 - 0.45 * max(st0.z, st1.z) * onTape);
  fabric_final = mix(fabric_final, threadCol, stitchCov);

  // Image Texture
  var img_col = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // ── IDEA 2 (last pass, part b): contact shadow of the rolled lip on the revealed image ──
  // The key light comes from the left, so the left flap throws a wider shadow across the gap.
  let shadowW = (0.006 + 0.06 * width) * (1.0 - 0.6 * sign(dx));
  let lipShadow = exp(-max(-edge_dist, 0.0) / max(shadowW, 1e-4)) * 0.6 * openF;
  img_col = img_col * (1.0 - lipShadow);

  // Metal Color
  let metal_col = vec3<f32>(0.7, 0.7, 0.8) + vec3<f32>(noise_val * 0.1);

  // Teeth Color (Gold/Silver)
  let tooth_col = vec3<f32>(0.6, 0.5, 0.2);

  // Final Mix
  var final_col = mix(fabric_final, img_col, mask);

  // ── IDEA 1 + 2: the tooth chain ─────────────────────────────────
  // Left chain centred where the left edge is narrowest (phase -0.25), right chain half a pitch later.
  let ffPhase = teeth_size / f32(dims.y);                     // one pixel in tooth-phase units
  let phL = uv.y * teeth_size - 0.25;
  let phR = uv.y * teeth_size + 0.25;
  let tL = toothBarrel(eL, phL, fe, ffPhase);
  let tR = toothBarrel(eR, phR, fe, ffPhase);

  // Teeth throw a short soft shadow (light from the upper left) onto whatever they sit on.
  let shiftX = 0.004;
  let shiftY = 0.005 * teeth_size;                            // in phase units (5/1000 of the height)
  let shL = toothBarrel(eL + shiftX, phL - shiftY, fe * 3.0, ffPhase * 3.0);
  let shR = toothBarrel(eR - shiftX, phR - shiftY, fe * 3.0, ffPhase * 3.0);
  let toothShadow = max(shL.x, shR.x) * 0.5 * (1.0 - max(tL.x, tR.x));
  final_col = final_col * (1.0 - toothShadow);

  // Slider contact shadow on the tape / image, then the teeth, then the slider.
  let sliderShadowD = length(vec2<f32>(dx - 0.006, dy - 0.009));
  final_col = final_col * (1.0 - 0.5 * (1.0 - smoothstep(SLIDER_R - 0.004, SLIDER_R + 0.016, sliderShadowD)));

  // Each tooth is a small barrel: normal from its own (a, b), brass material (tooth_col is the albedo).
  let toothAO = vec2<f32>(1.0 - 0.35 * smoothstep(0.55, 1.0, max(abs(tL.y), abs(tL.z))),
                          1.0 - 0.35 * smoothstep(0.55, 1.0, max(abs(tR.y), abs(tR.z))));
  let nL = vec3<f32>(-tL.y * 0.8, tL.z * 0.8, max(0.35, sqrt(max(1.0 - 0.6 * (tL.y * tL.y + tL.z * tL.z), 0.0))));
  let nR = vec3<f32>(tR.y * 0.8, tR.z * 0.8, max(0.35, sqrt(max(1.0 - 0.6 * (tR.y * tR.y + tR.z * tR.z), 0.0))));
  let shadeL = metalShade(nL, tooth_col, BRASS_F0) * toothAO.x;
  let shadeR = metalShade(nR, tooth_col, BRASS_F0) * toothAO.y;
  final_col = mix(final_col, shadeL, tL.x);
  final_col = mix(final_col, shadeR, tR.x);
  let teethCov = max(tL.x, tR.x);
  let isTeeth = teethCov > 0.5;

  // Draw Slider: a lit steel dome with a pull-tab post hole (HEAD: flat grey disc).
  let sA = vec2<f32>(dx, dy) / (SLIDER_R + 0.002);
  let sR2 = dot(sA, sA);
  let nS = vec3<f32>(sA.x * 0.9, sA.y * 0.9, max(0.25, sqrt(max(1.0 - sR2, 0.0))));
  var sliderCol = metalShade(nS, metal_col, STEEL_F0);
  let postHole = 1.0 - smoothstep(0.0075, 0.0095, slider_dist);
  sliderCol = mix(sliderCol, vec3<f32>(0.03), postHole * 0.85);
  let isSlider = slider_mask > 0.5;
  final_col = mix(final_col, sliderCol, slider_mask);

  // Calculate material alpha
  let materialAlpha = calculateFabricAlpha(tw.x, isSeam, isTeeth || isSlider);

  // Blend alpha: fabric allows some image through, metal is opaque; thread is a touch more opaque
  var finalAlpha = mix(materialAlpha, 1.0, mask * 0.7);
  finalAlpha = max(finalAlpha, mix(finalAlpha, SEAM_ALPHA, stitchCov * (1.0 - mask)));

  let outCol = vec4<f32>(aces(max(final_col, vec3<f32>(0.0))), finalAlpha);
  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
