// ----------------------------------------------------------------
// Bioluminescent Chrono-Plasma Astro-Owl
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Wing Plasma Distortion, y=Core Gravity Intensity, z=Nebula Particle Density, w=Temporal Echo Fade
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotation matrix 2D
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
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
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
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

// The SDF for the Owl
fn map(p: vec3<f32>) -> vec2<f32> {
    var q = p;

    // Mouse interaction - orbital gravity pulling the entire scene
    let mouse = u.zoom_config.yz;
    q -= vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    let t = u.config.x;
    let bass = plasmaBuffer[0].x; // Core acoustic reactivity
    let core_gravity = u.zoom_params.y;

    // Core gravity well bending space around the owl
    let dist_to_core = length(q);
    let gravity_warp = core_gravity * (1.0 / (dist_to_core + 0.1)) * (1.0 + bass * 0.5);
    let rot = rot2D(gravity_warp);
    q.x = q.x * cos(gravity_warp) - q.z * sin(gravity_warp);
    q.z = q.x * sin(gravity_warp) + q.z * cos(gravity_warp);

    // Owl Body (composite SDF)
    // Central ellipsoid body
    let body_scale = vec3<f32>(0.6, 1.0, 0.5);
    let body_dist = length(q / body_scale) - 1.0;
    var d = body_dist * min(min(body_scale.x, body_scale.y), body_scale.z);

    // Head
    let head_pos = q - vec3<f32>(0.0, 0.9, 0.1);
    let head_dist = length(head_pos) - 0.45;
    d = smin(d, head_dist, 0.3);

    // Wings (Ethereal fractal wings)
    let wing_flap = sin(t * 2.0) * 0.5;
    var wing_q = q;
    // Wing mirroring and flapping
    wing_q.x = abs(wing_q.x) - 0.5;
    wing_q.y -= wing_q.x * wing_flap;

    // Domain warping for plasma feathers
    let wing_distortion = u.zoom_params.x;
    let feather_fbm = fbm(wing_q * 5.0 + t) * wing_distortion * 0.2;

    // Wing structure (flat, elongated box)
    let wing_width = 1.2;
    let wing_box = abs(wing_q) - vec3<f32>(wing_width, 0.05, 0.3);
    let wing_base = length(max(wing_box, vec3<f32>(0.0))) + min(max(wing_box.x, max(wing_box.y, wing_box.z)), 0.0);
    let final_wing = wing_base + feather_fbm;

    d = smin(d, final_wing, 0.1);

    // Bioluminescent geometric eyes (shattered glass)
    let eye_pos = head_pos;
    var eye_q = eye_pos;
    eye_q.x = abs(eye_q.x) - 0.2;
    eye_q -= vec3<f32>(0.0, 0.1, 0.35);
    let eye_dist = length(eye_q) - 0.1;

    // Mat id logic
    var mat_id = 1.0; // Body
    if (eye_dist < d) {
        d = eye_dist;
        mat_id = 2.0; // Eyes
    }

    return vec2<f32>(d, mat_id);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat_id = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            mat_id = d.y;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d.x;
    }
    if (t > 20.0) { t = -1.0; }
    return vec2<f32>(t, mat_id);
}

// Volumetric background (Dark matter nebula)
fn getNebula(ro: vec3<f32>, rd: vec3<f32>, time: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var p = ro + rd * 5.0;
    let particle_density = u.zoom_params.z;
    let echo_fade = u.zoom_params.w;

    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        // Twist space for the nebula
        let warp = sin(p.y * 0.5 + time) * 0.5;
        let r_mat = rot2D(warp);
        let tmp_x = p.x * r_mat[0][0] + p.z * r_mat[1][0];
        let tmp_z = p.x * r_mat[0][1] + p.z * r_mat[1][1];
        p.x = tmp_x;
        p.z = tmp_z;

        let n = fbm(p * 0.5 + time * 0.2);
        // Inverted noise accumulation
        col += vec3<f32>(0.1, 0.05, 0.2) * (1.0 - n) * particle_density * (1.0 - echo_fade * 0.5);
        p += rd * 2.0;
    }
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;
    let time = u.config.x;

    var ro = vec3<f32>(0.0, 0.0, 4.0);
    let rd = normalize(vec3<f32>(uv, -1.0));

    let hit = raymarch(ro, rd);
    let t = hit.x;
    let mat_id = hit.y;

    var col = vec3<f32>(0.0);
    let bass = plasmaBuffer[0].x;
    let mid_highs = plasmaBuffer[1].x;

    if (t > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
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
            col = baseCol * diff + sss;
        } else if (mat_id == 2.0) {
            // Eyes (Glowing shattered glass)
            let eye_glow = vec3<f32>(0.1, 1.0, 0.8) * (1.0 + mid_highs * 2.0);
            let spec = pow(max(dot(reflect(-l, n), view_dir), 0.0), 32.0);
            col = eye_glow + vec3<f32>(spec);
        }

        // Bloom from core gravity well
        let dist_to_center = length(p);
        let bloom = exp(-dist_to_center * 1.5) * vec3<f32>(0.8, 0.2, 1.0) * (bass * 2.0);
        col += bloom;

        // Distance fog integrating into nebula
        let fog_factor = 1.0 - exp(-0.02 * t * t);
        col = mix(col, vec3<f32>(0.05, 0.0, 0.1), fog_factor);
    } else {
        col = getNebula(ro, rd, time);
        // Add subtle acoustic reaction to nebula
        col *= (1.0 + bass * 0.3);
    }

    // Tonemapping and Gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}
