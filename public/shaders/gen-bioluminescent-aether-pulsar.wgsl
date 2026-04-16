// ----------------------------------------------------------------
// Bioluminescent Aether-Pulsar
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Pulsar Spin Rate, y=Beam Intensity, z=Accretion Density, w=Color Shift
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotate3DY(angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat3x3<f32>(
        c, 0.0, -s,
        0.0, 1.0, 0.0,
        s, 0.0, c
    );
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D noise for fluid core and debris
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

// --- SDFs ---
fn map(p: vec3<f32>) -> vec2<f32> {
    let t = u.config.x * u.zoom_params.x;
    let audio = u.config.y;

    // Core (Sphere twisted by Y)
    var q_core = p;
    q_core = rotate3DY(t + q_core.y * 0.5) * q_core;
    let core_noise = noise3(q_core * 2.0 + t) * (0.2 + audio * 0.5);
    let d_core = length(q_core) - 1.0 - core_noise;

    // Accretion disk (Torus with noise/folds)
    var q_disk = p;
    q_disk.y += noise3(q_disk * 1.5 - t * 0.5) * 0.3 * audio;
    let d2 = vec2<f32>(length(q_disk.xz) - 2.5, q_disk.y);
    let d_disk_base = length(d2) - 0.5;
    let d_disk = d_disk_base + noise3(q_disk * 4.0) * (0.5 - u.zoom_params.z * 0.4);

    // Smoothmin between core and disk where they might interact
    let d = smin(d_core, d_disk, 0.5);

    var mat_id = 0.0;
    if d_disk < d_core {
        mat_id = 1.0; // Disk
    }

    return vec2<f32>(d, mat_id);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) {
        return;
    }

    var uv = (fragCoord - 0.5 * resolution) / resolution.y;

    // Camera
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 6.28;
    var ro = vec3<f32>(0.0, 2.0, -6.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse rotation
    let rotY = rotate2D(mouse.x);
    let rotX = rotate2D(mouse.y);

    let roYZ = rotX * vec2<f32>(ro.y, ro.z);
    ro.y = roYZ.x;
    ro.z = roYZ.y;

    let rdYZ = rotX * vec2<f32>(rd.y, rd.z);
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let roXZ = rotY * vec2<f32>(ro.x, ro.z);
    ro.x = roXZ.x;
    ro.z = roXZ.y;

    let rdXZ = rotY * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    // Raymarching
    var t = 0.0;
    var d: vec2<f32>;
    var p = ro;
    var glow = 0.0;

    for(var i=0; i<100; i++) {
        p = ro + rd * t;
        d = map(p);

        // Volumetric beams
        let beam_dist = length(p.xz) - 0.2 * (1.0 + p.y*0.1);
        glow += exp(-beam_dist * 4.0) * 0.05 * u.zoom_params.y;

        if(d.x < 0.001 || t > 20.0) { break; }
        t += d.x * 0.5;
    }

    var col = vec3<f32>(0.0);
    let audio = u.config.y;

    if (t < 20.0) {
        // Base color
        if d.y < 0.5 { // Core
            col = vec3<f32>(0.1, 0.3, 0.8) + vec3<f32>(0.5, 0.1, 0.8) * abs(p.y) * 0.5;
        } else { // Disk
            col = vec3<f32>(0.2, 0.6, 0.7) * (1.0 + audio);
        }

        // Lighting
        let n = normalize(p); // simplified normal
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);
        col *= diff + 0.2;
    }

    // Add volumetric glow
    col += vec3<f32>(0.1, 0.8, 1.0) * glow;

    writeTexture(vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}