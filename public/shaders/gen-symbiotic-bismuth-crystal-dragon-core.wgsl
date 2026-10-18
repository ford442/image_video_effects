// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Bismuth-Crystal Dragon-Core
//  Category: generative
//  Features: audio-reactive, mouse-driven, raymarched, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: ichor seep along the symbiotic crystal/sinew seam; peristaltic
//         lub-dub heart-bolus travelling down the sinew artery; furnace
//         underlight + heat haze from the artery through the labyrinth
//  A packing: ACES display RGBA (alpha = surface coverage x fog
//             transmission + core haze); stateless, no C read
//  Fix: camera sat inside the infinite sinew cylinder (every ray hit at
//       step 0 -> flat gold wash); artery is now capped at world z=-2.5
//       and bores a lumen through the crystal. Audio was extraBuffer[0].
// ═══════════════════════════════════════════════════════════════════
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
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4 (mapped from UI sliders)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;
const ARTERY_MOUTH_Z = -2.5;   // world-space cap of the sinew artery (camera is at z=-4)
const LUMEN_RADIUS = 0.6;      // channel the artery bores through the labyrinth (folded space)

// Per-evaluation side channels written by map() (read after the march / at the hit).
var<private> g_seam: f32;      // [IDEA 1] smin blend weight 4h(1-h): 1 on the crystal/sinew seam
var<private> g_gap: f32;       // [IDEA 1] sinew-minus-crystal distance (folded units)
var<private> g_bolus: f32;     // [IDEA 2] heart-bolus bump at this point of the artery
var<private> g_sinew: f32;     // [IDEA 3] signed distance to the artery (world units)

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Bismuth iridescence palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// [IDEA 2] Lub-dub cardiac pulse train along the artery axis. Phase advances with time so a fixed
// phase moves toward -z, i.e. each bolus rushes down the artery toward the viewer.
fn heartBolus(z: f32, t: f32, rate: f32) -> f32 {
    let f = fract(z * 0.4 + t * rate);
    let a = (f - 0.50) / 0.07; // squared by hand: pow() of a negative base is NaN in WGSL
    let b = (f - 0.68) / 0.05;
    let lub = exp(-a * a);
    let dub = exp(-b * b) * 0.6;
    return lub + dub;
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Sliders
    let zoom_level = u.zoom_params.x; // default 1.0
    let complexity = u.zoom_params.y; // default 3.0
    let breathing_speed = u.zoom_params.z; // default 0.5
    let iridescence_shift = u.zoom_params.w; // default 0.0

    // Time and breathing
    let t = u.config.x;
    let audio_bass = plasmaBuffer[0].x * 0.5;
    let breathe = sin(t * breathing_speed + audio_bass) * 0.1 + 1.0;

    p /= zoom_level * breathe;

    // Mouse interaction - volumetric gravity well
    let mouse_uv = u.zoom_config.yz;
    if (mouse_uv.x > 0.0 && mouse_uv.y > 0.0) {
        let mouse_pos = vec3<f32>((mouse_uv.x - 0.5) * 5.0, -(mouse_uv.y - 0.5) * 5.0, -2.0);
        let d2m = length(p - mouse_pos);
        if (d2m < 2.0) {
             let pull = 1.0 - smoothstep(0.0, 2.0, d2m);
             p += (mouse_pos - p) * pull * 0.5;
        }
    }

    var res = vec2<f32>(MAX_DIST, -1.0);

    // 1. Rigid Crystalline Bismuth structures (fractal folds)
    var bp = p;
    var scale = 1.0;

    // Modulo space repetition
    let repeat = 4.0;
    bp = fract(bp/repeat + 0.5) * repeat - repeat/2.0;

    let iters = i32(complexity);
    for (var i = 0; i < 8; i++) {
        if (i >= iters) { break; }

        bp = abs(bp) - 0.5;

        let r1 = rot(t * 0.1 + f32(i) * 0.2);
        let bpxz = r1 * vec2<f32>(bp.x, bp.z);
        bp = vec3<f32>(bpxz.x, bp.y, bpxz.y);

        let r2 = rot(t * 0.15 + f32(i) * 0.3);
        let bpyz = r2 * vec2<f32>(bp.y, bp.z);
        bp = vec3<f32>(bp.x, bpyz.x, bpyz.y);

        // stepped domain modulation for bismuth
        bp = floor(bp * 5.0) / 5.0 + fract(bp * 5.0) * 0.2 / 5.0;

        bp *= 1.5;
        scale *= 1.5;
    }

    // 2. Fluid liquid-gold organic sinews
    var sp = p;
    let r3 = rot(t * 0.2);
    let spxy = r3 * vec2<f32>(sp.x, sp.y);
    sp = vec3<f32>(spxy.x, spxy.y, sp.z);
    let sp_r = length(sp.xy);

    // Box SDF for crystal
    let d_box = length(max(abs(bp) - vec3<f32>(0.5), vec3<f32>(0.0))) / scale;
    // Fix: the artery bores a lumen through the labyrinth so it is seen running down a channel.
    let crystal_dist = max(d_box, LUMEN_RADIUS - sp_r) * zoom_level * breathe;

    // [IDEA 2] Peristaltic heart-bolus: the artery wall bulges as each lub-dub pulse passes.
    let heart_rate = 0.05 + breathing_speed * 0.6;
    let bolus = heartBolus(sp.z, t, heart_rate);
    let bulge = 1.0 + (0.22 + plasmaBuffer[0].x * 0.2) * bolus;

    // volumetric noise / capsules
    // Fix: HEAD's infinite z-cylinder swallowed the camera; cap it at a world-space mouth.
    let mouth_cap = (ARTERY_MOUTH_Z - p_in.z) / (zoom_level * breathe);
    let sinew_base = max(sp_r - 0.3 * bulge, mouth_cap);
    let noise = sin(sp.x*5.0) * sin(sp.y*5.0) * sin(sp.z*5.0) * 0.1;
    let sinew_dist = (sinew_base + noise) * zoom_level * breathe;

    // [IDEA 1] symbiotic seam weight = the smin blend region between the two bodies.
    let seam_h = clamp(0.5 + 0.5 * (sinew_dist - crystal_dist) / (0.2 * zoom_level), 0.0, 1.0);
    g_seam = 4.0 * seam_h * (1.0 - seam_h);
    g_gap = max(sinew_dist - crystal_dist, 0.0) / (zoom_level * breathe);
    g_bolus = bolus;
    g_sinew = sinew_dist;


    // Combine
    if (crystal_dist < sinew_dist) {
        res = vec2<f32>(crystal_dist, 0.0); // 0 = crystal
    } else {
        res = vec2<f32>(sinew_dist, 1.0); // 1 = sinew
    }

    // Smooth blend between them
    let blended_dist = smin(crystal_dist, sinew_dist, 0.2 * zoom_level);

    // Determine material based on which one is closer, but use blended dist
    if (crystal_dist - 0.1 < sinew_dist) {
        res = vec2<f32>(blended_dist, 0.0);
    } else {
         res = vec2<f32>(blended_dist, 1.0);
    }

    return res;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) {
        return;
    }
    let pixel = vec2<i32>(gid.xy);
    let bass = plasmaBuffer[0].x;

    let base_uv = vec2<f32>(f32(gid.x), f32(gid.y)) / res.xy;
    let uv = (base_uv - 0.5) * vec2<f32>(res.x / res.y, 1.0);

    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var p = ro;
    var t_dist = 0.0;
    var mat_id = -1.0;
    var ao = 1.0;
    var steps = 0.0;
    var haze = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let res_map = map(p);
        let d = res_map.x;
        mat_id = res_map.y;

        // [IDEA 3] heat haze: rays grazing the artery soak up its glow (brighter as a bolus passes).
        haze += exp(-abs(g_sinew) * 6.0) * (0.25 + g_bolus) * min(max(d, 0.0), 0.3) * 0.5;

        if (d < SURF_DIST) {
            ao = 1.0 - f32(i) / f32(MAX_STEPS);
            break;
        }
        if (t_dist > MAX_DIST) {
            mat_id = -1.0;
            break;
        }

        t_dist += d;
        p = ro + rd * t_dist;
        steps += 1.0;
    }

    var col = vec3<f32>(0.05, 0.05, 0.1); // Background
    var fog_amt = 1.0;
    let hit = mat_id >= 0.0;

    if (hit) {
        let n = getNormal(p);
        let hit_info = map(p); // refresh g_* side channels at the hit (getNormal overwrote them)
        let v = -rd;
        let ndotv = max(dot(n, v), 0.0);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, light), 0.0);
        let zoom_level = u.zoom_params.x;
        let breathe = sin(u.config.x * u.zoom_params.z + bass * 0.5) * 0.1 + 1.0;

        if (hit_info.y < 0.5) {
            // Crystal (Bismuth)
            let iridescence_shift = u.zoom_params.w;
            let iri = palette(ndotv * 2.0 + u.config.x * 0.1 + iridescence_shift);
            let spec = pow(ndotv, 16.0);
            col = iri * (dif * 0.5 + 0.5) + spec * 0.5;

            // [IDEA 1] Ichor seep: molten gold wicks out of the seam into the bismuth, fingering
            // along capillaries; the seam line itself glows, pumped by the heart-bolus.
            let finger = 0.5 + 0.5 * sin(p.x * 9.0 + sin(p.y * 7.0 + u.config.x * 0.3) * 2.0 + p.z * 5.0);
            let wick = exp(-g_gap * 3.5) * (0.6 + 0.6 * finger);
            let stain = smoothstep(0.35, 0.85, wick);
            let gold = vec3<f32>(1.0, 0.7, 0.2);
            col = mix(col, gold * (0.35 + 0.65 * dif) + spec * 0.6, stain * 0.75);
            col += vec3<f32>(1.0, 0.38, 0.06) * g_seam * (0.5 + 1.1 * g_bolus);

            // [IDEA 3] Furnace underlight: facets facing the artery axis catch its heat, swelling
            // as each bolus passes this depth.
            let radial = vec3<f32>(p.x, p.y, 0.0);
            let to_axis = -radial / max(length(radial), 1e-4);
            let facing = max(dot(n, to_axis), 0.0);
            let rr = length(p.xy) / (zoom_level * breathe);
            let core_light = exp(-max(rr - 0.3, 0.0) * 2.2) * facing * (0.3 + 0.9 * g_bolus);
            col += vec3<f32>(1.0, 0.42, 0.1) * core_light;
        } else {
            // Sinew (Liquid Gold)
            let gold = vec3<f32>(1.0, 0.7, 0.2);
            let spec = pow(ndotv, 32.0);
            let emission = vec3<f32>(0.8, 0.2, 0.0) * (1.0 - ndotv) * 0.5;
            col = gold * dif + spec + emission;

            // [IDEA 2] bolus heat: the swollen wall runs white-hot; the artery mouth flares
            // when a pulse arrives there.
            let mouth = smoothstep(0.35, 0.0, p.z - ARTERY_MOUTH_Z);
            col += vec3<f32>(1.0, 0.45, 0.08) * g_bolus * (0.6 + bass) * (1.0 + 1.5 * mouth);
        }

        // Ambient Occlusion
        col *= ao * ao;

        // Fog
        fog_amt = 1.0 - exp(-0.02 * t_dist * t_dist);
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), fog_amt);
    }

    // [IDEA 3] core heat haze glows through the labyrinth gaps
    col += vec3<f32>(1.0, 0.5, 0.15) * haze;

    // Audio reaction flash
    col += vec3<f32>(0.1, 0.05, 0.2) * bass * 0.8 * (1.0 - min(t_dist/10.0, 1.0));

    col = acesToneMap(col);
    let coverage = select(0.0, 1.0 - fog_amt, hit);
    let alpha = clamp(0.1 + coverage * 0.9 + haze, 0.0, 1.0); // semantic alpha: surface x fog + haze
    let depth = select(0.0, clamp(1.0 - t_dist / 20.0, 0.0, 1.0), hit);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
