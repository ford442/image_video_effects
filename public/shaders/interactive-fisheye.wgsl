// ═══════════════════════════════════════════════════════════════════
//  Fluid Lens Dynamics (interactive-fisheye)
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-04, 2026-11-09
//  Ideas: refraction from the simulated surface (exact C neighbour gradient); caustic focusing from the height Laplacian; neighbour-coupled capillary waves (damped wave equation + isotropic 9-point Laplacian, §12.2D); Snell vector refraction (η = 1/1.33, §12.2F)
//  A packing: raw sim state [h, v, nx, ny] (normal is the blended sim normal); texel (0,0) = cursor-lag tracker (glide.x, glide.y, 7 marker, fract(time)) and is masked (h = v = 0) in every sim read; display is ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"


fn aces_film(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

// ── Rescue R1 (lag only): cursor-lag tracker in A texel (0,0) ─────────
// HEAD estimated the droplet's stretch from the last two CLICKS (ripples[rc-1] - ripples[rc-2]), so the
// teardrop tracked click history, not the drag. A glide of the raw cursor now lives in A texel (0,0)
// (extraBuffer[133..] is re-uploaded zeroed every frame, so it cannot hold state). The droplet itself stays
// at the RAW cursor; only the lag vector (raw - glide) is used, as the velocity proxy for stretch_dir /
// stretch_mag. First-order glide: lag = velocity / GLIDE_RATE when the cursor moves steadily. At rest: lag = 0.
// Texel (0,0) is therefore not sim data any more; every sim read of C goes through simLoad(), which masks it.
const GLIDE_MARK: f32 = 7.0;
const GLIDE_RATE: f32 = 8.0;

fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
  let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;   // <= 1: f16 rounds fract(time) > 0.9997 to exactly 1.0
  let dt = clamp(fract(time - st.w), 0.001, 0.05);
  let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
  let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
  return select(raw, snapped, ok);
}

// Exact C load of the sim state with the border clamped (reflecting wall) and texel (0,0) masked to h = v = 0.
fn simLoad(c: vec2<i32>, maxc: vec2<i32>) -> vec4<f32> {
  let cc = clamp(c, vec2<i32>(0), maxc);
  let s = textureLoad(dataTextureC, cc, 0);
  return select(s, vec4<f32>(0.0), all(cc == vec2<i32>(0)));
}

// Wave solver constants (Idea 3).
// - Deviation, not height: the wave force is the Laplacian of (h - rest height), where the rest height is what the
//   pixel's spring already pulls toward (analytic droplet + painted capillary). Laplacian of h itself would smooth
//   the droplet's razor-sharp sqrt edge into a wide meniscus and spread the lens (measured: lens radius +60%, a
//   different effect); the deviation is ~0 on the equilibrium droplet, so the droplet looks as in HEAD and only
//   transients (overshoot after a move, ripples launched by the capillary forcing, splashes) propagate and ring down.
// - Stencil spacing wb texels = WAVE_STENCIL of the frame height, not 1 texel: A is rgba16float on most real tiers,
//   h rounds to ~5e-4..1e-3 there, and a 1-texel Laplacian of a smooth field (~2e-4 per texel^2 at 576 px) is BELOW
//   that rounding noise (measured: 5-14x HEAD's frame-to-frame flicker). Spacing wb keeps the signal a fixed size
//   on screen and divides the rounding noise by wb^2; LAP_CORE dead-bands what is left (continuous soft threshold).
// - WAVE_SPEED is in screen heights per second (c^2 is also scaled by spring_k/6.86, i.e. surface tension / mass, so
//   Surface Tension 0 still means no droplet). kappa = (c dt / spacing)^2 = (0.03 * 0.016 / 0.015)^2 ~ 1e-3 is the
//   per-frame CFL number of the stencil (dh = kappa * lap per frame, accumulated through v). The isotropic 9-point
//   Laplacian has |lambda_max| = 16/3, so the leapfrog limit is kappa <= 0.75; forced test on f16 (WAVE_SPEED 5):
//   stable at kappa 0.25 / 0.5 / 0.75, v pinned at the V_MAX clamp (unstable) at 1.1. WAVE_KAPPA_MAX = 0.25 is the
//   hard cap (3x margin) and only binds if WAVE_SPEED is raised. 0.03 and not higher: the painted capillary
//   forcing runs at omega = 6, k = 48 and the spring + wave dispersion omega^2 = omega0^2 + c^2 k^2 resonates
//   with it (c = 0.08 gave +-0.3 centre rings, ~3x HEAD's).
const WAVE_STENCIL: f32 = 0.015;
const LAP_CORE: f32 = 0.0015;
const WAVE_SPEED: f32 = 0.03;
const WAVE_KAPPA_MAX: f32 = 0.25;
const V_MAX: f32 = 12.0;
// Air -> water, relative index n1/n2. eta < 1 so the refracted ray always exists (no total internal reflection).
const SNELL_ETA: f32 = 0.7519;
const SNELL_CAP: f32 = 0.16;

