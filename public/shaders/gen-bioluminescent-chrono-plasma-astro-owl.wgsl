// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Chrono-Plasma Astro-Owl
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: frame-dragged sky (core gravity twist swirls nebula + lattice); lattice plumage (sky lattice etched on the owl); nebula-dissolve fog (distance + silhouette melt into the real sky)
//  A packing: HDR linear RGB (pre-ACES echo history) + semantic alpha; C read back as HDR
// ═══════════════════════════════════════════════════════════════════
// History: 2026-08-03 Interactivist b31 — mouse-orbit camera, click-ripple
// SDF deformation, FFT wing fold, tessellation layer, real depth + alpha.
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

// Shared chrono-tessellation lattice (one lattice for sky and plumage).
// v = a direction's xy; folds counted by mids, cells drift with time.
fn chronoLattice(v: vec2<f32>, time: f32, snd: vec4<f32>) -> f32 {
    let folds = 6.0 + floor(snd.y * 4.0);
    let kuv = kaleido(v * 1.6, folds);
    let cell = fract(kuv * 3.0 + vec2<f32>(time * 0.05, time * 0.03)) - 0.5;
    return 1.0 - smoothstep(0.02, 0.09, abs(length(cell) - 0.28));
}

// Core gravity twist about world Y: angle = g/(r+0.1) (bass-swelled) + ripple kick.
fn coreTwistAngle(r: f32, snd: vec4<f32>, rip: f32) -> f32 {
    return u.zoom_params.y * (1.0 / (r + 0.1)) * (1.0 + snd.x * 0.5) + rip * 2.0;
}

fn twistY(v: vec3<f32>, ang: f32) -> vec3<f32> {
    let c = cos(ang);
    let s = sin(ang);
    return vec3<f32>(v.x * c - v.z * s, v.y, v.x * s + v.z * c);
}

