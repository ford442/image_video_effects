// ================================================================
//  Glass Shatter
//  Category: distortion
//  Features: mouse-driven, chromatic-aberration, audio-reactive, upgraded-rgba,
//            click-reactive, held-drag, bounded-click-ripples, voronoi-facets, fresnel, aces,
//            stress-birefringence, crack-propagation, semantic-alpha, depth-aware, temporal-state
//  Complexity: Medium
//  Chunks From: glass-shatter
//  Created: 2026-05-30
//  By: Copilot
//  Upgraded: 2026-11-09
//  Ideas: impact fragmentation gradient (shards shrink toward the press/click point, radial wedges); fracture hairlines on the real shard borders that catch the lamp and flare with the click front; photoelastic stress fringes (sin^2(pi*retardation/lambda) at 650/550/450 nm) along the cracks
//  Rescued: did not compile (`let target` reserved); held spring lived in extraBuffer[133..134] (zeroed every frame, race) -> A texels; C ghost mixed pre-ACES -> display space; alpha saturated at 1.0 by a luma term; click front now aspect-corrected; every click-age term (front, fragmentation envelope) reaches exactly 0 at the 3 s cutoff and the warp centre blends press and click points (no lattice snap)
//  A packing: ACES display RGBA in A and writeTexture. Texel (0,0) = (held pos, held vel, fract(lastTime), 0.7371 sentinel) is STATE in A only (top-left pixel; writeTexture is unaffected), masked when C is read as colour history.
// ================================================================

#include "_prelude.wgsl"
// zoom_params: x=ShardSize, y=Displacement, z=Edge, w=Aberration

struct VoronoiResult {
  dist: f32,
  id: vec2<f32>,
  center: vec2<f32>,
  seedHash: vec2<f32>,  // hash22(id): the seed jitter, reused as the per-shard random
  border: f32,          // distance to the nearest shard border, in cell units
  bnormal: vec2<f32>,   // border normal (nearest seed -> second-nearest seed)
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
  let g = floor(uv * scale);
  let f = fract(uv * scale);
  // Two nearest seeds, tracked branch-free (the nested if/else-if cost ~half of the Idea 2 overhead in the
  // SwiftShader JIT). Ties resolve as at HEAD: the first seed in scan order wins.
  var d1 = 8.0;
  var d2 = 8.0;
  var p1 = vec2<f32>(0.0);
  var p2 = vec2<f32>(0.0);
  var best = vec2<f32>(0.0);

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let lattice = vec2<f32>(f32(x), f32(y));
      let p = lattice + hash22(g + lattice) - f;
      let d = dot(p, p);
      let first = d < d1;
      let second = d < d2;
      p2 = select(select(p2, p, second), p1, first);
      d2 = select(select(d2, d, second), d1, first);
      p1 = select(p1, p, first);
      d1 = select(d1, d, first);
      best = select(best, lattice, first);
    }
  }

  var res: VoronoiResult;
  res.id = g + best;
  res.seedHash = hash22(res.id);
  res.center = (res.id + res.seedHash) / scale;
  // Exact distance from this pixel to the bisector of the two nearest seeds.
  let span = p2 - p1;
  let invLen = inverseSqrt(max(dot(span, span), 1e-8));
  res.bnormal = span * invLen;
  res.border = max(dot(0.5 * (p1 + p2), span) * invLen, 0.0);
  res.dist = sqrt(d1);
  return res;
}

// Idea 1 helpers: radial lattice warp r' = R * (r / R)^q about the impact point.
// q = 1 is the identity (HEAD lattice); q < 1 packs small shards around the impact
// and lets them grow (radially elongated) with distance.
const IMPACT_R: f32 = 0.5;
const SENT: f32 = 0.7371;
const FRINGE_PX: f32 = 9.0;                         // photoelastic bands end here (sigma remapped to 0)
const SIGMA_CUT: f32 = 0.076426;                    // exp(-9 / 3.5)
const SIGMA_NORM: f32 = 1.082751;                    // 1 / (1 - SIGMA_CUT)
const LAMP_XY: vec2<f32> = vec2<f32>(-0.624695, 0.780869);   // normalize(lightDir.xy), lightDir = (-0.4, 0.5, 0.8)

