// ═══════════════════════════════════════════════════════════════════
//  Interactive Voronoi Lens
//  Category: interactive-mouse
//  Features: upgraded-rgba, voronoi, lens, mouse-driven, audio-reactive,
//            depth-aware, temporal-feedback, semantic-alpha, gravity-well,
//            click-shockwave, spring-damper, emergent-feedback
//  Complexity: Medium
//  Upgraded: 2026-07-12 (retry expansion), 2026-11-09
//  Ideas: integral-imaging parallax (each lenslet sees the scene from its own viewpoint, shifted by its depth disparity from the refocus plane, so flat or missing depth is a no-op); lenslet rim catch-light, energy-accounted (§12.2F Fresnel–Schlick: the seam reflects F and transmits 1−F; seam placed by the distance to the cell border (second-nearest-seed bisector), ~1-2 px lit at every Density); cursor refocus (focal plane = depth under the sprung cursor, lenslets blur by their depth distance from it). Rescued: all interactive state lived in extraBuffer[0..7] (zeroed every frame, raced by every thread, dt was the ripple COUNT) so the well sat in the top-left corner and the click shockwave never played — spring now lives in two A texels with a real dt, shockwaves come from ripples[]; treble moved out of the time multiplier; inherited-C clamp; pixels with no seed within 1 cell (HEAD: ~0.1 %) now find their nearest seed instead of centring the lens on the uv origin; the two state texels read their trail from the texel below (not 0), so they are not ~22% darker than their neighbours.
//  A packing: (trail rgb, env) display-ish history (unchanged, read back as C). Texels (0,0) = (spring pos.xy, spring vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible; their C is not trail history, so the trail is read from the texel below).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SENT: f32 = 0.7371;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    return mix(prev, bass, select(release, attack, bass > prev));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(v / len, vec2<f32>(0.0), len < 0.0001);
}
// Fresnel–Schlick reflectance (F0 = 0.04, glass in air).
fn fresnelSchlick(cosTheta: f32) -> f32 {
    let m = clamp(1.0 - cosTheta, 0.0, 1.0);
    let m2 = m * m;
    return 0.04 + 0.96 * m2 * m2 * m;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / max(u.config.w, 0.001);
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let isPress = u.zoom_config.w;

  let density = mix(5.0, 50.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let strength = clamp(u.zoom_params.y, 0.0, 1.0);
  let chaos = clamp(u.zoom_params.z, 0.0, 1.0);
  let curve = clamp(u.zoom_params.w, 0.0, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // History = (trail rgb, bass env). The two state texels are masked, and a direct switch from
  // another shader cannot poison the trail / feedback offset with out-of-range inherited C (rgb ≤ 1.5).
  // The state texels hold spring state in C, not trail: reading them as trail (or as 0) darkens those
  // two pixels (0 -> trail = 0.12*colour -> ~22% darker). Use the texel below as their history.
  let isStateTexel = coord.y == 0 && coord.x <= 1;
  let prevRaw = textureLoad(dataTextureC, select(coord, vec2<i32>(coord.x, 1), isStateTexel), 0);
  let prev = vec4<f32>(clamp(prevRaw.rgb, vec3<f32>(0.0), vec3<f32>(1.5)), clamp(prevRaw.a, 0.0, 1.0));
  let env = bass_env(prev.a, bass, 0.8, 0.15);

  // ---- sprung "gravity well" cursor, persisted in two A texels ----
  // HEAD kept this in extraBuffer[0..7] (re-uploaded zeroed every frame, read-modify-written by
  // every thread) with dt = u.config.y (the ripple COUNT): the well never followed the cursor.
  // Texel (0,0) = (pos.xy, vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT). Every thread
  // integrates the same step from the stored state; fract(time) stays exact on rgba16float.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var smoothMouse = select(mouse, st0.xy, stateOk);
  var velocity = select(vec2<f32>(0.0), st0.zw, stateOk);
  let dt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  let k = 70.0;
  let d = 12.0;
  let accel = (mouse - smoothMouse) * k - velocity * d;
  velocity = velocity + accel * dt;
  smoothMouse = smoothMouse + velocity * dt;
  // f16 rest-snap: a spring stored in rgba16float stalls ~2e-3 short with residual velocity.
  let settled = all(abs(mouse - smoothMouse) < vec2<f32>(0.004)) && dot(velocity, velocity) < 0.0036;
  smoothMouse = select(smoothMouse, mouse, settled);
  velocity = select(velocity, vec2<f32>(0.0), settled);
  let smoothMouse_corrected = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);

  let st = uv_corrected * density;
  let i_st = floor(st);
  let f_st = fract(st);

  // Nearest seed: distance m_dist, offset-from-pixel m_diff, lattice index m_k (0..8). Second-nearest
  // seed: d2 / s_diff. m_point and cell_id are rebuilt from m_diff + m_k after the loop instead of
  // being selected per tap (per-tap selects are what made this loop expensive in SwiftShader).
  // m_dist / d2 start at 2.0 (> the farthest a 3x3 neighbourhood can be): HEAD started at 1.0, which
  // left ~0.1 % of pixels without a seed and with cell centre (0,0) (lens centred on the uv origin).
  var m_dist = 2.0;
  var m_k = 0.0;
  var s_dist = 1.0;
  var m_diff = vec2<f32>(8.0);
  var d2 = 2.0;
  var s_diff = vec2<f32>(8.0);

  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(i_st + neighbor);
      let jitter = 0.1 + env * 0.35 + chaos;
      // treble is a bounded phase offset, not a time multiplier (that teleported every cell by time·Δtreble)
      point = 0.5 + 0.5 * sin(time * (1.0 + chaos * 2.0) + treble * 0.9 + TAU * point + neighbor * jitter);
      let diff = neighbor + point - f_st;
      let dist = length(diff);
      let nearer = dist < m_dist;
      s_dist = select(s_dist, smin(s_dist, dist, 0.3), !nearer && dist < s_dist);
      s_dist = select(s_dist, min(m_dist, 1.0), nearer);
      // second-nearest seed: the candidate is this seed, or (when it just became the nearest) the old nearest
      let cand = select(diff, m_diff, nearer);
      let candd = select(dist, m_dist, nearer);
      s_diff = select(s_diff, cand, candd < d2);
      d2 = min(candd, d2);
      m_diff = select(m_diff, diff, nearer);
      m_k = select(m_k, f32((y + 1) * 3 + (x + 1)), nearer);
      m_dist = select(m_dist, dist, nearer);
    }
  }
  let m_n = vec2<f32>(m_k - 3.0 * floor(m_k / 3.0) - 1.0, floor(m_k / 3.0) - 1.0);
  let m_point = m_diff + f_st - m_n;
  let cell_id = i_st + m_n;

  // Distance (cell units) from this pixel to the border between its cell and the second-nearest seed:
  // dot(0.5*(m+r2), normalize(r2-m)) is the distance to their perpendicular bisector. An exact min over
  // all 9 seeds differs on < 2.5 % of the lit seam pixels (vertices only) and cost ~25 % more frame
  // time (per-pixel array + second pass). The smin-softened s_dist - m_dist (cell_edge) is a body
  // gradient, 0 over a band wider than the seam at big cells, so it cannot place the seam.
  let dvb = s_diff - m_diff;
  let lvb2 = dot(dvb, dvb);
  let borderDist = select(8.0, max(dot(0.5 * (m_diff + s_diff), dvb) * inverseSqrt(lvb2), 0.0), lvb2 > 1e-8);

  let cell_center_corrected = (cell_id + m_point) / density;
  let cell_center_uv = vec2<f32>(cell_center_corrected.x / aspect, cell_center_corrected.y);

  // ---- mouse gravity well on cell centres (uses lagging smooth mouse) ----
  let dist_to_mouse = length(uv_corrected - smoothMouse_corrected);
  let mouse_influence = smoothstep(0.5, 0.0, dist_to_mouse) * (1.0 + isPress * 2.0);
  let gravityStrength = smoothstep(0.6, 0.0, dist_to_mouse) * (0.18 + env * 0.18);
  let gravityDir = safeNormalize(smoothMouse_corrected - cell_center_corrected);
  let nudged_center = cell_center_corrected + gravityDir * gravityStrength * 0.04;
  let nudged_center_uv = vec2<f32>(nudged_center.x / aspect, nudged_center.y);

  let final_strength = strength * (1.0 + mouse_influence * 2.0 + env * 0.6);

  var dir = uv - nudged_center_uv;
  let dist_from_center = length(dir);
  let bulge = (1.0 - sin(dist_from_center * mix(1.0, 10.0, curve)));
  let cell_edge = clamp(s_dist - m_dist, 0.0, 1.0);

  var offset = dir * bulge * final_strength * 0.5;

  // ── Idea 1: integral-imaging parallax ───────────────────────────────
  // A lens array is a light-field sheet: every lenslet looks at the scene from its own viewpoint,
  // so neighbouring cells disagree about where a near/far object is. Shift each cell's sample by
  // its viewpoint (cell centre relative to the frame centre) times its depth disparity.
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let cellDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(nudged_center_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  // Zero-parallax plane = the refocus depth under the sprung cursor (Idea 3), so a flat or missing
  // depth map (all 0 or all 1) shifts nothing; near/far cells shift opposite ways around the focus.
  let focusDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(smoothMouse, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  offset = offset + (nudged_center_uv - vec2<f32>(0.5)) * (cellDepth - focusDepth) * 0.22 * strength;

  // ---- click shockwaves push the lens outward (from ripples[]; HEAD's latched click state was dead) ----
  var shockStrength = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      if (age >= 0.0 && age < 1.25) {
          // one ring profile serves both the push and the neon glow (they used to evaluate length + exp twice)
          let delta = uv_corrected - vec2<f32>(rp.x * aspect, rp.y);
          let dRing = length(delta);
          let arg = (dRing - age * 0.55) * 12.0;
          let ringF = exp(-arg * arg) * (1.0 - age * 0.8);
          let push = select(vec2<f32>(0.0), delta / dRing, dRing >= 0.0001) * (ringF * 0.08);
          offset = offset + vec2<f32>(push.x / aspect, push.y);
          shockStrength += ringF * 1.5;
      }
  }
  shockStrength = min(shockStrength, 2.0);

  // ---- emergent feedback: previous frame distorts current offset ----
  let feedbackEnergy = length(prev.rgb);
  offset = offset + safeNormalize(offset) * feedbackEnergy * 0.02 * (1.0 + mids);

  let final_uv = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;

  // ── Idea 3: cursor refocus ──────────────────────────────────────────
  // The focal plane is the depth under the sprung cursor; each lenslet is out of focus by how far
  // its own depth is from that plane (plenoptic "pick a depth to refocus"). Rotated 4-tap diamond.
  let blurR = min(abs(cellDepth - focusDepth) * 0.03 * (0.4 + strength), 0.012);
  // A blur radius under ~0.6 px is invisible: skip the four extra taps there.
  if (blurR * f32(dims.y) > 0.6) {
    let ang = hash22(cell_id).x * TAU;
    let tapScale = vec2<f32>(blurR / aspect, blurR);
    let ax = vec2<f32>(cos(ang), sin(ang)) * tapScale;
    let ay = vec2<f32>(-sin(ang), cos(ang)) * tapScale;
    let t1 = textureSampleLevel(readTexture, u_sampler, clamp(final_uv + ax, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let t2 = textureSampleLevel(readTexture, u_sampler, clamp(final_uv - ax, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let t3 = textureSampleLevel(readTexture, u_sampler, clamp(final_uv + ay, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let t4 = textureSampleLevel(readTexture, u_sampler, clamp(final_uv - ay, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = (color + t1 + t2 + t3 + t4) * 0.2;
  }

  let neon = vec3<f32>(0.15, 0.35, 0.6) * cell_edge * (0.5 + mids * 0.6);
  color = color + neon * strength;

  // ── Idea 2: lenslet rim catch-light, energy-accounted (§12.2F Fresnel–Schlick) ──
  // borderDist is 0 on the seam and grows into the cell body: the lenslet's radial coordinate.
  // The rim is the grazing end of that sphere: it REFLECTS F of the sheen and transmits 1−F of the
  // magnified image (light moved, not added). The ramp reaches 5 px (of border distance) from the
  // seam at every Density / resolution (capped at 0.3 cell on the smallest cells); the F^5 falloff
  // makes the visibly lit band ~1.2-1.8 px wide (measured at 576 px: F > 0.1 is 1.75 / 1.82 / 1.24 px at Density 0 / 0.5 / 1).
  let cellPx = f32(dims.y) / density;
  let wRim = clamp(5.0 / cellPx, 0.01, 0.3);
  let rn = 1.0 - smoothstep(0.0, wRim, borderDist);
  let cosT = sqrt(max(1.0 - rn * rn, 0.0));
  let rimF = fresnelSchlick(cosT) * (0.15 + 0.65 * strength);
  let sheen = vec3<f32>(0.78, 0.92, 1.0) * (0.55 + env * 0.35 + treble * 0.25);
  color = color * (1.0 - rimF) + sheen * rimF;

  // ---- shockwave neon ring ----
  color = color + vec3<f32>(0.4, 0.7, 1.0) * shockStrength * (0.6 + treble);

  let fog = 1.0 - exp(-depth * 1.8);
  color = mix(color, color * 0.7, fog * 0.4);

  let trail = mix(prev.rgb * 0.96, color, 0.12 + mouse_influence * 0.12);
  color = mix(color, trail, 0.25);
  color = acesToneMap(max(color, vec3<f32>(0.0)) * (0.9 + env * 0.2));

  let alpha = clamp(0.35 + cell_edge * 0.45 + mouse_influence * 0.25 + shockStrength * 0.35, 0.0, 0.95);

  var aOut = vec4<f32>(trail, env);
  if (coord.y == 0 && coord.x == 0) { aOut = vec4<f32>(smoothMouse, velocity); }
  if (coord.y == 0 && coord.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
