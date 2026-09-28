// ═══════════════════════════════════════════════════════════════════
//  Chrono-Kitsune Prism Weaver
//  Category: generative
//  Features: raymarch, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: body-as-prism tail spectrum (each tail one discrete spectral band, the body rim disperses into the band behind it); heartbeat transfer (the body's lub-dub swell runs out along every tail); tail unfurl (fractional Tail Count grows the next tail out of the fan)
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read exactly as HDR radial echo
// ═══════════════════════════════════════════════════════════════════
// Optimizer pass (Batch 37): bounding-sphere early-out, tetrahedral
//           normals (4 taps instead of 6), hoisted frame-uniform terms,
//           named constants, HDR feedback chain, fixed mouse-uniform truth.
// 2026-09-27 fixes: tails splay outward (at HEAD the whole fan hid behind
//           the body: 0 tail hits in a numpy port), upright image, depth
//           near=1/miss=0, step exhaustion no longer shaded as a hit.
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── March constants (named, bounded) ────────────────────────────
const RAY_STEPS: i32 = 72;        // hard bound on march iterations
const SURF_EPS: f32 = 0.01;       // surface hit epsilon
const HIT_EPS: f32 = 0.04;        // accept-as-hit slack after the march (grazing rays)
const FAR_CLIP: f32 = 40.0;       // far plane / early exit
const STEP_RELAX: f32 = 0.7;      // relaxation factor per step

// ── Kitsune SDF constants ───────────────────────────────────────
const BODY_POS: vec3<f32> = vec3<f32>(0.0, 0.0, 5.0);
const BODY_RADIUS: f32 = 1.2;
const BODY_DETAIL_FREQ: f32 = 10.0;
const BODY_DETAIL_AMP: f32 = 0.1;
const TAIL_Z_START: f32 = 6.0;
const TAIL_Z_LEN: f32 = 20.0;
const TAIL_RADIUS: f32 = 0.2;
const TAIL_TAPER: f32 = 0.03;
const TAIL_OFFSET: f32 = 0.8;
const TAIL_WAVE_AMP: f32 = 0.5;
const TAIL_SMIN: f32 = 0.4;
const BODY_SMIN: f32 = 0.6;
const MIN_TAILS: f32 = 3.0;
const MAX_TAILS: f32 = 9.0;
// FIX: tails splay outward with length so the fan clears the body silhouette
const TAIL_SPLAY: f32 = 0.55;
const TAIL_LIP_INV: f32 = 0.876;  // 1/sqrt(1+splay^2): keeps the sheared tail SDF conservative

// ── Idea 2: heartbeat transfer constants ────────────────────────
const BEAT_PERIOD: f32 = 1.3;     // seconds per lub-dub
const PULSE_SPEED: f32 = 9.0;     // world units / s the pulse travels down a tail
const BODY_BEAT_SWELL: f32 = 0.1;
const TAIL_BEAT_SWELL: f32 = 0.18;
const PULSE_GLOW: f32 = 2.5;

// ── Bounding volume for ray early-out (covers body + splayed fan) ──
const BOUND_C: vec3<f32> = vec3<f32>(0.0, 0.0, 16.5);
const BOUND_R: f32 = 17.0;

// ── Feedback constants ──────────────────────────────────────────
const ECHO_DISP_FREQ: f32 = 20.0;
const ECHO_DISP_SPEED: f32 = 5.0;
const ECHO_DISP_AMP: f32 = 0.005;
const ECHO_MIX: f32 = 0.85;
const HDR_CEIL: f32 = 8.0;        // keep HDR feedback bounded

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 2: lub-dub heartbeat, periodic in `phase` (cycles) and continuous
// across the wrap (each peak measured to its nearest repeat).
fn heartbeat(phase: f32) -> f32 {
    let a0 = phase - 0.06;
    let a = (a0 - floor(a0 + 0.5)) * 16.0;
    let b0 = phase - 0.24;
    let b = (b0 - floor(b0 + 0.5)) * 16.0;
    return exp(-a * a) + 0.6 * exp(-b * b);
}

