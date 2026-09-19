// ----------------------------------------------------------------
// Symbiotic Bismuth-Crystal Dragon-Core
// Category: generative
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
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4 (mapped from UI sliders)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;

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

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Sliders
    let zoom_level = u.zoom_params.x; // default 1.0
    let complexity = u.zoom_params.y; // default 3.0
    let breathing_speed = u.zoom_params.z; // default 0.5
    let iridescence_shift = u.zoom_params.w; // default 0.0

    // Time and breathing
    let t = u.config.x;
    let audio_bass = extraBuffer[0] * 0.005;
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

    // Box SDF for crystal
    let d_box = length(max(abs(bp) - vec3<f32>(0.5), vec3<f32>(0.0))) / scale;
    let crystal_dist = d_box * zoom_level * breathe;


    // 2. Fluid liquid-gold organic sinews
    var sp = p;
    let r3 = rot(t * 0.2);
    let spxy = r3 * vec2<f32>(sp.x, sp.y);
    sp = vec3<f32>(spxy.x, spxy.y, sp.z);

    // volumetric noise / capsules
    let sinew_base = length(sp.xy) - 0.3;
    let noise = sin(sp.x*5.0) * sin(sp.y*5.0) * sin(sp.z*5.0) * 0.1;
    let sinew_dist = (sinew_base + noise) * zoom_level * breathe;


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

    let base_uv = vec2<f32>(f32(gid.x), f32(gid.y)) / res.xy;
    let uv = (base_uv - 0.5) * vec2<f32>(res.x / res.y, 1.0);

    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var p = ro;
    var t_dist = 0.0;
    var mat_id = -1.0;
    var ao = 1.0;
    var steps = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let res_map = map(p);
        let d = res_map.x;
        mat_id = res_map.y;

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

    if (mat_id >= 0.0) {
        let n = getNormal(p);
        let v = -rd;
        let ndotv = max(dot(n, v), 0.0);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, light), 0.0);

        if (mat_id < 0.5) {
            // Crystal (Bismuth)
            let iridescence_shift = u.zoom_params.w;
            let iri = palette(ndotv * 2.0 + u.config.x * 0.1 + iridescence_shift);
            let spec = pow(ndotv, 16.0);
            col = iri * (dif * 0.5 + 0.5) + spec * 0.5;
        } else {
            // Sinew (Liquid Gold)
            let gold = vec3<f32>(1.0, 0.7, 0.2);
            let spec = pow(ndotv, 32.0);
            let emission = vec3<f32>(0.8, 0.2, 0.0) * (1.0 - ndotv) * 0.5;
            col = gold * dif + spec + emission;
        }

        // Ambient Occlusion
        col *= ao * ao;

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), 1.0 - exp(-0.02 * t_dist * t_dist));
    }

    // Audio reaction flash
    col += vec3<f32>(0.1, 0.05, 0.2) * extraBuffer[0] * 0.002 * (1.0 - min(t_dist/10.0, 1.0));

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(col, 1.0));
}
