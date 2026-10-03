// ═══════════════════════════════════════════════════════════════════
//  Ethereal Chrono-Flora Loom
//  Category: generative
//  Features: audio-reactive, mouse-driven
// ═══════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // .x = Density, .y = Flow Speed, .z = Glow Intensity, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

// --- SDF ---
fn map(p: vec3<f32>) -> vec2<f32> {
    var p_mod = p;

    // Audio modulation for speed
    let audioBass = extraBuffer[0] * 0.5;
    let t = u.config.x * u.zoom_params.y * (1.0 + audioBass);

    // Twist based on height and time
    let pxy = p_mod.xy * rot2D(p_mod.z * 0.2 + t * 0.5);
    p_mod = vec3<f32>(pxy, p_mod.z);

    // Domain repetition for flora petals
    let angle = atan2(p_mod.y, p_mod.x);
    let radius = length(p_mod.xy);
    let petals = 6.0;
    let sector = 6.28318 / petals;
    let id = floor(angle / sector);
    let local_angle = (fract(angle / sector) - 0.5) * sector;

    let p_folded = vec3<f32>(cos(local_angle)*radius, sin(local_angle)*radius, p_mod.z);

    let fft_mod = extraBuffer[4u + u32(abs(id) % 10.0)] * 0.5;

    // Flora structure (capsule/cylinder)
    let d_stem = length(p_folded.xy - vec2<f32>(0.5, 0.0)) - 0.1 * u.zoom_params.x * (1.0 + fft_mod);

    // Central glowing orb
    let d_orb = length(p) - 1.0;

    let d = smin(d_stem, d_orb, 0.5);

    return vec2<f32>(d, 1.0);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    let n = vec3<f32>(
        d - map(p - e.xyy).x,
        d - map(p - e.yxy).x,
        d - map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = (u.zoom_config.yz - 0.5 * res) / res.y;
        let pxy = ro.xy * rot2D(mouse_uv.x * 3.14);
        ro = vec3<f32>(pxy, ro.z);
        let rdxy = rd.xy * rot2D(mouse_uv.x * 3.14);
        rd = vec3<f32>(rdxy, rd.z);
    }

    var t = 0.0;
    var glow = 0.0;
    var hit = false;
    var steps_taken: i32 = 0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let d = map(p);

        let audioBass = extraBuffer[0];

        glow += 0.01 / (0.01 + abs(d.x)) * u.zoom_params.z * (1.0 + audioBass*0.5);

        if (abs(d.x) < SURF_DIST) {
            hit = true;
            steps_taken = i;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d.x * 0.8;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));

        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.1 + 0.9 * clamp(0.5 + 0.5 * n.y, 0.0, 1.0);

        let baseCol = palette(length(p) * 0.1 + u.zoom_params.w);
        col = baseCol * dif * amb;

        // Fake AO from step count
        col *= 1.0 - f32(steps_taken) / f32(MAX_STEPS);
    }

    // Add glow
    col += palette(u.config.x * 0.1) * glow * 0.05;

    // Output
    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / MAX_DIST, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(col, 1.0));
}