fn droplet_shape(p: vec2<f32>, center: vec2<f32>, radius: f32, stretch_dir: vec2<f32>, stretch_mag: f32) -> f32 {
  let d = p - center;
  let len_d = length(d);
  if (len_d > radius * 1.5) { return 0.0; }
  let parallel = dot(d, stretch_dir);
  let perp = length(d - stretch_dir * parallel);
  let eff_r = sqrt(parallel * parallel / max(1.0 + stretch_mag * 1.8, 0.1) + perp * perp);
  let h = max(0.0, 1.0 - (eff_r / max(radius, 0.001)) * (eff_r / max(radius, 0.001)));
  return sqrt(h);
}

// Equilibrium height a pixel's spring pulls toward: the analytic droplet + the painted capillary forcing, clamped
// >= 0 exactly like h itself (HEAD's `target_h + capillary`).
fn rest_height(pc: vec2<f32>, mouse_corr: vec2<f32>, radius: f32, sdir: vec2<f32>, smag: f32, t: f32, down: f32, treble: f32) -> f32 {
  let dm = length(pc - mouse_corr);
  let cap = sin(dm * 48.0 - t * 6.0) * exp(-dm * 8.0) * (0.1 + 0.25 * down) * (1.0 + treble * 0.6);
  return max(droplet_shape(pc, mouse_corr, radius, sdir, smag) + cap, 0.0);
}