fn fragWarp(p: vec2<f32>, c: vec2<f32>, q: f32) -> vec3<f32> {
  let d = p - c;
  let r = max(length(d), 1e-4);
  let rr = IMPACT_R * pow(r / IMPACT_R, q);
  return vec3<f32>(c + d * (rr / r), clamp(rr / r, 0.5, 4.0));
}

fn fragUnwarp(p: vec2<f32>, c: vec2<f32>, q: f32) -> vec2<f32> {
  let d = p - c;
  let rr = max(length(d), 1e-4);
  let r = IMPACT_R * pow(rr / IMPACT_R, 1.0 / q);
  return c + d * (r / rr);
}

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let mouse = u.zoom_config.yz;
  let isDown = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioPulse = bass * 0.50 + mid * 0.30 + treble * 0.20;

  let time = u.config.x;

  // ── Held-pressure envelope in one A texel (rescue R2) ──────────────
  // HEAD kept this spring in extraBuffer[133..134] written by thread (0,0): the buffer is re-uploaded zeroed
  // every frame and the other threads read it in the same dispatch, so `heldState` was ~0/racy in the app.
  // Texel (0,0) = (pos, vel, fract(lastTime), SENT) — one texel, one load per pixel. Every thread integrates the
  // same step from the stored state; the sentinel guards the first frame / an inherited C.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stateOk = abs(st0.w - SENT) < 0.001;
  let heldTarget = select(0.0, 1.0, isDown);
  var hPos = select(0.0, st0.x, stateOk);
  var hVel = select(0.0, st0.y, stateOk);
  let springDt = select(0.016, clamp(fract(time - st0.z), 0.001, 0.05), stateOk);
  hVel = hVel + (150.0 * (heldTarget - hPos) - 12.0 * hVel) * springDt;   // HEAD's tension / damping
  hPos = clamp(hPos + hVel * springDt, -0.5, 1.5);
  // f16 rest-snap: a spring stored in rgba16float stalls short of its target with a residual velocity
  let settled = abs(heldTarget - hPos) < 0.004 && abs(hVel) < 0.06;
  hPos = select(hPos, heldTarget, settled);
  hVel = select(hVel, 0.0, settled);
  let heldState = hPos;
  let heldK = clamp(heldState, 0.0, 1.0);

  let shardScale = u.zoom_params.x * 20.0 + 3.0;
  let displacement = u.zoom_params.y * 0.42;
  let edge = u.zoom_params.z;
  let aberration = u.zoom_params.w * 0.05 + treble * 0.015;

  // Click fronts (bounded, aspect-corrected; HEAD measured in raw uv -> elliptical off 1:1).
  // The same loop finds the freshest click: it is the impact point while the glass is not pressed.
  var clickFront = 0.0;
  var impactK = 0.0;
  var impactPos = mouse;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
    let ripple = u.ripples[rippleIndex];
    let rippleAge = max(time - ripple.z, 0.0);
    if (rippleAge < 3.0) {
      // Every click-age term is faded to exactly 0 at the 3 s cutoff (HEAD's front and the fragmentation
      // envelope were still ~0.03 / ~0.006 there, so the lattice / front stepped once, 3 s after each click).
      let ageFade = 1.0 - smoothstep(2.0, 3.0, rippleAge);
      let front = abs(distance(uv * aspectVec, ripple.xy * aspectVec) - rippleAge * (0.24 + bass * 0.12));
      clickFront += exp(-front * 125.0) * exp(-rippleAge * 1.7) * ageFade;
      // Fragmentation envelope: 0.1 s attack, full crush zone to 0.3 s, then an even smoothstep relaxation that
      // reaches exactly 0 (with zero slope) at 3 s — no frame-to-frame lattice snap at either end.
      let fresh = smoothstep(0.0, 0.10, rippleAge) * (1.0 - smoothstep(0.3, 3.0, rippleAge));
      impactPos = select(impactPos, ripple.xy, fresh >= impactK && fresh > 0.0);   // newest click wins ties
      impactK = max(impactK, fresh);
    }
  }
  clickFront = min(clickFront, 2.0);

  // ── Idea 1: impact fragmentation gradient ───────────────────────────
  // Struck glass does not break uniformly: fragments are tiny at the impact and grow outward in radial
  // wedges. While pressed (spring envelope) and ~2 s after a click the lattice is warped about the impact
  // point; at rest k = 0 and this is HEAD's lattice exactly.
  let fragK = max(heldK, impactK);
  // The warp centre blends press point and click point by their envelopes (a hard switch jumped the whole
  // lattice when a decaying click envelope dropped below the held one).
  let impactC = (impactPos * impactK + mouse * heldK) / max(impactK + heldK, 1e-4);
  let warpQ = 1.0 - 0.5 * fragK;
  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let impactA = impactC * aspectVec;
  var warped = vec3<f32>(aspectUV, 1.0);
  if (fragK > 0.002) { warped = fragWarp(aspectUV, impactA, warpQ); }   // fragK is uniform: idle frames skip the pow()s
  let v = voronoi(warped.xy, shardScale);
  var shardCenter = v.center;
  if (fragK > 0.002) { shardCenter = fragUnwarp(v.center, impactA, warpQ); }

  let mouseVec = shardCenter - vec2<f32>(mouse.x * aspect, mouse.y);
  let mouseDist = length(mouseVec);
  let repelDir = select(vec2<f32>(0.0), mouseVec / max(mouseDist, 0.0001), mouseDist > 0.0001);
  let repelZone = 1.0 - smoothstep(0.0, 0.6, mouseDist);
  let repelMask = repelZone * mix(0.18, 1.0, heldState);

  let shardHash = v.seedHash;
  let shardPhase = dot(shardHash, vec2<f32>(5.3, 8.7)) * 6.2831853;
  let shardRunner = pow(max(0.0, sin(shardPhase + length(shardCenter - vec2<f32>(0.5)) * 34.0 - time * (12.0 + mid * 7.0))), 12.0);
  let edgeRunner = pow(max(0.0, sin(v.dist * 72.0 + shardPhase - time * (17.0 + treble * 8.0))), 18.0);
  let offset = repelDir * (repelMask * (displacement + audioPulse * 0.06) + clickFront * 0.055);
  let randBase = shardHash - 0.5;
  let randOffset = randBase * (0.005 + max(displacement, 0.08) * 0.025);
  let finalUV = clamp(uv - offset - randOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let tiltVec = offset + randOffset;
  let tiltLen = length(tiltVec);
  let shardTilt = select(vec2<f32>(0.0, 0.0), tiltVec / max(tiltLen, 0.0001), tiltLen > 0.0001);
  let sampleDir = select(vec2<f32>(1.0, 0.0), shardTilt, tiltLen > 0.0001);
  let normal = normalize(vec3<f32>(shardTilt * (1.5 + audioPulse), 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let cosTheta = max(dot(viewDir, normal), 0.0);
  let fresnel = 0.04 + (1.0 - 0.04) * pow(1.0 - cosTheta, 5.0);
  let edgeHighlight = pow(1.0 - cosTheta, 3.0) * (0.25 + edge * 0.75) + edgeRunner * (0.08 + treble * 0.28);

  let thickness = 0.04 + (1.0 - clamp(v.dist, 0.0, 1.0)) * 0.08 + edge * 0.04;
  let density = 0.70 + edge * 1.50;
  let glassTint = mix(vec3<f32>(0.90, 0.97, 1.00), vec3<f32>(1.0, 0.82, 0.55), audioPulse * 0.35);
  let absorption = exp(-(1.0 - glassTint) * thickness * density);
  let transmission = clamp((1.0 - fresnel) * dot(absorption, vec3<f32>(0.33333334)), 0.08, 0.98);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + sampleDir * aberration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - sampleDir * aberration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var finalColor = vec3<f32>(r, g, b) * absorption;

  let lightDir = normalize(vec3<f32>(-0.4, 0.5, 0.8));
  let specular = pow(max(dot(lightDir, normal), 0.0), 20.0) * (0.20 + 0.40 * edge + 0.30 * treble);
  finalColor = finalColor + glassTint * edgeHighlight * 0.25 + vec3<f32>(specular);
  finalColor += vec3<f32>(0.58, 0.82, 1.0) * shardRunner * (0.04 + mid * 0.18) +
                vec3<f32>(1.0, 0.72, 0.35) * clickFront * 0.16;

  // ── Fracture network on the true shard borders ──────────────────────
  // Widths are held in pixels (cell units scale with the shard count and with the Idea 1 warp).
  let pxPerCell = resolution.y / shardScale;
  let borderPx = v.border * pxPerCell / warped.z;           // approx. pixels to the border
  // ── Idea 2: fracture lines that catch the light ─────────────────────
  // A fracture face is a tiny mirror: it flashes when its normal faces the lamp, burns brighter in the
  // pressed zone, and flares amber where the click front is passing (crack propagation made visible).
  // The hairline is <= 1.8 px wide and the stress fringes are remapped to reach exactly 0 at FRINGE_PX, so
  // the hairline work runs on a thin line and the fringe work only in the band next to a border.
  var crackLine = 0.0;
  if (borderPx < FRINGE_PX) {
    let lineW = mix(0.7, 1.8, edge);
    crackLine = 1.0 - smoothstep(0.0, lineW, borderPx);
    if (crackLine > 0.0) {
      let facing = abs(dot(v.bnormal, LAMP_XY));
      let catchLamp = 0.35 + 0.65 * facing * facing;
      let crackHot = 1.0 + 1.1 * repelZone * heldK + 2.2 * clickFront;
      let crackTint = mix(glassTint, vec3<f32>(1.0, 0.72, 0.35), clamp(clickFront, 0.0, 1.0));
      finalColor += crackTint * crackLine * (0.06 + 0.30 * edge) * catchLamp * crackHot;
    }

    // ── Idea 3: photoelastic stress fringes along the cracks ──────────
    // Residual stress is concentrated at the fracture and grows with the load (how hard the shard has been
    // pushed). The retardation D(nm) = Dmax * stress makes per-wavelength fringes I = sin^2(pi*D/lambda)
    // (650/550/450 nm) in bands that fade away from the crack, like a polariscope view of fractured glass.
    let load = clamp(tiltLen * 7.0, 0.0, 1.0);
    let stress = 0.25 + 0.75 * load + 0.25 * audioPulse;
    let sigma = max(exp(-borderPx * (1.0 / 3.5)) - SIGMA_CUT, 0.0) * SIGMA_NORM;   // 1 at the crack, 0 at FRINGE_PX
    let retard = 720.0 * sigma * stress;
    let phase = retard * (3.14159265 / vec3<f32>(650.0, 550.0, 450.0));
    let ringS = sin(phase);
    let fringe = ringS * ringS;
    finalColor += fringe * (0.11 + 0.20 * edge) * sigma;
  }

  // The photoelastic bands are dark-field on the clear plate: keep the sum finite and non-negative.
  finalColor = max(finalColor, vec3<f32>(0.0));
  let tonemapped = aces_tonemap(finalColor);

  // C holds ACES display colour: ghost it in display space (HEAD mixed it before the tone map), and never
  // read the state texel as colour. A pressed-glass ghost only, as at HEAD.
  let isStateTexel = pixel.y == 0 && pixel.x == 0;
  let prevColor = clamp(textureLoad(dataTextureC, pixel, 0).rgb, vec3<f32>(0.0), vec3<f32>(1.0));
  let histW = select(0.15 * heldK, 0.0, isStateTexel);
  let shown = mix(tonemapped, prevColor, histW);

  // Alpha is coverage/transmission: clear glass transmits, fracture lines and fronts scatter (HEAD added a
  // luma term that pinned alpha at 1.0).
  let alpha = clamp(transmission + (shardRunner + clickFront) * 0.5 + crackLine * 0.35, 0.08, 1.0);
  let finalRGBA = vec4<f32>(shown, alpha);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.35 + 0.55 * (1.0 - transmission), 0.20 + 0.35 * edge), 0.0, 1.0);

  var aOut = finalRGBA;
  if (isStateTexel) { aOut = vec4<f32>(hPos, hVel, fract(time), SENT); }

  textureStore(writeTexture, pixel, finalRGBA);
  textureStore(dataTextureA, pixel, aOut);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
