// ----------------------------------------------------------------
// Xeno-Mycelial Resonance-Web
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Repetition, y=BranchSize, z=Hue, w=PulseSpeed
    ripples: array<vec4<f32>, 50>,
}

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
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

// --- SHADER LOGIC ---

// PRNG and Noise
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

// 2D Rotation Matrix
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth Minimum
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Organic Mycelial SDF
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    // Domain repetition
    p = (fract(p / u.zoom_params.x + 0.5) - 0.5) * u.zoom_params.x;

    var d = 100.0;

    // Branching KIFS
    for (var i = 0; i < 4; i++) {
        p = abs(p) - 0.3;
        let pXY = rot2(0.5) * p.xy;
        p.x = pXY.x;
        p.y = pXY.y;
        let pYZ = rot2(1.2) * p.yz;
        p.y = pYZ.x;
        p.z = pYZ.y;

        let branch = length(p.xy) - u.zoom_params.y * (1.0 - f32(i)*0.2);
        d = smin(d, branch, 0.2);
    }

    // Audio reactive swelling — bass via plasmaBuffer
    let bassMap = plasmaBuffer[0].x;
    let pulse = sin(pos.z * 5.0 - u.config.x * u.zoom_params.w) * 0.5 + 0.5;
    d -= pulse * bassMap * 0.15;

    return d;
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy) +
        e.yyx * map(p + e.yyx) +
        e.yxy * map(p + e.yxy) +
        e.xxx * map(p + e.xxx)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    let bass = plasmaBuffer[0].x;

    // Mouse Rotation
    let mouseX = (u.zoom_config.y - 0.5) * TAU;
    let mouseY = (u.zoom_config.z - 0.5) * PI;

    let roYZ = rot2(-mouseY) * ro.yz;
    ro.y = roYZ.x;
    ro.z = roYZ.y;
    let rdYZ = rot2(-mouseY) * rd.yz;
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let roXZ = rot2(mouseX) * ro.xz;
    ro.x = roXZ.x;
    ro.z = roXZ.y;
    let rdXZ = rot2(mouseX) * rd.xz;
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    // Raymarching
    var t = 0.0;
    var max_t = 20.0;
    var d = 0.0;
    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > max_t) { break; }
        t += d * 0.7; // step cautiously for smin
    }

    var col = vec3<f32>(0.0);
    var hit = 0.0;
    var glow = 0.0;

    if (t < max_t) {
        hit = 1.0;
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Base color based on hue slider — TAU constant
        let base_col = 0.5 + 0.5 * cos(TAU * (u.zoom_params.z + vec3<f32>(0.0, 0.33, 0.67)));

        // Bioluminescent Glow — bass-driven from plasmaBuffer
        let pulse = sin(p.z * 5.0 - u.config.x * u.zoom_params.w) * 0.5 + 0.5;
        glow = pow(pulse, 4.0) * (0.5 + bass * 2.0);

        col = base_col * (0.2 + glow);

        // Basic lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        col += diff * 0.1 * base_col;

        // Beer-Lambert fog
        col = mix(col, vec3<f32>(0.01, 0.0, 0.02), 1.0 - exp(-0.15 * t));
    }

    // Alpha: ray hit + bioluminescent glow drives ethereal compositing weight
    let lumaOut = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(hit * (0.4 + glow * 0.4) + lumaOut * 0.2 + 0.05, 0.0, 1.0);
    textureStore(writeTexture, coords, vec4<f32>(col, alpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(coords) / res, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
