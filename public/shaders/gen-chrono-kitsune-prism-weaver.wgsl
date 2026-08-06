// ----------------------------------------------------------------
// Chrono-Kitsune Prism Weaver
// Category: generative
// Features: raymarching, volumetric-glow, temporal-feedback (textureLoad),
//           hdr-feedback, aces-tone-map, semantic-alpha, generated-depth,
//           audio-reactive, interactive-mouse, bounded-march, early-out
// Optimizer pass (Batch 37): bounding-sphere early-out, tetrahedral
//           normals (4 taps instead of 6), hoisted frame-uniform terms,
//           named constants, HDR feedback chain, fixed mouse-uniform truth.
// ----------------------------------------------------------------
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

// ── Bounding volume for ray early-out (covers body + tail arcs) ──
const BOUND_C: vec3<f32> = vec3<f32>(0.0, 0.0, 14.5);
const BOUND_R: f32 = 12.0;

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

// SDF: kitsune body + prismatic tail fan. tail_count and weave are
// hoisted per-frame (computed once in main, uniform across the march).
fn mapKitsune(p: vec3<f32>, time: f32, tail_count: i32, weave: f32) -> vec2<f32> {
    // Kitsune central body
    let bp = p - BODY_POS;
    let ripple = sin(bp.x * BODY_DETAIL_FREQ + time)
               * sin(bp.y * BODY_DETAIL_FREQ + time)
               * sin(bp.z * BODY_DETAIL_FREQ + time);
    let d_body = (length(bp) - BODY_RADIUS) + BODY_DETAIL_AMP * ripple;

    // Prismatic tails (bounded 3–9 by slider)
    var d_tails = 1000.0;
    let inv_count = 1.0 / f32(tail_count);
    for (var i = 0; i < tail_count; i = i + 1) {
        let phase = f32(i) * TAU * inv_count;
        var tp = p;
        tp.z -= TAIL_Z_START;
        let rotated_xy = rot2(phase) * tp.xy;
        tp = vec3<f32>(rotated_xy.x, rotated_xy.y, tp.z);
        tp.x -= TAIL_OFFSET;
        tp.x += sin(tp.z * weave * 0.5 - time * 2.0 + phase) * TAIL_WAVE_AMP;
        let d_cyl = length(tp.xy) - TAIL_RADIUS - tp.z * TAIL_TAPER;
        let z_bounds = max(-tp.z, tp.z - TAIL_Z_LEN);
        d_tails = smin(d_tails, max(d_cyl, z_bounds), TAIL_SMIN);
    }

    let is_body = d_body < d_tails;
    return vec2<f32>(smin(d_body, d_tails, BODY_SMIN), select(2.0, 1.0, is_body));
}

// Tetrahedral normal — 4 SDF taps instead of the 6-tap central difference.
fn calcNormal(p: vec3<f32>, time: f32, tail_count: i32, weave: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.01;
    return normalize(
        e.xyy * mapKitsune(p + e.xyy, time, tail_count, weave).x +
        e.yyx * mapKitsune(p + e.yyx, time, tail_count, weave).x +
        e.yxy * mapKitsune(p + e.yxy, time, tail_count, weave).x +
        e.xxx * mapKitsune(p + e.xxx, time, tail_count, weave).x
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
    let tail_count = i32(clamp(floor(p_tail_count * MAX_TAILS), MIN_TAILS, MAX_TAILS));
    let weave      = 1.0 + p_weave * 3.0;

    let uv = (vec2<f32>(pixel) - 0.5 * res) / res.y;

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
    var p = ro;
    var glow = 0.0;

    // Raymarching — bounded with early exits
    if (in_bounds) {
        for (var i = 0; i < RAY_STEPS; i = i + 1) {
            p = ro + rd * t;
            let hit = mapKitsune(p, time, tail_count, weave);
            d = hit.x;
            m = hit.y;

            if (m > 1.5) {
                glow += 0.02 / (1.0 + d * d * 50.0);
            }

            if (d < SURF_EPS) { break; }
            t += d * STEP_RELAX;
            if (t > FAR_CLIP) { break; }
        }
    }
    glow *= 1.0 + burst; // click-driven chrono burst

    var col = vec3<f32>(0.0);
    let hit_surface = in_bounds && t < FAR_CLIP;

    if (hit_surface) {
        let n = calcNormal(p, time, tail_count, weave);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let fre = pow(1.0 - max(dot(n, view), 0.0), 4.0);

        let hue = p_prism_hue + t * 0.1 - time * 0.5 + mids * 0.15;
        let base_col = vec3<f32>(0.5 + 0.5 * sin(hue * TAU + vec3<f32>(0.0, 2.0, 4.0)));

        if (m < 1.5) {
            // Kitsune Body
            col = mix(base_col * diff, vec3<f32>(1.0, 0.8, 1.0), fre);
        } else {
            // Prismatic Tails — bass-driven glow
            col = base_col * (diff + fre * 2.0) + vec3<f32>(glow * bass);
        }
    }

    // Volumetric glow and space dust — treble/FFT shimmer
    let hue_glow = p_prism_hue - time * 0.2;
    let glow_col = vec3<f32>(0.5 + 0.5 * sin(hue_glow * TAU + vec3<f32>(0.0, 2.0, 4.0)));
    col += glow_col * glow * (1.5 + treble * 0.8 + fft * 0.4);

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
    let depth_hit = clamp(t / FAR_CLIP, 0.0, 1.0);
    let depth_val = select(1.0, depth_hit, hit_surface);
    let depth_out = clamp(depth_val - glow * 0.05, 0.0, 1.0);
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
