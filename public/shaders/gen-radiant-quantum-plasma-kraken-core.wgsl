// ----------------------------------------------------------------
// Radiant Quantum-Plasma Kraken-Core
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tentacle Twist, y=Plasma Glow, z=Core Heat, w=Void Depth
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
    var p = p_in;
    let t = u.config.x * 0.5;
    let audio = u.config.y;

    // UI Sliders mapped
    let twist_amount = u.zoom_params.x; // Tentacle Twist
    let core_heat = u.zoom_params.z;    // Core Heat

    // Mouse Interaction (Gravitational distortion)
    let mx = (u.zoom_config.y - 0.5) * 2.0;
    let my = (u.zoom_config.z - 0.5) * 2.0;
    let click_pull = smoothstep(0.0, 1.0, length(vec2<f32>(mx, my)) * 2.0); // Simple proxy for intensity based on mouse distance from center

    // Add overall temporal and mouse rotation
    let rotY = rot(t * 0.2 + mx * 2.0);
    let rotX = rot(t * 0.1 + my * 2.0);
    var p_rot = p;
    p_rot.xz = rotY * p_rot.xz;
    p_rot.yz = rotX * p_rot.yz;

    // Distort space slightly based on audio and noise
    let n1 = fbm(p_rot * 1.5 + vec3<f32>(t)) * 0.5;
    let p_distorted = p_rot + normalize(p_rot) * n1 * audio * 0.5;

    // --- Core Entity (Sphere) ---
    // The core pulsates with audio and core heat
    let core_radius = 1.0 + (audio * 0.5) + (core_heat * 0.2);
    let noise_core = fbm(p_distorted * 3.0 - vec3<f32>(t * 2.0)) * 0.4;
    let d_core = length(p_distorted) - core_radius - noise_core;

    // --- Tentacles ---
    var d_tentacles = 100.0;
    let num_tentacles = 8.0;

    for (var i = 0.0; i < num_tentacles; i = i + 1.0) {
        // Angle for each tentacle around the core
        let angle = (i / num_tentacles) * PI * 2.0;
        var p_tentacle = p_rot;

        // Rotate local space for this tentacle
        p_tentacle.xz = rot(angle) * p_tentacle.xz;

        // Twist tentacle along its length
        let tentacle_length_pos = p_tentacle.x;
        // Domain warping / Twisting
        let twist = (t + click_pull * 2.0) * 0.5 * twist_amount;
        p_tentacle.yz = rot(tentacle_length_pos * 0.5 + twist) * p_tentacle.yz;

        // Wavy motion (bioluminescent waves)
        p_tentacle.y = p_tentacle.y + sin(p_tentacle.x * 2.0 - t * 3.0) * 0.3 * (1.0 + audio);
        p_tentacle.z = p_tentacle.z + cos(p_tentacle.x * 1.5 - t * 2.5) * 0.3 * (1.0 + audio);

        // Tentacle length and shape
        let t_start = vec3<f32>(0.5, 0.0, 0.0); // Start near the core
        let t_end = vec3<f32>(6.0, 0.0, 0.0);   // Extend outwards

        // Taper radius
        let t_pos = clamp(p_tentacle.x / 6.0, 0.0, 1.0);
        let t_radius = mix(0.4, 0.02, t_pos) + fbm(p_tentacle * 5.0) * 0.05 * audio;

        // Use a capsule for the base shape
        let d_t = sdCapsule(p_tentacle, t_start, t_end, t_radius);

        d_tentacles = smin(d_tentacles, d_t, 0.3);
    }

    // Determine which part is glowing more
    if (d_core < d_tentacles) {
        *is_light = 1.0; // Core
    } else {
        // Tentacles glow more near the base and based on noise
        *is_light = 0.2 + fbm(p_distorted * 2.0 + vec3<f32>(t)) * 0.8;
    }

    // Blend core and tentacles
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
    let audio = u.config.y;

    let plasma_glow = u.zoom_params.y; // Plasma Glow
    let void_depth = u.zoom_params.w;  // Void Depth

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
        let glow_strength = 0.05 * plasma_glow * (1.0 + audio * 0.5);
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

        // Lighting
        let lightDir1 = normalize(vec3<f32>(5.0, 5.0, 5.0));
        let lightDir2 = normalize(vec3<f32>(-5.0, -2.0, -3.0));

        let diff1 = max(dot(n, lightDir1), 0.0);
        let diff2 = max(dot(n, lightDir2), 0.0);

        // Base colors
        let core_col = vec3<f32>(1.0, 0.2, 0.8) * u.zoom_params.z; // Neon magenta + gold heat
        let tentacle_col = vec3<f32>(0.1, 0.6, 1.0); // Bioluminescent blue

        var mat_col = mix(tentacle_col, core_col, is_light);

        // Fresnel for quantum glass refraction look on surface
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Audio reactive flash
        mat_col = mat_col + vec3<f32>(audio * 0.5 * is_light);

        col = mat_col * (diff1 * 0.8 + diff2 * 0.4 + 0.2) + fresnel * vec3<f32>(0.8, 0.9, 1.0);
    } else {
        // Fog / Void Background
        let star_noise = fbm(rd * 100.0) * fbm(rd * 200.0);
        let stars = smoothstep(0.7, 1.0, star_noise) * vec3<f32>(0.8, 0.9, 1.0) * (1.0 + audio);
        col = bg_color + stars;
    }

    // Add accumulated glow
    let glow_col = vec3<f32>(1.0, 0.3, 0.9); // Radiant magenta glow
    col = col + glow_col * acc * 0.02;

    // Distance fog
    col = mix(col, bg_color, 1.0 - exp(-0.02 * d * d));

    // Tone mapping and gamma correction
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