// The SDF for the Owl
// snd = (bass, mids, treble, fftWingBand); rip = click-ripple displacement
fn map(p: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec2<f32> {
    var q = p;

    let t = u.config.x;
    let bass = snd.x;

    // Core gravity well bending space around the owl (fixed stale-read rotation)
    q = twistY(q, coreTwistAngle(length(q), snd, rip));

    // Bass pulse breathes the whole chrono-plasma body
    let breathe = 1.0 + bass * 0.12;
    q = q / breathe;

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

    // Distance was measured in breathe-scaled space: scale back to world units.
    return vec2<f32>(d * breathe, mat_id);
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
// Step 0.8 + 128 iterations: the core twist and fbm feathers are not 1-Lipschitz.
// Step exhaustion near a surface counts as a hit; exhaustion in open space is a miss
// (HEAD shaded exhausted rays as mat 0 -> black holes).
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec2<f32> {
    var t = 0.0;
    var mat_id = 0.0;
    var hit = false;
    var last_d = 1e9;
    var last_m = 0.0;
    for (var i = 0; i < 128; i++) {
        let p = ro + rd * t;
        let d = map(p, snd, rip);
        last_d = d.x;
        last_m = d.y;
        if (d.x < 0.001) {
            mat_id = d.y;
            hit = true;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d.x * 0.8;
    }
    if (!hit && t < MAX_DIST && last_d < 0.02) {
        hit = true;
        mat_id = last_m;
    }
    if (!hit) { return vec2<f32>(-1.0, 0.0); }
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
    let lattice = chronoLattice(rd.xy, time, snd);
    col += vec3<f32>(0.05, 0.3, 0.45) * lattice * particle_density * (0.25 + snd.w * 0.9);

    return col;
}

// Idea 1: Frame-dragged sky — the SAME g/(r+0.1) twist that bends the owl's SDF is
// applied to every view ray about the owl's core, using the ray's closest approach
// to the core as r. Rays grazing the silhouette are dragged furthest, so the nebula
// and the chrono-lattice shear into a vortex around the owl. Core Gravity (y) is the
// strength; click ripples kick it exactly as they kick the SDF. y = 0 → HEAD sky.
fn dragSky(ro: vec3<f32>, rd: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec3<f32> {
    let b = max(-dot(ro, rd), 0.0);
    let r_min = length(ro + rd * b);
    return normalize(twistY(rd, coreTwistAngle(r_min, snd, rip)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
    // Pixel rows run top-down; flip so world +Y (the owl's head) is screen-up
    // (HEAD rendered the owl upside down).
    let rd = cam * normalize(vec3<f32>(uv.x, -uv.y, -1.0));

    // Idea 1: every background lookup uses the frame-dragged direction.
    let rd_sky = dragSky(ro, rd, snd, rip);
    let sky = getNebula(ro, rd_sky, time, snd) * (1.0 + bass * 0.3 + rip * 0.8);

    let hit = raymarch(ro, rd, snd, rip);
    let t = hit.x;
    let mat_id = hit.y;

    var col = vec3<f32>(0.0);
    var depth = 0.0; // miss / far = 0
    var solidity = 0.0;

    if (t > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, snd, rip);
        let l = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, l), 0.0);

        let view_dir = normalize(ro - p);
        let rim = 1.0 - max(dot(n, view_dir), 0.0);
        let rim_power = pow(rim, 3.0);

        if (mat_id == 2.0) {
            // Eyes (Glowing shattered glass) — treble shimmer
            let eye_glow = vec3<f32>(0.1, 1.0, 0.8) * (1.0 + treble * 2.0 + fft_air);
            let spec = pow(max(dot(reflect(-l, n), view_dir), 0.0), 32.0);
            col = eye_glow + vec3<f32>(spec);
        } else {
            // Owl Body (Bioluminescent cyber-organic); mix factor clamped (HEAD
            // extrapolated below y=-1 → negative red → NaN after gamma).
            var baseCol = mix(vec3<f32>(0.05, 0.2, 0.5), vec3<f32>(0.4, 0.1, 0.6), clamp(p.y * 0.5 + 0.5, 0.0, 1.0));
            // SSS approx
            let sss = pow(rim, 2.0) * vec3<f32>(0.2, 0.8, 1.0) * (0.5 + bass);
            col = baseCol * diff + sss + rim_power * vec3<f32>(0.3, 0.1, 0.5) * (0.4 + mids);

            // Idea 2: Lattice plumage — the sky's chrono-lattice is etched onto the
            // body and wings as emissive cell edges. It is indexed by the direction
            // from the core in the owl's own twisted, breathing frame, so it rides
            // the flap/twist with the plumage while staying the same lattice
            // (same folds, same drift) as the sky behind it.
            let q_obj = twistY(p, coreTwistAngle(length(p), snd, rip)) / (1.0 + bass * 0.12);
            let plume_dir = normalize(q_obj + vec3<f32>(0.0, 0.0, 1e-4));
            let plume = chronoLattice(plume_dir.xy * 1.35, time, snd);
            let plume_glow = 0.55 + 0.45 * (1.0 - diff) + snd.w * 0.9;
            col += vec3<f32>(0.05, 0.3, 0.45) * plume * plume_glow;
        }

        // Bloom from core gravity well
        let dist_to_center = length(p);
        let bloom = exp(-dist_to_center * 1.5) * vec3<f32>(0.8, 0.2, 1.0) * (bass * 2.0 + rip * 1.5);
        col += bloom;

        // Idea 3: Nebula-dissolve fog — distance fog and a silhouette fringe both
        // blend toward the ACTUAL frame-dragged sky behind the pixel (HEAD used a
        // flat purple), so distant feathers and the owl's outline melt into the
        // swirling nebula/lattice instead of a painted-on haze.
        let fog_factor = clamp(1.0 - exp(-0.02 * t * t) + 0.4 * pow(rim, 4.0), 0.0, 0.85);
        col = mix(col, sky, fog_factor);
        solidity = 1.0 - fog_factor;

        // Real depth: near = 1, far = 0
        depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    } else {
        col = sky;
    }

    // Temporal Echo Fade slider: feedback from last frame's HDR history.
    // A/C now hold linear HDR (HEAD stored Reinhard+gamma output and re-toned it
    // every frame → a grey floor ~0.13 at echo 0.2 that never decayed).
    let echo_fade = u.zoom_params.w;
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.94, clamp(echo_fade, 0.0, 1.0) * 0.45);
    col = max(col, vec3<f32>(0.0));

    // Display: ACES then gamma (HEAD's Reinhard+gamma replaced)
    let display = pow(max(acesToneMap(col * 0.8), vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));

    // Semantic alpha: owl solid, fog/glow translucent from luma
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let glow_alpha = clamp(luma * 0.7 + 0.25, 0.0, 1.0);
    let alpha = mix(glow_alpha, 1.0, solidity);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
