// ----------------------------------------------------------------
// Bioluminescent Chrono-Plasma Astro-Owl
// Category: generative
// Upgraded: 2026-08-03 — Interactivist b31: mouse-orbit camera, click-ripple
// SDF deformation, FFT wing fold, tessellation layer, real depth + alpha.
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV (0-1, y=0 top), w=MouseDown
    zoom_params: vec4<f32>,  // x=Wing Plasma Distortion, y=Core Gravity Intensity, z=Nebula Particle Density, w=Temporal Echo Fade
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_DIST: f32 = 20.0;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

// Pseudo-random function
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    let r = q + dot(q, q.yzx + 33.33);
    return fract((r.x + r.y) * r.z);
}

// Smooth minimum
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Noise for volumetric fBM
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), w.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), w.x), w.y),
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), w.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), w.x), w.y), w.z);
}

// Fractal Brownian Motion
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_warp = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(p_warp);
        p_warp = p_warp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Engine FFT bins live at extraBuffer[5..132] (bin 0 at [5]) — read-only.
fn fftBin(i: u32) -> f32 {
    let idx = clamp(5u + i, 5u, 132u);
    if (idx < arrayLength(&extraBuffer)) {
        return extraBuffer[idx];
    }
    return 0.0;
}

// Click-ripple deformation field (0-1 uv space, y=0 top — matches engine ripples).
fn rippleField(uv01: vec2<f32>, time: f32) -> f32 {
    var acc = 0.0;
    let n = min(u32(u.config.y), 50u);
    for (var i = 0u; i < n; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < 4.0) {
            let d = distance(uv01, rp.xy);
            let wave = d - age * 0.45;
            acc += exp(-wave * wave * 90.0) * exp(-age * 1.4);
        }
    }
    return min(acc, 1.5);
}

// 2D kaleidoscopic symmetry fold for the chrono-tessellation layer.
fn kaleido(uv: vec2<f32>, folds: f32) -> vec2<f32> {
    let ang = atan2(uv.y, uv.x);
    let rad = length(uv);
    let fa = abs(fract(ang / TAU * folds + 0.5) - 0.5) / folds * TAU;
    return vec2<f32>(cos(fa), sin(fa)) * rad;
}

// The SDF for the Owl
// snd = (bass, mids, treble, fftWingBand); rip = click-ripple displacement
fn map(p: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec2<f32> {
    var q = p;

    let t = u.config.x;
    let bass = snd.x;
    let core_gravity = u.zoom_params.y;

    // Core gravity well bending space around the owl (fixed stale-read rotation)
    let dist_to_core = length(q);
    let gravity_warp = core_gravity * (1.0 / (dist_to_core + 0.1)) * (1.0 + bass * 0.5) + rip * 2.0;
    let gq_x = q.x * cos(gravity_warp) - q.z * sin(gravity_warp);
    let gq_z = q.x * sin(gravity_warp) + q.z * cos(gravity_warp);
    q.x = gq_x;
    q.z = gq_z;

    // Bass pulse breathes the whole chrono-plasma body
    q = q / (1.0 + bass * 0.12);

    // Owl Body (composite SDF)
    // Central ellipsoid body
    let body_scale = vec3<f32>(0.6, 1.0, 0.5);
    let body_dist = length(q / body_scale) - 1.0;
    var d = body_dist * min(min(body_scale.x, body_scale.y), body_scale.z);

    // Head
    let head_pos = q - vec3<f32>(0.0, 0.9, 0.1);
    let head_dist = length(head_pos) - 0.45;
    d = smin(d, head_dist, 0.3);

    // Wings (Ethereal fractal wings) — FFT band folds the feather lattice
    let wing_flap = sin(t * 2.0) * 0.5 + bass * 0.35;
    var wing_q = q;
    // Wing mirroring and flapping
    wing_q.x = abs(wing_q.x) - 0.5;
    wing_q.y -= wing_q.x * wing_flap;
    // Symmetry fold: treble-band twists the wing plane into a feather helix
    let fold_twist = snd.w * 1.5 + snd.z * 0.6 + rip * 3.0;
    let wq_xy = wing_q.xy * rot2D(fold_twist * wing_q.x);
    wing_q = vec3<f32>(wq_xy.x, wq_xy.y, wing_q.z);

    // Domain warping for plasma feathers
    let wing_distortion = u.zoom_params.x;
    let feather_fbm = fbm(wing_q * 5.0 + t) * wing_distortion * 0.2;

    // Wing structure (flat, elongated box)
    let wing_width = 1.2;
    let wing_box = abs(wing_q) - vec3<f32>(wing_width, 0.05, 0.3);
    let wing_base = length(max(wing_box, vec3<f32>(0.0))) + min(max(wing_box.x, max(wing_box.y, wing_box.z)), 0.0);
    let final_wing = wing_base + feather_fbm;

    d = smin(d, final_wing, 0.1);

    // Bioluminescent geometric eyes (shattered glass) — treble faceting
    let eye_pos = head_pos;
    var eye_q = eye_pos;
    eye_q.x = abs(eye_q.x) - 0.2;
    eye_q -= vec3<f32>(0.0, 0.1, 0.35);
    let eye_dist = (length(eye_q) - 0.1) / (1.0 + snd.z * 0.3);

    // Click ripples dent the quantum-glass plumage
    d -= rip * 0.22 * (1.0 + bass * 0.5);

    // Mat id logic
    var mat_id = 1.0; // Body
    if (eye_dist < d) {
        d = eye_dist;
        mat_id = 2.0; // Eyes
    }

    return vec2<f32>(d, mat_id);
}

// Normal calculation
fn calcNormal(p: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, snd, rip).x - map(p - e.xyy, snd, rip).x,
        map(p + e.yxy, snd, rip).x - map(p - e.yxy, snd, rip).x,
        map(p + e.yyx, snd, rip).x - map(p - e.yyx, snd, rip).x
    ));
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec2<f32> {
    var t = 0.0;
    var mat_id = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, snd, rip);
        if (d.x < 0.001) {
            mat_id = d.y;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d.x;
    }
    if (t > MAX_DIST) { t = -1.0; }
    return vec2<f32>(t, mat_id);
}

