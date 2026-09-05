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

// Map the world
fn map(p: vec3<f32>) -> vec2<f32> {
    var q = p;

    // Domain repetition / folding
    q = abs(q) - u.zoom_params.z;
    q = abs(q) - u.zoom_params.z * 0.5;

    // Core geometry
    let d = sdOctahedron(q, 1.0);

    // Audio reactivity
    let audio_uv = vec2<f32>(abs(p.x * 0.1), 0.5);
    let audio_val = textureSampleLevel(dataTextureC, non_filtering_sampler, audio_uv, 0.0).r;
    let displacement = audio_val * 0.2 * sin(p.x * 10.0 + u.config.x) * cos(p.y * 10.0 + u.config.x);

    return vec2<f32>(d + displacement, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
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
    let base_uv = uv; // Keep for ripples
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Mouse Interaction: Gravity well
    var mouse_uv = u.zoom_config.yz;
    mouse_uv.y = 1.0 - mouse_uv.y; // Invert y since WGSL texture space is top-left
    var mouse_clip = mouse_uv * 2.0 - 1.0;
    mouse_clip.x *= resolution.x / resolution.y;

    var distortion = 0.0;
    if (u.zoom_config.w > 0.0) {
        distortion = u.zoom_params.y / (1.0 + pow(length(uv - mouse_clip), 2.0));
    }

    // Setup camera and rays
    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * 0.5);
    let ta = vec3<f32>(0.0, 0.0, u.config.x * 0.5);

    let cw = normalize(ta - ro);
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let cu = normalize(cross(cw, up));
    let cv = normalize(cross(cu, cw));

    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Apply distortion to ray direction
    rd = normalize(rd + (uv.x * cu + uv.y * cv) * distortion);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    for(var i = 0; i < 100; i = i + 1) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if(d < 0.001 || t > 20.0) { break; }
        t += d * 0.5; // Step size
    }

    var col = vec3<f32>(0.0);

    if(t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Refraction / Chromatic dispersion approximation
        let disp = u.zoom_params.x * 0.1;
        let rR = reflect(rd, n); // Simple reflection for now
        let rG = reflect(rd, n + vec3<f32>(disp));
        let rB = reflect(rd, n - vec3<f32>(disp));

        // Simplified lighting / glow
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, l), 0.0);
        let glow = u.zoom_params.w * (1.0 / (1.0 + t*t*0.1));

        col = vec3<f32>(dif) * vec3<f32>(0.5, 0.7, 1.0) + vec3<f32>(glow * 0.5, glow * 0.2, glow * 0.8);

        // Add pseudo-dispersion colors based on normal
        col += vec3<f32>(abs(rR.x), abs(rG.y), abs(rB.z)) * 0.3;
    } else {
        // Background
        col = vec3<f32>(0.05, 0.05, 0.1) * (1.0 - length(uv) * 0.5);
    }

    // Audio reactive background coloring
    let audio_bg = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(base_uv.x, 0.5), 0.0).r;
    col += vec3<f32>(audio_bg * 0.1, audio_bg * 0.05, audio_bg * 0.15);

    // Write out final pixel
    let final_col = vec4<f32>(col, 1.0);
    textureStore(writeTexture, coords, final_col);
}
