// ----------------------------------------------------------------
// Chrono-Kinetic Fractal Engine
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn map(p: vec3<f32>, time: f32, warp: f32, complexity: f32) -> vec2<f32> {
    var pos = p;

    // Mouse Interaction: warp based on u.zoom_config.yz
    var mouse_uv = u.zoom_config.yz;
    if (u.zoom_config.w < 0.5) {
        mouse_uv = vec2<f32>(0.5, 0.5); // Default to center
    }

    let m = (mouse_uv - 0.5) * 5.0; // Scale mouse to world coords vaguely
    let dist_to_mouse = length(pos.xy - m);
    let warp_factor = exp(-dist_to_mouse * 0.5) * warp;

    pos = vec3<f32>(rot(warp_factor) * pos.xy, pos.z);

    // Audio Reactivity
    let audio_uv = clamp(abs(pos.xy) / 5.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let audio_data = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(audio_uv.x, 0.5), 0.0).r;
    let kinetic_burst = audio_data * 0.5;

    // Space folding
    for (var i = 0; i < i32(complexity); i++) {
        let fi = f32(i);
        pos = abs(pos) - vec3<f32>(0.5 + kinetic_burst, 0.5, 0.5);
        pos = vec3<f32>(rot(time * 0.2 + fi) * pos.xy, pos.z);
        pos = vec3<f32>(pos.x, rot(time * 0.15 - fi) * pos.yz);
    }

    // Mix of Torus and Octahedron
    let d1 = sdTorus(pos, vec2<f32>(1.0, 0.3));
    let d2 = sdOctahedron(pos, 1.2);
    let d3 = sdTorus(pos.yzx, vec2<f32>(0.8, 0.1));

    let base_d = smin(d1, d2, 0.5);
    let final_d = max(base_d, -d3); // Cutout

    // Orbit trap distance for color
    let orbit = length(pos);
    return vec2<f32>(final_d, orbit);
}

fn calcNormal(p: vec3<f32>, time: f32, warp: f32, comp: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy, time, warp, comp).x +
                     e.yyx * map(p + e.yyx, time, warp, comp).x +
                     e.yxy * map(p + e.yxy, time, warp, comp).x +
                     e.xxx * map(p + e.xxx, time, warp, comp).x);
}

// Palette for iridescence
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord - 0.5 * res) / res.y;

    let time = u.config.x * u.zoom_params.w;
    let complexity = u.zoom_params.x; // 1.0 - 5.0
    let warp_strength = u.zoom_params.y; // 0.0 - 2.0
    let iridescence = u.zoom_params.z; // 0.0 - 3.0

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Add slight camera movement
    ro = vec3<f32>(ro.x, ro.y, ro.z + sin(time * 0.1) * 2.0);

    var dO = 0.0;
    var d = 0.0;
    var p = ro;
    var trap = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let map_res = map(p, time, warp_strength, complexity);
        d = map_res.x;
        trap = map_res.y; // Keep last trap
        if (d < SURF_DIST || dO > MAX_DIST) { break; }
        dO += d;
    }

    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        let n = calcNormal(p, time, warp_strength, complexity);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -3.0));

        let dif = max(dot(n, lightDir), 0.0);
        let refl = reflect(rd, n);
        let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);

        // Iridescent base color
        let baseCol = palette(trap * 0.2 + time * 0.1 + iridescence);

        // Chromatic aberration approximation: slightly offset normals
        let n_r = normalize(n + vec3<f32>(0.01, 0.0, 0.0));
        let n_b = normalize(n - vec3<f32>(0.01, 0.0, 0.0));
        let r_val = max(dot(n_r, lightDir), 0.0);
        let b_val = max(dot(n_b, lightDir), 0.0);

        let chromaCol = vec3<f32>(r_val, dif, b_val) * baseCol;

        col = chromaCol * 0.6 + vec3<f32>(spec) * 0.4;

        // Bloom / neon edge
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        col += vec3<f32>(0.2, 0.5, 1.0) * fresnel * 0.8;
    }

    // Fog
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * dO * dO));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