// Idea 1: visible spectrum, x = 0 red .. 1 violet (bump fit over 680..400 nm).
fn spectralBand(x: f32) -> vec3<f32> {
    let lam = 680.0 - 280.0 * clamp(x, 0.0, 1.0);
    let r0 = (lam - 620.0) / 90.0;
    let rv = (lam - 410.0) / 35.0;
    let g0 = (lam - 540.0) / 70.0;
    let b0 = (lam - 455.0) / 60.0;
    let r = max(1.0 - r0 * r0, 0.0) + 0.4 * max(1.0 - rv * rv, 0.0);
    let g = max(1.0 - g0 * g0, 0.0);
    let b = max(1.0 - b0 * b0, 0.0);
    return vec3<f32>(r, g, b) * 1.3;
}

// SDF: kitsune body + prismatic tail fan. Tail count / growth, weave and
// beat amplitude are hoisted per-frame (uniform across the march).
// Returns (distance, material 1=body 2=tail, band of nearest tail, pulse on nearest tail).
fn mapKitsune(p: vec3<f32>, time: f32, tail_full: i32, tail_grow: f32, weave: f32, beat_amp: f32) -> vec4<f32> {
    // Kitsune central body
    let bp = p - BODY_POS;
    let ripple = sin(bp.x * BODY_DETAIL_FREQ + time)
               * sin(bp.y * BODY_DETAIL_FREQ + time)
               * sin(bp.z * BODY_DETAIL_FREQ + time);
    // Idea 2: the heart — the body swells on each lub-dub
    let body_beat = heartbeat(time / BEAT_PERIOD) * beat_amp;
    let d_body = (length(bp) - BODY_RADIUS - BODY_BEAT_SWELL * body_beat) + BODY_DETAIL_AMP * ripple;

    // Prismatic tails (bounded 3–9 by slider)
    // Idea 3: tail unfurl — fractional count; the newest tail (index tail_full)
    // grows in length and girth with tail_grow and the fan spacing eases open.
    var d_tails = 1000.0;
    var best_d = 1000.0;
    var best_band = 0.0;
    var best_pulse = 0.0;
    let count_eff = f32(tail_full) + tail_grow;
    let inv_count = 1.0 / count_eff;
    let n_loop = tail_full + select(0, 1, tail_grow > 0.0);
    for (var i = 0; i < n_loop; i = i + 1) {
        let phase = f32(i) * TAU * inv_count;
        let newest = i >= tail_full;
        let tail_len = select(TAIL_Z_LEN, TAIL_Z_LEN * tail_grow, newest);
        let girth = select(1.0, tail_grow, newest);
        var tp = p;
        tp.z -= TAIL_Z_START;
        let rotated_xy = rot2(phase) * tp.xy;
        tp = vec3<f32>(rotated_xy.x, rotated_xy.y, tp.z);
        tp.x -= TAIL_OFFSET;
        let s_along = max(tp.z, 0.0);
        tp.x -= TAIL_SPLAY * s_along; // FIX: fan the tails out past the body
        tp.x += sin(tp.z * weave * 0.5 - time * 2.0 + phase) * TAIL_WAVE_AMP;
        // Idea 2: heartbeat transfer — the body's pulse arrives at distance s
        // along the tail s/PULSE_SPEED seconds later and swells the tail as it passes.
        let pulse = heartbeat((time - s_along / PULSE_SPEED) / BEAT_PERIOD) * beat_amp
                  * (1.0 - 0.3 * clamp(s_along / TAIL_Z_LEN, 0.0, 1.0));
        let d_cyl = length(tp.xy) - (TAIL_RADIUS + tp.z * TAIL_TAPER + TAIL_BEAT_SWELL * pulse) * girth;
        let z_bounds = max(-tp.z, tp.z - tail_len);
        let d_i = max(d_cyl, z_bounds) * TAIL_LIP_INV;
        if (d_i < best_d) {
            best_d = d_i;
            best_band = f32(i) * inv_count; // Idea 1: this tail's slot in the spectrum
            best_pulse = pulse;
        }
        d_tails = smin(d_tails, d_i, TAIL_SMIN);
    }

    let is_body = d_body < d_tails;
    return vec4<f32>(smin(d_body, d_tails, BODY_SMIN), select(2.0, 1.0, is_body), best_band, best_pulse);
}

