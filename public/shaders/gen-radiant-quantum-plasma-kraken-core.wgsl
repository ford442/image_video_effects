// ----------------------------------------------------------------
// Radiant Quantum-Plasma Kraken-Core
// Category: generative
// Features: mouse-driven, audio-reactive, upgraded-rgba
// Upgraded: 2026-09-15
// Ideas: paired sucker-current rows; core-to-arm peristaltic discharge
// A packing: ACES display RGBA
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
    config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=held
    zoom_params: vec4<f32>,  // x=Tentacle Twist 0-5, y=Plasma Glow 0-5, z=Core Heat 0.1-3, w=Void Depth 0-1
    ripples: array<vec4<f32>, 50>,
};

// --- Math & Noise Helpers ---

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise function
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.3183099 + vec3<f32>(0.1, 0.1, 0.1));
    return fract(sin(dot(q, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p2 = p;
    for (var i = 0; i < 4; i = i + 1) {
        v = v + a * noise3(p2);
        p2 = p2 * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

var<private> g_arm_tpos: f32 = 0.0;
var<private> g_arm_local: vec3<f32> = vec3<f32>(0.0);
var<private> g_peri: f32 = 0.0;

// Box SDF for domain repetition
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Capsule SDF
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

// --- Map Function ---
fn map(p_in: vec3<f32>, is_light: ptr<function, f32>) -> f32 {
    let t = u.config.x * 0.5;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Range-aware sliders: Twist 0–5, Heat 0.1–3 (do not flatten to 0–1)
    let twist_amount = u.zoom_params.x;
    let core_heat = u.zoom_params.z;

    // Mouse Interaction (Gravitational distortion)
    let mx = (u.zoom_config.y - 0.5) * 2.0;
    let my = (u.zoom_config.z - 0.5) * 2.0;
    let click_pull = smoothstep(0.0, 1.0, length(vec2<f32>(mx, my)) * 2.0);

    // Add overall temporal and mouse rotation
    let rotY = rot(t * 0.2 + mx * 2.0);
    let rotX = rot(t * 0.1 + my * 2.0);
    var p_rot = p_in;
    let p_rot_xz = rotY * p_rot.xz;
    p_rot.x = p_rot_xz.x;
    p_rot.z = p_rot_xz.y;
    let p_rot_yz = rotX * p_rot.yz;
    p_rot.y = p_rot_yz.x;
    p_rot.z = p_rot_yz.y;

    // Distort space slightly based on audio and noise
    let n1 = fbm(p_rot * 1.5 + vec3<f32>(t)) * 0.5;
    let p_len = max(length(p_rot), 0.001);
    let p_distorted = p_rot + (p_rot / p_len) * n1 * bass * 0.5;

    // --- Core Entity (Sphere) ---
    let core_radius = 1.0 + (bass * 0.5) + (core_heat * 0.2);
    let noise_core = fbm(p_distorted * 3.0 - vec3<f32>(t * 2.0)) * 0.4;
    let d_core = length(p_distorted) - core_radius - noise_core;

    // --- Tentacles ---
    var d_tentacles = 100.0;
    let num_tentacles = 8.0;
    var nearest_tpos = 0.0;
    var nearest_local = vec3<f32>(0.0);
    var nearest_peri = 0.0;

    for (var i = 0.0; i < num_tentacles; i = i + 1.0) {
        let angle = (i / num_tentacles) * PI * 2.0;
        var p_tentacle = p_rot;

        let p_tentacle_xz = rot(angle) * p_tentacle.xz;
        p_tentacle.x = p_tentacle_xz.x;
        p_tentacle.z = p_tentacle_xz.y;

        let tentacle_length_pos = p_tentacle.x;
        let twist = (t + click_pull * 2.0) * 0.5 * twist_amount;
        let p_tentacle_yz = rot(tentacle_length_pos * 0.5 + twist) * p_tentacle.yz;
        p_tentacle.y = p_tentacle_yz.x;
        p_tentacle.z = p_tentacle_yz.y;

        p_tentacle.y = p_tentacle.y + sin(p_tentacle.x * 2.0 - t * 3.0) * 0.3 * (1.0 + bass);
        p_tentacle.z = p_tentacle.z + cos(p_tentacle.x * 1.5 - t * 2.5) * 0.3 * (1.0 + bass);

        let t_start = vec3<f32>(0.5, 0.0, 0.0);
        let t_end = vec3<f32>(6.0, 0.0, 0.0);

        let t_pos = clamp(p_tentacle.x / 6.0, 0.0, 1.0);
        // Core-to-arm peristaltic discharge: travelling constriction
        let peri = sin(t_pos * 14.0 - u.config.x * 3.2);
        let t_radius = mix(0.4, 0.02, t_pos) * (1.0 + peri * 0.14)
            + fbm(p_tentacle * 5.0) * 0.05 * bass;

        let d_t = sdCapsule(p_tentacle, t_start, t_end, t_radius);
        if (d_t < d_tentacles) {
            nearest_tpos = t_pos;
            nearest_local = p_tentacle;
            nearest_peri = peri;
        }
        d_tentacles = smin(d_tentacles, d_t, 0.3);
    }

    g_arm_tpos = nearest_tpos;
    g_arm_local = nearest_local;
    g_peri = nearest_peri;

    if (d_core < d_tentacles) {
        *is_light = 1.0;
    } else {
        *is_light = 0.2 + fbm(p_distorted * 2.0 + vec3<f32>(t)) * 0.8;
        *is_light = *is_light + max(nearest_peri, 0.0) * 0.35 * (0.4 + mids);
    }

    return smin(d_core, d_tentacles, 0.8);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    var dummy1 = 0.0; var dummy2 = 0.0; var dummy3 = 0.0; var dummy4 = 0.0;
    let nx = map(p + e.xyy, &dummy1) - map(p - e.xyy, &dummy2);
    let ny = map(p + e.yxy, &dummy3) - map(p - e.yxy, &dummy4);
    let nz = map(p + e.yyx, &dummy1) - map(p - e.yyx, &dummy2); // Reusing dummy
    return normalize(vec3<f32>(nx, ny, nz));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let uv = (fragCoord.xy - 0.5 * res) / res.y;
    let t = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let plasma_glow = u.zoom_params.y; // 0–5
    let void_depth = u.zoom_params.w;  // 0–1

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 10.0 + (void_depth * 5.0)); // Zoom out based on void depth
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Add some camera sway
    ro.x = ro.x + sin(t * 0.1) * 2.0;
    ro.y = ro.y + cos(t * 0.15) * 1.5;

    // Look at origin
    let cw = normalize(vec3<f32>(0.0) - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    rd = mat3x3<f32>(cu, cv, cw) * normalize(vec3<f32>(uv, 1.0)); // FOV adjusting

    // Raymarching
    var p = ro;
    var d = 0.0;
    var acc = 0.0; // Accumulation for glow
    var is_light = 0.0;
    var hit = false;

    let max_steps = 100;
    for (var i = 0; i < max_steps; i = i + 1) {
        let dist = map(p, &is_light);

        // Volumetric accumulation (Bloom/Glow)
        // Subsurface scattering proxy
        let glow_strength = 0.05 * plasma_glow * (1.0 + bass * 0.5);
        acc = acc + glow_strength / (1.0 + abs(dist) * 10.0) * is_light;

        if (abs(dist) < 0.001) {
            hit = true;
            break;
        }
        if (d > 30.0) {
            break;
        }
        p = p + rd * dist;
        d = d + dist;
    }

    var col = vec3<f32>(0.0);
    let bg_color = vec3<f32>(0.02, 0.01, 0.05); // Deep abyssal blue/purple

    if (hit) {
        let n = calcNormal(p);
        var dummyHit = 0.0;
        let hitDist = map(p, &dummyHit);

        let lightDir1 = normalize(vec3<f32>(5.0, 5.0, 5.0));
        let lightDir2 = normalize(vec3<f32>(-5.0, -2.0, -3.0));

        let diff1 = max(dot(n, lightDir1), 0.0);
        let diff2 = max(dot(n, lightDir2), 0.0);

        let core_col = vec3<f32>(1.0, 0.2, 0.8) * u.zoom_params.z;
        let tentacle_col = vec3<f32>(0.1, 0.6, 1.0);

        var mat_col = mix(tentacle_col, core_col, is_light);

        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        mat_col = mat_col + vec3<f32>(bass * 0.5 * is_light);

        // Paired sucker-current rows along the nearest arm underside
        let underside = smoothstep(-0.05, 0.15, -g_arm_local.y);
        let ringA = fract(g_arm_tpos * 16.0);
        let ringB = fract(g_arm_tpos * 16.0 + 0.5);
        let suckA = exp(-pow((ringA - 0.5) / 0.09, 2.0));
        let suckB = exp(-pow((ringB - 0.5) / 0.09, 2.0));
        let suckers = (suckA + suckB) * underside * (1.0 - is_light) * (0.55 + treble);
        mat_col += vec3<f32>(0.2, 0.95, 1.0) * suckers;
        mat_col += vec3<f32>(1.0, 0.45, 0.85) * max(g_peri, 0.0) * (1.0 - is_light) * (0.35 + mids);

        col = mat_col * (diff1 * 0.8 + diff2 * 0.4 + 0.2) + fresnel * vec3<f32>(0.8, 0.9, 1.0);
        col += vec3<f32>(0.12) * clamp(-hitDist, 0.0, 1.0);
    } else {
        let star_noise = fbm(rd * 100.0) * fbm(rd * 200.0);
        let stars = smoothstep(0.7, 1.0, star_noise) * vec3<f32>(0.8, 0.9, 1.0) * (1.0 + bass);
        col = bg_color + stars;
    }

    let glow_col = vec3<f32>(1.0, 0.3, 0.9);
    col = col + glow_col * acc * 0.02;

    col = mix(col, bg_color, 1.0 - exp(-0.02 * d * d));

    let alpha = clamp(select(0.0, 0.7, hit) + clamp(acc, 0.0, 2.0) * 0.12, 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col), alpha);
    let depth = select(0.0, clamp(1.0 - d / 30.0, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
