// ═══════════════════════════════════════════════════════════════════
//  frost-reveal-crystal — Anisotropic Dendritic Frost & Crystal Growth
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            frost-reveal, crystal-growth, semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-11-09
//  Ideas: six-fold lattice anisotropy → hexagonal ice plates on an isotropic 9-point stencil (§12.2D); forward-scatter frost; meltwater meniscus
//  A packing: raw sim state (mask, phase, orientation, impurity) as before — ACES only on writeTexture.
//             Texel (0,0) = (0,0,0,SENT) is a state sentinel (top-left corner, not a pixel): no sentinel ⇒ re-seed.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=GrowthSpeed, y=MeltRadius, z=MaxOpacity, w=Anisotropy

const SENT: f32 = 0.6182;     // state sentinel in A/C texel (0,0).w (f16-safe, tol 0.001)
const TAU: f32 = 6.2831853;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * noise(pos);
    pos = rot * pos * 2.0 + vec2<f32>(100.0);
    a *= 0.5;
  }
  return v;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact sim-state load. Texel (0,0) is the sentinel, not a pixel: read its right neighbour instead.
fn loadC(c: vec2<i32>) -> vec4<f32> {
  let cc = select(c, vec2<i32>(1, 0), c.x == 0 && c.y == 0);
  return textureLoad(dataTextureC, cc, 0);
}