// Volumetric background (Dark matter nebula + chrono-tessellation layer)
fn getNebula(ro: vec3<f32>, rd: vec3<f32>, time: f32, snd: vec4<f32>) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var p = ro + rd * 5.0;
    let particle_density = u.zoom_params.z;

    for (var i = 0; i < 5; i++) {
        // Twist space for the nebula — mids drive the swirl rate
        let warp = sin(p.y * 0.5 + time) * 0.5 + snd.y * 0.4;
        let r_mat = rot2D(warp);
        let tmp_x = p.x * r_mat[0][0] + p.z * r_mat[1][0];
        let tmp_z = p.x * r_mat[0][1] + p.z * r_mat[1][1];
        p.x = tmp_x;
        p.z = tmp_z;

        let n = fbm(p * 0.5 + time * 0.2);
        col += vec3<f32>(0.1, 0.05, 0.2) * (1.0 - n) * particle_density;
        p += rd * 2.0;
    }

    // 2D chrono-tessellation: kaleidoscopic hex-fold lattice behind the owl,
    // folds counted by mids, cells shimmered by the high FFT band.
    let folds = 6.0 + floor(snd.y * 4.0);
    let kuv = kaleido(rd.xy * 1.6, folds);
    let cell = fract(kuv * 3.0 + vec2<f32>(time * 0.05, time * 0.03)) - 0.5;
    let lattice = 1.0 - smoothstep(0.02, 0.09, abs(length(cell) - 0.28));
    col += vec3<f32>(0.05, 0.3, 0.45) * lattice * particle_density * (0.25 + snd.w * 0.9);

    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) {
        return;
    }

    let coord = vec2<i32>(id.xy);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;

    // Real audio: bands + engine FFT (read-only)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let fft_wing = (fftBin(12u) + fftBin(20u) + fftBin(28u)) / 3.0;
    let fft_air = (fftBin(80u) + fftBin(96u) + fftBin(112u)) / 3.0;
    let snd = vec4<f32>(bass, mids, treble, fft_wing);

    // Click ripples deform the geometry
    let rip = rippleField(uv01, time);

    // Mouse-orbit camera (mouse uv is 0-1, y=0 top — used directly, no flip)
    let yaw = (u.zoom_config.y - 0.5) * PI * 1.4 + time * 0.08;
    let pitch = (u.zoom_config.z - 0.5) * PI * 0.7;
    let cam = rotY(yaw) * rotX(pitch);

    var ro = cam * vec3<f32>(0.0, 0.0, 4.0);
    let rd = cam * normalize(vec3<f32>(uv, -1.0));

    let hit = raymarch(ro, rd, snd, rip);
    let t = hit.x;
    let mat_id = hit.y;

    var col = vec3<f32>(0.0);
    var depth = textureLoad(readDepthTexture, coord, 0).r; // passthrough for misses

    if (t > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, snd, rip);
        let l = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, l), 0.0);

        let view_dir = normalize(ro - p);
        let rim = 1.0 - max(dot(n, view_dir), 0.0);
        let rim_power = pow(rim, 3.0);

        if (mat_id == 1.0) {
            // Owl Body (Bioluminescent cyber-organic)
            var baseCol = mix(vec3<f32>(0.05, 0.2, 0.5), vec3<f32>(0.4, 0.1, 0.6), p.y * 0.5 + 0.5);
            // SSS approx
            let sss = pow(rim, 2.0) * vec3<f32>(0.2, 0.8, 1.0) * (0.5 + bass);
            col = baseCol * diff + sss + rim_power * vec3<f32>(0.3, 0.1, 0.5) * (0.4 + mids);
        } else if (mat_id == 2.0) {
            // Eyes (Glowing shattered glass) — treble shimmer
            let eye_glow = vec3<f32>(0.1, 1.0, 0.8) * (1.0 + treble * 2.0 + fft_air);
            let spec = pow(max(dot(reflect(-l, n), view_dir), 0.0), 32.0);
            col = eye_glow + vec3<f32>(spec);
        }

        // Bloom from core gravity well
        let dist_to_center = length(p);
        let bloom = exp(-dist_to_center * 1.5) * vec3<f32>(0.8, 0.2, 1.0) * (bass * 2.0 + rip * 1.5);
        col += bloom;

        // Distance fog integrating into nebula
        let fog_factor = 1.0 - exp(-0.02 * t * t);
        col = mix(col, vec3<f32>(0.05, 0.0, 0.1), fog_factor);

        // Real depth: near = 1, far = 0
        depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    } else {
        col = getNebula(ro, rd, time, snd);
        col *= (1.0 + bass * 0.3 + rip * 0.8);
    }

    // Temporal Echo Fade slider: feedback from last frame's buffer
    let echo_fade = u.zoom_params.w;
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.94, clamp(echo_fade, 0.0, 1.0) * 0.45);

    // Tonemapping and Gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha from luma (glow stays translucent, creature stays solid)
    let luma = dot(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.25, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