// Deviation of the SIMULATED height from its equilibrium at the stencil texel `coord + off` (exact C load,
// border clamped, texel (0,0) masked). Waves are the Laplacian of this deviation, not of h itself.
fn wave_dev(coord: vec2<i32>, off: vec2<i32>, maxc: vec2<i32>, res: vec2<f32>, aspect_vec: vec2<f32>,
            mouse_corr: vec2<f32>, radius: f32, sdir: vec2<f32>, smag: f32, t: f32, down: f32, treble: f32) -> f32 {
  let nc = clamp(coord + off, vec2<i32>(0), maxc);
  let pc = ((vec2<f32>(nc) + vec2<f32>(0.5)) / res) * aspect_vec;
  return simLoad(nc, maxc).r - rest_height(pc, mouse_corr, radius, sdir, smag, t, down, treble);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let aspect_vec = vec2<f32>(aspect, 1.0);
  let t = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let surface_tension = u.zoom_params.x * (1.0 + bass * 0.35);
  let viscosity = clamp(u.zoom_params.y, 0.05, 0.98);
  let mass = max(u.zoom_params.z * 1.5 + 0.2, 0.1);
  let splash_thresh = mix(0.15, 2.5, u.zoom_params.w);

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;
  let held = f32(is_down > 0.5);

  let depth_tex = textureLoad(readDepthTexture, coord, 0).r;
  let depth_mass = mix(0.5, 1.6, depth_tex);

  let maxc = vec2<i32>(res) - vec2<i32>(1);
  let prev_state = simLoad(coord, maxc);   // texel (0,0) reads as h = v = 0 (Rescue R1)
  let prev_h = prev_state.r;
  let prev_v = prev_state.g;

  let rc = min(u32(u.config.y), 50u);
  // ── Rescue R1 (lag only): the velocity proxy is the cursor lag, not the last two clicks ──
  // droplet stays at the RAW cursor; glide state is last frame's A(0,0) (exact C load, same for every pixel).
  let glide_state = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let glide = glideStep(glide_state, mouse_pos, t, GLIDE_RATE);
  let has_ptr = all(mouse_pos >= vec2<f32>(0.0));
  let pointer_vel = select(vec2<f32>(0.0), (mouse_pos - glide) * GLIDE_RATE, has_ptr);   // uv / s
  let speed = length(pointer_vel * aspect_vec);
  let stretch_dir = select(vec2<f32>(1.0, 0.0), normalize(pointer_vel * aspect_vec), speed > 0.001);
  let stretch_mag = clamp(speed * 0.12 / mass, 0.0, 1.5) * (1.0 + held * 0.45);

  let lens_radius = mix(0.18, 0.45, surface_tension * 0.5 + 0.25) * (1.0 + bass * 0.2) / depth_mass * mix(1.0, 0.78, held);
  let p_corr = uv * aspect_vec;
  let mouse_corr = mouse_pos * aspect_vec;

  let target_h = droplet_shape(p_corr, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let dist_m = length(p_corr - mouse_corr);
  let capillary = sin(dist_m * 48.0 - t * 6.0) * exp(-dist_m * 8.0) * (0.1 + 0.25 * is_down) * (1.0 + treble * 0.6);
  let runners = pow(max(0.0, sin(dist_m * 28.0 - t * (9.0 + mids * 5.0))), 12.0) * exp(-dist_m * 4.0);

  // ── Idea 3: neighbour-coupled capillary waves (damped wave equation + isotropic 9-point Laplacian, §12.2D) ──
  // HEAD's sim had no neighbour coupling: each pixel was an independent spring toward an analytic target, so
  // the "ripples" were painted functions. Promote the Laplacian to a force: d_tt = c^2 lap(d) - spring - damping
  // for the deviation d = h - rest, with the isotropic 9-point stencil (edges 0.2, corners 0.05, centre -1; x10/3
  // makes it a true Laplacian) so rings are round, not diamond. The 8 stencil loads are exact C loads (borders
  // clamped = reflecting wall), texel (0,0) is masked to h = 0 (R1). Per frame: dv = (kappa/dt) lap, dh = kappa lap.
  let wb = clamp(round(WAVE_STENCIL * res.y), 1.0, 16.0);   // stencil spacing in texels
  let wi = i32(wb);
  let rest_c = max(target_h + capillary, 0.0);
  let dev_c = prev_h - rest_c;
  let dv_l = wave_dev(coord, vec2<i32>(-wi, 0), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_r = wave_dev(coord, vec2<i32>(wi, 0), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_d = wave_dev(coord, vec2<i32>(0, -wi), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_u = wave_dev(coord, vec2<i32>(0, wi), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_ll = wave_dev(coord, vec2<i32>(-wi, -wi), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_lr = wave_dev(coord, vec2<i32>(wi, -wi), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_ul = wave_dev(coord, vec2<i32>(-wi, wi), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let dv_ur = wave_dev(coord, vec2<i32>(wi, wi), maxc, res, aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag, t, is_down, treble);
  let lap_raw = (10.0 / 3.0) * (0.2 * (dv_l + dv_r + dv_d + dv_u) + 0.05 * (dv_ll + dv_lr + dv_ul + dv_ur) - dev_c);
  let lap9 = lap_raw - clamp(lap_raw, -LAP_CORE, LAP_CORE);   // rounding-noise dead-band

  let spring_k = 12.0 * surface_tension / mass;
  let damp_c = 4.0 * viscosity;
  let dt_sub = 0.016;
  let wave_c = WAVE_SPEED * dt_sub * res.y / wb;             // stencil spacings per frame
  // capillary waves: c^2 ~ surface tension / mass, i.e. ~ spring_k; normalised so the defaults (spring_k 6.86) keep
  // WAVE_SPEED, 0 at Surface Tension 0 (no droplet forms at all there, as in HEAD), at most 2x in the stiffest corner.
  let wave_gain = clamp(spring_k / 6.86, 0.0, 2.0);
  let wave_kappa = min(wave_c * wave_c * wave_gain, WAVE_KAPPA_MAX);   // CFL number, <= 0.25 always
  let accel = spring_k * (target_h + capillary - prev_h) - damp_c * prev_v + (wave_kappa / (dt_sub * dt_sub)) * lap9;
  let new_v = clamp(prev_v + accel * dt_sub, -V_MAX, V_MAX);
  let new_h = clamp(prev_h + new_v * dt_sub, 0.0, 2.0);

  let eps = 1.0 / res.y;
  let h_r = droplet_shape((uv + vec2<f32>(eps, 0.0)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let h_l = droplet_shape((uv - vec2<f32>(eps, 0.0)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let h_u = droplet_shape((uv + vec2<f32>(0.0, eps)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let h_d = droplet_shape((uv - vec2<f32>(0.0, eps)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let dn_dx = (h_r - h_l) / (2.0 * eps);
  let dn_dy = (h_u - h_d) / (2.0 * eps);

  // Idea 1: refract through the surface the solver actually simulated. The
  // neighbours' last-frame heights (exact C loads) carry the overshoot,
  // jiggle and capillary ripples that the analytic target shape never had.
  let s_l = simLoad(coord + vec2<i32>(-1, 0), maxc).r;
  let s_r = simLoad(coord + vec2<i32>(1, 0), maxc).r;
  let s_d = simLoad(coord + vec2<i32>(0, -1), maxc).r;
  let s_u = simLoad(coord + vec2<i32>(0, 1), maxc).r;
  let px = 1.0 / res.y; // one pixel in aspect-corrected units
  let sim_dx = (s_r - s_l) / (2.0 * px);
  let sim_dy = (s_u - s_d) / (2.0 * px);
  let grad_x = mix(dn_dx, sim_dx, 0.8);
  let grad_y = mix(dn_dy, sim_dy, 0.8);
  let normal = normalize(vec3<f32>(-grad_x * (0.8 + 0.4 * surface_tension), -grad_y * (0.8 + 0.4 * surface_tension), 1.0));

  // Idea 2: caustics. A convex droplet focuses light (negative Laplacian of
  // the simulated height brightens its body) and the steep meniscus bends
  // light away, leaving a darker ring.
  let lap = (s_l + s_r + s_d + s_u - 4.0 * prev_h) / (px * px);   // HEAD's 1-texel 5-point Laplacian, kept (masked reads)
  let focus = clamp(-lap * 0.015, 0.0, 0.5);
  let meniscus = smoothstep(2.0, 6.0, length(vec2<f32>(grad_x, grad_y))) * 0.35;

  var splash_disp = vec2<f32>(0.0);
  var click = 0.0;
  for (var i = 0u; i < rc; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.5) {
      let r_pos = r.xy * aspect_vec;
      let d_r = length(p_corr - r_pos);
      let front = abs(d_r - age * 0.6);
      let pulse = exp(-front * 30.0) * exp(-age * 1.4);
      let r_dir = select(vec2<f32>(0.0), (p_corr - r_pos) / max(d_r, 0.001), d_r > 0.001);
      splash_disp += r_dir * pulse * 0.04 * sin(d_r * 45.0 - age * 14.0) * (1.0 + splash_thresh * 0.15);
      click = max(click, pulse);
    }
  }

  // ── Idea 4: Snell refraction (§12.2F) replaces the small-angle `normal.xy * 0.12 * h` ──
  // Refracted ray T = eta*I + (eta*cos_i - cos_t)*n with I = (0,0,-1) (view ray), n = the blended sim normal.
  // Its lateral run per unit of depth is  bend / |T.z|  with  bend = cos_t - eta*cos_i  and  |T.z| = eta + bend*cos_i.
  // The water depth is taken proportional to the simulated height, depth = h * 0.12/(1 - eta), so at weak slope
  // (cos_i -> 1: bend -> 1 - eta, |T.z| -> 1) the shift is exactly HEAD's 0.12*h*normal.xy (calibration), while a
  // steep meniscus bends non-linearly (up to ~3.5x per unit normal.xy at grazing incidence). Direction is kept as
  // in HEAD (displacement along +normal.xy). eta < 1 (air -> water): no total internal reflection is possible,
  // the sqrt is guarded anyway, and the shift is length-capped to SNELL_CAP*h (HEAD's small-angle maximum is
  // 0.12*h): the steep rim keeps the non-linear gain up to that cap but can never tear the picture (or sample
  // far away) much harder than HEAD did.
  let cos_i = clamp(normal.z, 0.0, 1.0);
  let cos_t = sqrt(max(1.0 - SNELL_ETA * SNELL_ETA * (1.0 - cos_i * cos_i), 0.0));
  let bend = cos_t - SNELL_ETA * cos_i;
  let lateral = bend / max(SNELL_ETA + bend * cos_i, 0.2);
  var snell_shift = normal.xy * (0.12 / (1.0 - SNELL_ETA) * new_h * lateral);
  snell_shift = snell_shift * min(1.0, (SNELL_CAP * new_h) / max(length(snell_shift), 1e-5));   // 0 where there is no water
  let refr_vec = snell_shift + splash_disp;
  let uv_r = clamp(uv + refr_vec * 1.06, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_g = clamp(uv + refr_vec, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_b = clamp(uv + refr_vec * 0.94, vec2<f32>(0.001), vec2<f32>(0.999));
  let c_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let c_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
  let c_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;
  let src_alpha = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).a;
  let refracted = vec3<f32>(c_r, c_g, c_b) * (1.0 + focus * (0.8 + bass * 0.4) - meniscus);

  let light_dir = normalize(vec3<f32>(mouse_pos.x - 0.5, mouse_pos.y - 0.5, 0.8));
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let half_v = normalize(light_dir + view_dir);
  // ── Rescue R2: the specular lobe only exists where there is water ──
  // HEAD added `spec` to the WHOLE frame: on flat water the normal is (0,0,1), half_v ~ (0,0,1) for a cursor near
  // the centre, so spec ~ 1 and the background got a +0.6 (+1.4 held) white wash. Gate it by droplet presence.
  let present = smoothstep(0.02, 0.25, new_h);
  let spec = pow(max(dot(normal, half_v), 0.0), 36.0) * (0.6 + 0.8 * is_down) * present;
  let fresnel_term = pow(1.0 - max(dot(normal, view_dir), 0.0), 3.5) * new_h;
  let slick = hsv2rgb(vec3<f32>(fract(0.55 + new_h * 0.35 + mids * 0.2 + t * 0.1), 0.7, 1.0));

  var final_color = refracted + vec3<f32>(1.0) * spec + vec3<f32>(0.85, 0.95, 1.0) * fresnel_term * 0.4;
  final_color = mix(final_color, final_color * slick * 1.25, (0.16 + treble * 0.2) * clamp(fresnel_term + runners, 0.0, 1.0));
  final_color += slick * (runners * 0.22 * new_h + click * 0.35);
  final_color = aces_film(final_color);

  textureStore(writeTexture, coord, vec4<f32>(final_color, src_alpha));
  // A = RAW sim [h, v, nx, ny]; texel (0,0) is the cursor-lag tracker instead (Rescue R1) and is masked in simLoad().
  var a_out = vec4<f32>(new_h, new_v, normal.x, normal.y);
  if (global_id.x == 0u && global_id.y == 0u) {
    a_out = vec4<f32>(glide, GLIDE_MARK, fract(t));
  }
  textureStore(dataTextureA, coord, a_out);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth_tex + new_h * 0.35, 0.0, 1.0), 0.0, 0.0, 0.0));
}
