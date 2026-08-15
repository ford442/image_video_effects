// ----------------------------------------------------------------
// Stellar-Acoustic Resonance-Manifold
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Audio Reactivity, .y = Plasma Density, .z = Orbital Speed, .w = Core Temp
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotate 2D
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Simple hash for 3D noise
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    let r = q + dot(q, q.yxz + 33.33);
    return fract((r.x + r.y) * r.z);
}

// 3D Value Noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3<f32>(0.0,0.0,0.0)), hash(i + vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0,1.0,0.0)), hash(i + vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(hash(i + vec3<f32>(0.0,0.0,1.0)), hash(i + vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0,1.0,1.0)), hash(i + vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

// FBM
fn fbm(p: vec3<f32>, amp: f32, scale: f32) -> f32 {
    var v = 0.0;
    var a = amp;
    var pp = p * scale;
    for(var i = 0; i < 4; i++) {
        v += a * noise(pp);
        pp = pp * 2.0;
        a *= 0.5;
    }
    return v;
}

// Audio sampling
fn getAudioFreq(uvX: f32) -> f32 {
    return textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(uvX, 0.5), 0.0).r;
}

fn map(p_in: vec3<f32>, low_freq: f32, high_freq: f32) -> vec2<f32> {
    var p = p_in;
    let time = u.config.x * u.zoom_params.z;

    // Orbital rotation driven by low freq
    let r_mat = rot(time * 0.2 + low_freq * 0.5);
    p = vec3<f32>(r_mat * p.xy, p.z);
    let r_mat2 = rot(time * 0.15);
    p = vec3<f32>(p.x, r_mat2 * p.yz);

    // Domain repetition
    let spacing = 3.0;
    let cell = floor((p + spacing * 0.5) / spacing);
    p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;

    // Volumetric noise perturbation driven by high freq
    let audio_reactivity = u.zoom_params.x;
    let noise_amp = 0.5 + high_freq * audio_reactivity * 0.5;
    let n = fbm(p + time, noise_amp, 1.5);

    // Sphere SDF perturbed by noise
    let radius = 0.8 * u.zoom_params.y; // Plasma density affects radius
    let d = length(p) - radius + n * 0.5;

    return vec2<f32>(d * 0.5, cell.x + cell.y + cell.z); // Scale distance slightly to avoid artifacts
}

// Basic Blackbody approximation
fn blackbody(temp: f32) -> vec3<f32> {
    // Very simplified blackbody
    let r = min(1.0, temp / 6000.0);
    let g = min(1.0, (temp - 3000.0) / 4000.0) * step(3000.0, temp);
    let b = min(1.0, (temp - 5000.0) / 4000.0) * step(5000.0, temp);
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= u32(u.config.z) || id.y >= u32(u.config.w)) {
        return;
    }

    let res = u.config.zw;
    var uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    let low_freq = getAudioFreq(0.1);
    let high_freq = getAudioFreq(0.8);

    // Mouse Interaction: Gravity well
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x/res.y, 1.0);
    // u.zoom_config.y and u.zoom_config.z are in 0..1 (y=0 top). But we centered uv. Let's make mouse match uv space.
    let mouse_pos = vec2<f32>((u.zoom_config.y - 0.5) * (res.x/res.y), (0.5 - u.zoom_config.z));

    let gravity_strength = 2.0;
    let dist_to_mouse = length(uv - mouse_pos);
    let distortion = 1.0 / (1.0 + dist_to_mouse * gravity_strength);

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * u.zoom_params.z);

    // Bend ray direction based on gravity
    var rd = normalize(vec3<f32>(uv, 1.0));
    rd = normalize(mix(rd, normalize(vec3<f32>(mouse_pos, 0.5) - ro), distortion * 0.5));

    var p = ro;
    var d: f32 = 0.0;
    var min_dist: f32 = 100.0;
    var hit: bool = false;
    var material_id: f32 = 0.0;

    // Raymarching
    for(var i = 0; i < 64; i++) {
        let res_map = map(p, low_freq, high_freq);
        d = res_map.x;
        material_id = res_map.y;

        min_dist = min(min_dist, d);

        if(d < 0.01) {
            hit = true;
            break;
        }
        p += rd * d;
        if(length(p - ro) > 20.0) {
            break;
        }
    }

    // Color mapping and Shading
    var col = vec3<f32>(0.01, 0.01, 0.05); // Deep space / indigo

    // Add bloom / scattering based on min_dist
    let glow = exp(-min_dist * 2.0);
    let base_temp = u.zoom_params.w;

    // Shift chromatic gradient towards cursor based on distortion
    let shift = distortion * 1000.0;
    let em_temp = base_temp + high_freq * 2000.0 + shift;

    let em_col = blackbody(em_temp);

    col += em_col * glow * 0.5;

    if(hit) {
        // Fake subsurface scattering
        let n = normalize(vec3<f32>(
            map(p + vec3<f32>(0.01, 0.0, 0.0), low_freq, high_freq).x - map(p - vec3<f32>(0.01, 0.0, 0.0), low_freq, high_freq).x,
            map(p + vec3<f32>(0.0, 0.01, 0.0), low_freq, high_freq).x - map(p - vec3<f32>(0.0, 0.01, 0.0), low_freq, high_freq).x,
            map(p + vec3<f32>(0.0, 0.0, 0.01), low_freq, high_freq).x - map(p - vec3<f32>(0.0, 0.0, 0.01), low_freq, high_freq).x
        ));

        // Simple lighting
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let sss = fbm(p * 5.0, 1.0, 2.0) * 0.5 + 0.5;

        col += em_col * (diff * 0.2 + sss * 0.8) * 1.5;
    }

    // Tone mapping
    col = col / (1.0 + col);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