// Tetrahedral normal — 4 SDF taps instead of the 6-tap central difference.
fn calcNormal(p: vec3<f32>, time: f32, tail_full: i32, tail_grow: f32, weave: f32, beat_amp: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.01;
    return normalize(
        e.xyy * mapKitsune(p + e.xyy, time, tail_full, tail_grow, weave, beat_amp).x +
        e.yyx * mapKitsune(p + e.yyx, time, tail_full, tail_grow, weave, beat_amp).x +
        e.yxy * mapKitsune(p + e.yxy, time, tail_full, tail_grow, weave, beat_amp).x +
        e.xxx * mapKitsune(p + e.xxx, time, tail_full, tail_grow, weave, beat_amp).x
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;

    // Audio — ONLY plasmaBuffer[0].xyz + guarded FFT bins 1–8
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fft = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        for (var k = 1u; k <= 8u; k = k + 1u) {
            fft += extraBuffer[4u + k];
        }
        fft *= 0.125;
    }

    // Mouse: zoom_config.yz is already 0–1 uv (y=0 top) — no /res divide.
    var mpos = u.zoom_config.yz * 2.0 - vec2<f32>(1.0);
    mpos.y = -mpos.y; // flip to match bottom-up scene space
    if (length(mpos) > 1.5) { mpos = vec2<f32>(0.0); }
    let mouse_down = u.zoom_config.w > 0.5;
    let burst = select(0.0, 0.8 + bass, mouse_down); // chrono burst on click

    // Live sliders
    let p_prism_hue  = u.zoom_params.x;
    let p_tail_count = u.zoom_params.y;
    let p_weave      = u.zoom_params.z;
    let p_echo       = u.zoom_params.w;

    // Hoisted frame-uniform terms (were recomputed inside every map call)
    // Idea 3: HEAD was floor(p*9) clamped 3..9 (each step popped a whole tail).
    // Now the integer part is fully grown and the next tail unfurls over the
    // upper 65% of each step: at the default 0.8 (7.2) it is still exactly 7 tails.
    let tail_cf    = clamp(p_tail_count * MAX_TAILS, MIN_TAILS, MAX_TAILS);
    let tail_full  = i32(floor(tail_cf));
    let tail_grow  = select(smoothstep(0.35, 1.0, fract(tail_cf)), 0.0, tail_full >= i32(MAX_TAILS));
    let weave      = 1.0 + p_weave * 3.0;
    let beat_amp   = 1.0 + bass * 0.8; // audio rides the heartbeat (not the idea)
    let band_shift = p_prism_hue * 0.2 + time * 0.02 + mids * 0.05; // Prism Hue Shift rotates the band order (0..5 = one turn)

    // FIX: flip y so screen-top = scene +y (HEAD rendered upside-down vs the flipped mouse and the (1,1,-1) light)
    let uv = vec2<f32>(f32(pixel.x) - 0.5 * res.x, 0.5 * res.y - f32(pixel.y)) / res.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse spatial bend
    let rd_xy = rot2(mpos.x * 2.0) * rd.xz;
    rd.x = rd_xy.x;
    rd.z = rd_xy.y;
    let rd_yz = rot2(mpos.y * 2.0) * rd.yz;
    rd.y = rd_yz.x;
    rd.z = rd_yz.y;

    // Bounding-sphere early-out: rays that cannot touch the kitsune or its
    // tail arcs skip the march entirely (large background savings).
    let oc     = ro - BOUND_C;
    let b_half = dot(oc, rd);
    let c_term = dot(oc, oc) - BOUND_R * BOUND_R;
    let disc   = b_half * b_half - c_term;
    let in_bounds = disc > 0.0 && (-b_half + sqrt(max(disc, 0.0))) > 0.0;

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var band = 0.0;
    var pulse = 0.0;
    var p = ro;
    var glow = 0.0;
    var glow_rgb = vec3<f32>(0.0); // Idea 1: fan halo carries each tail's band

    // Raymarching — bounded with early exits
    if (in_bounds) {
        for (var i = 0; i < RAY_STEPS; i = i + 1) {
            p = ro + rd * t;
            let hit = mapKitsune(p, time, tail_full, tail_grow, weave, beat_amp);
            d = hit.x;
            m = hit.y;
            band = hit.z;
            pulse = hit.w;

            if (m > 1.5) {
                let g_step = 0.02 / (1.0 + d * d * 50.0);
                glow += g_step;
                // Idea 1 + 2: halo coloured by the nearest tail's band, brightened where the pulse is
                glow_rgb += spectralBand(fract(band + band_shift)) * g_step * (1.0 + PULSE_GLOW * pulse);
            }

            if (d < SURF_EPS) { break; }
            t += d * STEP_RELAX;
            if (t > FAR_CLIP) { break; }
        }
    }
    glow *= 1.0 + burst; // click-driven chrono burst

    var col = vec3<f32>(0.0);
    // FIX: step exhaustion is not a hit (HEAD shaded every stalled grazing ray)
    let hit_surface = in_bounds && t < FAR_CLIP && d < HIT_EPS;

    if (hit_surface) {
        let n = calcNormal(p, time, tail_full, tail_grow, weave, beat_amp);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let fre = pow(1.0 - max(dot(n, view), 0.0), 4.0);

        let hue = p_prism_hue + t * 0.1 - time * 0.5 + mids * 0.15;
        let base_col = vec3<f32>(0.5 + 0.5 * sin(hue * TAU + vec3<f32>(0.0, 2.0, 4.0)));

        if (m < 1.5) {
            // Kitsune Body — Idea 1: the body is the prism. White light in
            // (HEAD hue kept as a faint tint); the silhouette rim disperses
            // into the band of the tail rooted behind that rim angle
            // (tail i points along +phase_i in xy, band_i = i / count).
            let rim_band = fract(atan2(n.y, n.x) / TAU + 1.0);
            let rim_col = spectralBand(fract(rim_band + band_shift)) * 1.6;
            let core = mix(base_col, vec3<f32>(1.0), 0.65) * (0.25 + diff);
            col = mix(core, rim_col, fre);
        } else {
            // Prismatic Tails — Idea 1: each tail is one discrete spectral band;
            // Idea 2: the travelling heartbeat lights the tail as it passes. Bass glow (HEAD).
            let tail_col = spectralBand(fract(band + band_shift));
            col = tail_col * (diff + fre * 2.0) * (1.0 + PULSE_GLOW * 0.4 * pulse) + vec3<f32>(glow * bass);
        }
    }

    // Volumetric glow and space dust — treble/FFT shimmer
    let hue_glow = p_prism_hue - time * 0.2;
    let glow_col = vec3<f32>(0.5 + 0.5 * sin(hue_glow * TAU + vec3<f32>(0.0, 2.0, 4.0)));
    let glow_mix = glow_col * glow * 0.25 + glow_rgb * 0.75; // Idea 1: spectral fan halo
    col += glow_mix * (1.5 + treble * 0.8 + fft * 0.4);

    // ── Temporal ping-pong feedback (HDR, textureLoad-only) ─────
    let tex_uv = (vec2<f32>(pixel) + 0.5) / res;
    let from_center = tex_uv - vec2<f32>(0.5);
    let dist_center = length(from_center);
    let center_dir = from_center / max(dist_center, 0.0001);
    let displacement = center_dir
        * sin(dist_center * ECHO_DISP_FREQ - time * ECHO_DISP_SPEED)
        * ECHO_DISP_AMP * p_echo * (1.0 + burst * 0.5);
    let prev_uv = clamp(tex_uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let prev_px = vec2<i32>(prev_uv * (res - vec2<f32>(1.0)));
    let prev_frame = textureLoad(dataTextureC, prev_px, 0).rgb;

    // Prismatic color shift on the feedback
    let shifted_prev = prev_frame * vec3<f32>(0.99, 0.95, 0.9);
    col = mix(col, shifted_prev, ECHO_MIX * p_echo * (1.0 - bass * 0.3));
    col = min(col, vec3<f32>(HDR_CEIL)); // keep HDR feedback chain bounded

    // ── Real generated depth (hit distance + glow relief) ───────
    // FIX: near = 1.0, miss = 0.0 (HEAD was inverted: t/FAR on hit, 1.0 on miss)
    let depth_hit = clamp(1.0 - t / FAR_CLIP, 0.0, 1.0);
    let depth_val = select(0.0, depth_hit, hit_surface);
    let depth_out = clamp(depth_val + glow * 0.05, 0.0, 1.0);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_out, 0.0, 0.0, 0.0));

    // ── Semantic alpha: intensity of presence (hit + glow + luma) ──
    let lum_hdr = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(0.1 + lum_hdr * 0.6 + glow * 0.25 + select(0.0, 0.35, hit_surface), 0.0, 1.0);

    // HDR history for next frame's feedback (A = primary state)
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));

    // Presentation-only: ACES tone map at the end of the chain
    let ldr = acesToneMap(col * (0.9 + mids * 0.25 + fft * 0.15));
    textureStore(writeTexture, pixel, vec4<f32>(ldr, alpha));
}