// (phase, orientation) of whichever of cur / nb has the higher phase.
fn pickHigher(cur: vec2<f32>, nb: vec4<f32>) -> vec2<f32> {
  return select(cur, vec2<f32>(nb.g, nb.b), nb.g > cur.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // RESCUE R2: the extraBuffer[133..138] "critically damped spring" was dead (extraBuffer is re-uploaded
  // zeroed every frame; the thread-(0,0) writer raced the readers), so the live app already ran the raw
  // cursor. The cursor is read raw here, honestly.
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

  // Exact parameter contracts
  let growth_speed = u.zoom_params.x * 0.06 * (1.0 + bass * 0.4);
  let melt_radius = u.zoom_params.y * 0.35 + 0.02;
  let max_opacity = u.zoom_params.z;
  let anisotropy = mix(0.0, 0.6, u.zoom_params.w);

  let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);

  // RESCUE R1: state sentinel. If texel (0,0) of C does not carry it, C is another shader's leftover
  // (late start / direct switch) — seed the field instead of growing garbage forever.
  let isState = (coord.x == 0 && coord.y == 0);
  let st = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stateOk = abs(st.w - SENT) < 0.001 && st.x == 0.0 && st.y == 0.0 && st.z == 0.0;
  let needSeed = (!stateOk) || time < 0.1;
  let live = !needSeed;   // no sim step on a seed frame (neighbours are not valid yet). Gated with select(), never
                          // multiplied: an inherited NaN/Inf in C must not survive as 0·NaN.

  // Exact load from dataTextureC
  let prev = loadC(coord);
  var mask = prev.r;
  var phase = prev.g;
  var orientation = prev.b;
  var impurity = prev.a;

  if (needSeed) {
    mask = 0.5;
    phase = 0.0;
    orientation = 0.0;
    impurity = hash12(uv * 100.0) * 0.1;
    if (length(uv - vec2<f32>(0.5)) < 0.03) {
      phase = 1.0;
      orientation = atan2(uv.y - 0.5, uv.x - 0.5);
    }
  }

  // Melt frost near mouse
  let melt = smoothstep(melt_radius, melt_radius * 0.4, dist) * (0.8 + held * 0.2);
  mask = mix(mask, 0.0, melt * 0.3);
  mask += growth_speed * (1.0 - mask * 0.5);
  mask = clamp(mask, 0.0, 1.0);

  // Exact loads of the 8-neighbourhood (4 edges as before + 4 diagonals for the isotropic stencil)
  let iMax = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
  let zero2 = vec2<i32>(0);
  let left  = loadC(clamp(coord + vec2<i32>(-1,  0), zero2, iMax));
  let right = loadC(clamp(coord + vec2<i32>( 1,  0), zero2, iMax));
  let down  = loadC(clamp(coord + vec2<i32>( 0, -1), zero2, iMax));
  let up    = loadC(clamp(coord + vec2<i32>( 0,  1), zero2, iMax));
  let dl = loadC(clamp(coord + vec2<i32>(-1, -1), zero2, iMax));
  let dr = loadC(clamp(coord + vec2<i32>( 1, -1), zero2, iMax));
  let ul = loadC(clamp(coord + vec2<i32>(-1,  1), zero2, iMax));
  let ur = loadC(clamp(coord + vec2<i32>( 1,  1), zero2, iMax));

  // ── Idea 1: isotropic 9-point Laplacian (§12.2D) — the 5-point stencil has a square-lattice bias that
  // would fight any lattice anisotropy; with 0.2/0.05 weights the only anisotropy left is the one below.
  // lap9 ≈ 0.3·∇²φ, so 0.667·lap9 keeps HEAD-equivalent diffusion D = 0.2 px²/frame (stable ≤ 0.25).
  let lap9 = 0.2 * (left.g + right.g + down.g + up.g) + 0.05 * (dl.g + dr.g + ul.g + ur.g) - phase;
  let gradPhase = vec2<f32>(right.g - left.g, up.g - down.g) * 0.5;

  // RESCUE R3b: a pixel the front reaches adopts the orientation of its highest-phase neighbour
  // (HEAD only wrote orientation under the held mouse, so grown crystal stayed at orientation 0 = one
  // magenta hue). Done before the lattice term so the front already knows its crystal axis.
  var best = vec2<f32>(phase, orientation);
  best = pickHigher(best, left);
  best = pickHigher(best, right);
  best = pickHigher(best, down);
  best = pickHigher(best, up);
  best = pickHigher(best, dl);
  best = pickHigher(best, dr);
  best = pickHigher(best, ul);
  best = pickHigher(best, ur);
  let adopt = live && best.x > phase + 0.002 && phase < 0.5;
  orientation = select(orientation, best.y, adopt);

  let dir = vec2<f32>(cos(orientation), sin(orientation));
  let alignment = abs(dot(normalize(gradPhase + vec2<f32>(0.0001)), dir));
  let anisoFactor = 1.0 + anisotropy * (alignment - 0.5) * 2.0;

  let supercooling = 0.5 + mids * 0.2;
  let m = supercooling * (1.0 - 2.0 * impurity);
  let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);

  // ── Idea 1 (cont.): six-fold lattice anisotropy. Ice grows fastest along its six crystal axes (corners)
  // and slowest across them (facets), so the growth rate is scaled by exp(k·anisotropy·cos 6θ), θ = the FRONT
  // NORMAL angle (Sobel gradient of phase: exact geometry, independent of the hue-only `orientation` field).
  // Slider 0 = round disc, 0.5/1 = hexagonal plate with ever flatter facets. Kept un-normalised on purpose:
  // attenuating only the facets drops the small seed below the critical nucleus radius and it collapses
  // (tested). Weight fades out where the gradient is too small to define a direction.
  // RESCUE R3a: HEAD's reaction/diffusion were both scaled by growthRate≈0.007, so the front never moved
  // (seed r 0.030→0.033 in 1200 frames, anisotropy dead). Now r = 0.66·growth_speed and D = min(0.6·r, 0.2):
  // at the default the front creeps ≈0.08 px/frame. Rate is capped at 2.2 (explicit-Euler stability at phase≈1).
  let sobel = vec2<f32>((dr.g + 2.0 * right.g + ur.g) - (dl.g + 2.0 * left.g + ul.g),
                        (ul.g + 2.0 * up.g + ur.g) - (dl.g + 2.0 * down.g + dr.g)) * 0.125;
  let frontConf = smoothstep(0.0003, 0.006, length(sobel));
  let frontCos6 = select(0.0, cos(6.0 * atan2(sobel.y, sobel.x)), frontConf > 0.0);   // atan2(0,0) never reaches ·0
  let lattice6 = exp(3.5 * anisotropy * frontConf * frontCos6);
  // Review fix 4: diffusion now scales WITH the reaction rate (D = 0.6·r, capped at the 0.2 stability limit), so
  // the critical nucleus radius ∝ sqrt(D/r) no longer grows as the slider drops: the seed neither shrinks at low
  // speed nor flattens into a lens at low speed + high anisotropy, and speed 0 freezes the crystal like HEAD did.
  let growthBase = 0.66 * u.zoom_params.x;
  let reactRate = min(growthBase * anisoFactor * lattice6, 2.2);
  let phaseD = min(0.6 * growthBase, 0.2);                    // px²/frame; lap9 ≈ 0.3·∇² → coefficient D/0.3
  phase += select(0.0, phaseReaction * reactRate + lap9 * (phaseD / 0.3), live);
  phase = clamp(phase, 0.0, 1.0);

  // Mouse seeds crystals
  let mouseInfluence = smoothstep(0.05, 0.0, dist) * held;
  phase = mix(phase, 1.0, mouseInfluence);
  if (mouseInfluence > 0.01) {
    orientation = atan2(uv.y - mouse.y, uv.x - mouse.x);
  }

  // Click ripples melt & shock-freeze
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let toClick = (uv - r.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(toClick);
      let wave = exp(-abs(rDist - age * 0.5) * 15.0) * (1.0 - age * 0.5);
      mask = mix(mask, 0.0, wave * 0.6);
      phase = mix(phase, 1.0, wave * 0.4);
      // RESCUE R3c: ring seeds carry the radial orientation like the mouse seeds (HEAD left it at 0).
      orientation = select(orientation, atan2(uv.y - r.y, uv.x - r.x), wave * 0.4 > 0.05);
    }
  }

  // Frost visuals
  let frost_pattern = fbm(uv * 10.0 + time * 0.05);
  let frost_detail = fbm(uv * 20.0 - time * 0.03);
  let combined_frost = smoothstep(0.3, 0.7, frost_pattern * 0.6 + frost_detail * 0.4);
  let offset = (vec2<f32>(frost_pattern, frost_detail) - 0.5) * 0.05 * mask;
  let distorted_uv = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));

  let orientNorm = fract(orientation / 6.2831853);
  let h6 = orientNorm * 6.0;
  let c = 0.8;
  let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
  var crystalColor = vec3<f32>(c, x, 0.3);
  if (h6 >= 1.0 && h6 < 2.0) { crystalColor = vec3<f32>(x, c, 0.3); }
  else if (h6 >= 2.0 && h6 < 3.0) { crystalColor = vec3<f32>(0.3, c, x); }
  else if (h6 >= 3.0 && h6 < 4.0) { crystalColor = vec3<f32>(0.3, x, c); }
  else if (h6 >= 4.0 && h6 < 5.0) { crystalColor = vec3<f32>(x, 0.3, c); }
  else if (h6 >= 5.0) { crystalColor = vec3<f32>(c, 0.3, x); }

  let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
  var displayColor = mix(vec3<f32>(0.05, 0.08, 0.15), crystalColor, smoothstep(0.4, 0.6, phase));
  displayColor = mix(displayColor, vec3<f32>(0.9, 0.95, 1.0), interfaceMask * 0.5 + treble * 0.2);

  // ── Idea 3: meltwater meniscus. ∇mask (from the neighbours already loaded) is the melt boundary; a
  // water film there refracts the clear image like a bead (toward the frost side) and catches a thin
  // highlight on the lit side / a shade on the far side. Zero on flat frost and on flat clear glass.
  let gm = select(vec2<f32>(0.0), vec2<f32>(right.r - left.r, up.r - down.r) * 0.5 * resolution.y, live);
  let gmLen = length(gm);
  let rim = smoothstep(1.5, 6.0, gmLen);
  let nrm = gm / max(gmLen, 1e-4);
  let lightDir = vec2<f32>(-0.6, -0.8);                       // upper-left, uv space (y down)
  let facing = dot(nrm, lightDir);
  let glint = pow(max(facing, 0.0), 6.0) * rim;
  let shade = pow(max(-facing, 0.0), 2.0) * rim;
  let bead_uv = clamp(uv + nrm * rim * 0.008 * vec2<f32>(1.0 / aspect, 1.0), vec2<f32>(0.001), vec2<f32>(0.999));

  let clear_plain = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var clear_color = clear_plain;
  if (rim > 0.002) {   // almost every pixel is off the melt boundary: skip the extra tap there
    clear_color = mix(clear_plain, textureSampleLevel(readTexture, u_sampler, bead_uv, 0.0).rgb, rim);
  }

  // ── Idea 2: forward-scatter frost. Frosted glass diffuses the transmitted image: 4 taps on a ring
  // around the existing wobble tap, radius following frost thickness (mask · pattern), ring rotated by a
  // static per-pixel angle so the blur reads as grain instead of a 4-point ghost. No time term (no strobe).
  let thickness = mask * combined_frost;
  let scatterR = 0.003 + 0.011 * thickness;                   // uv-y units; x is divided by aspect
  let a0 = hash12(vec2<f32>(coord) * 1.37 + vec2<f32>(7.0)) * TAU;
  var scat = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;
  for (var k = 0; k < 4; k = k + 1) {
    let ang = a0 + f32(k) * 1.5707963;
    let o = vec2<f32>(cos(ang) / aspect, sin(ang)) * scatterR;
    scat += textureSampleLevel(readTexture, u_sampler, clamp(distorted_uv + o, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  }
  let frost_color_sample = scat / 5.0;
  let frosted_look = mix(frost_color_sample, vec3<f32>(0.9, 0.95, 1.0), 0.45 * mask * max_opacity);

  let visibility = mask * combined_frost * max_opacity;
  let crystalVisibility = smoothstep(0.4, 0.6, phase) * (1.0 - mask);
  var finalRGB = mix(clear_color, frosted_look, visibility);
  finalRGB = mix(finalRGB, displayColor, crystalVisibility * 0.85);
  finalRGB = finalRGB * (1.0 - 0.18 * shade) + vec3<f32>(0.85, 0.93, 1.0) * glint * 0.4;   // Idea 3 shading

  finalRGB = aces(max(finalRGB, vec3<f32>(0.0)));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.3 + visibility * 0.5 + crystalVisibility * 0.4 + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  var aOut = vec4<f32>(mask, phase, orientation, impurity);
  if (isState) { aOut = vec4<f32>(0.0, 0.0, 0.0, SENT); }
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
