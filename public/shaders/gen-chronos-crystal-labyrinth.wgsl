// ----------------------------------------------------------------
// Chronos Crystal Labyrinth
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
  zoom_params: vec4<f32>,  // .x = Dispersion, .y = Gravity Strength, .z = Fractal Fold, .w = Glow Intensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Distance functions
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map the world
fn map(p: vec3<f32>) -> f32 {
    var q = p;

    // Temporal distortion waves driven by audio-reactive low-frequency data
    let audio_lf = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.1, 0.5), 0.0).r;
    let time_audio = u.config.x + audio_lf * 2.0;

    // Rotate space slowly over time
    let r_xz = rot(time_audio * 0.1);
    let r_yz = rot(time_audio * 0.15);
    q = vec3<f32>(r_xz * q.xz, q.y).xzy;
    q = vec3<f32>(q.x, r_yz * q.yz);

    // Domain repetition / folding
    for (var i = 0; i < 3; i++) {
        q = abs(q) - u.zoom_params.z;
        let r = rot(f32(i) * 0.5 + time_audio * 0.05);
        q = vec3<f32>(r * q.xy, q.z);
    }

    q = abs(q) - u.zoom_params.z * 0.5;

    // Core geometry
    let d = sdOctahedron(q, 1.0);

    // Add noise displacement
    let noise = sin(p.x * 2.0 + time_audio) * sin(p.y * 2.0 + time_audio) * sin(p.z * 2.0) * 0.1;
    return d + noise;
}

// Calculate normal
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// Raymarching loop
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = vec2<f32>(coords) / resolution;
    let base_uv = uv; // Retain original for potential 2D sampling
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Setup camera and rays
    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * 0.5);
    let ta = vec3<f32>(0.0, 0.0, u.config.x * 0.5);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Mouse Interaction (Gravity Well)
    if (u.zoom_config.w > 0.0) {
        var mouse_uv = u.zoom_config.yz;
        mouse_uv = mouse_uv * 2.0 - 1.0;
        mouse_uv.x *= resolution.x / resolution.y;
        mouse_uv.y = -mouse_uv.y; // Correct y-axis

        let dist_to_mouse = length(uv - mouse_uv);
        let distortion = u.zoom_params.y / (1.0 + pow(dist_to_mouse, 2.0));
        let bend_dir = normalize(vec3<f32>(uv - mouse_uv, 0.5));
        rd = normalize(mix(rd, bend_dir, distortion * 0.5));
    }

    // Raymarching, lighting, and refraction logic
    var t = 0.0;
    var d = 0.0;
    var p = ro;

    // Volumetric raymarching properties
    var glow = vec3<f32>(0.0);

    // Audio reactivity for glow
    let audio_glow = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.2, 0.5), 0.0).r;

    for (var i = 0; i < 64; i++) {
        p = ro + rd * t;
        d = map(p);

        if (d < 0.001) {
            break;
        }

        // Soft subsurface scattering approximation
        glow += exp(-d * 2.0) * vec3<f32>(0.1, 0.2, 0.5) * u.zoom_params.w * (1.0 + audio_glow);

        t += d;
        if (t > 20.0) {
            break;
        }
    }

    var col = vec3<f32>(0.0);

    if (d < 0.001) {
        let n = getNormal(p);

        // Chromatic aberration and heavy dispersion
        let disp = u.zoom_params.x * 0.01;
        let refl = reflect(rd, n);

        // Shading utilizes a custom PBR-like approach for transparent media
        let base_col = vec3<f32>(0.8, 0.9, 1.0);
        let diffuse = max(dot(n, vec3<f32>(0.5, 0.8, -0.5)), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

        col = base_col * diffuse * 0.2 + fresnel * vec3<f32>(0.6, 0.8, 1.0);

        // Add fake dispersion reflection
        let r_rd = normalize(rd + n * disp);
        let b_rd = normalize(rd - n * disp);

        // Just a stylistic addition to mimic dispersion
        col += vec3<f32>(max(dot(r_rd, refl), 0.0), 0.0, 0.0) * 0.2;
        col += vec3<f32>(0.0, 0.0, max(dot(b_rd, refl), 0.0)) * 0.2;
    }

    col += glow * 0.02;

    // Output
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
