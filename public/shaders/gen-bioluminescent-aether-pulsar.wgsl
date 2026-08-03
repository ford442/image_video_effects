// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Aether-Pulsar
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 34)
//  upgraded-rgba
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Core (Sphere twisted by Y)
    var q_core = p;
    q_core = rotate3DY(t + q_core.y * 0.5) * q_core;
    let core_noise = noise3(q_core * 2.0 + t) * (0.18 + audio * 0.35 + mids * 0.12);
    let d_core = length(q_core) - 1.0 - core_noise;

    // Accretion disk (Torus with noise/folds)
    var q_disk = p;
    q_disk.y += noise3(q_disk * 1.5 - t * 0.5) * 0.3 * audio;
    let d2 = vec2<f32>(length(q_disk.xz) - 2.5, q_disk.y);
    let diskThickness = mix(0.22, 0.68, u.zoom_params.z);
    let d_disk_base = length(d2) - diskThickness;
    let d_disk = d_disk_base + noise3(q_disk * 4.0) * mix(0.32, 0.08, u.zoom_params.z);

    // Smoothmin between core and disk where they might interact
    let d = smin(d_core, d_disk, 0.5);

    var mat_id = 0.0;
    if d_disk < d_core {
        mat_id = 1.0; // Disk
    }

    return vec2<f32>(d, mat_id);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + e.xyy).x - d,
        map(p + e.yxy).x - d,
        map(p + e.yyx).x - d
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) {
        return;
    }

    var uv = (fragCoord - 0.5 * resolution) / resolution.y;

    let time = u.config.x;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouseUv = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouseUv = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouseUv += mouseVelocity * springDt;
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouseUv.x; extraBuffer[134] = mouseUv.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }

    // Camera
    let mouse = (mouseUv - vec2<f32>(0.5)) * vec2<f32>(6.28, 2.4);
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
    var hit = false;

    for(var i=0; i<80; i++) {
        p = ro + rd * t;
        d = map(p);

        // Volumetric beams
        let beam_dist = length(p.xz) - 0.2 * (1.0 + p.y * 0.1);
        glow += exp(-abs(beam_dist) * 7.0) * 0.025 * u.zoom_params.y * (1.0 + plasmaBuffer[0].z * 0.5);

        if(d.x < 0.001) { hit = true; break; }
        if(t > 20.0) { break; }
        t += max(abs(d.x) * 0.55, 0.002);
    }

    var col = vec3<f32>(0.0);
    let audio = plasmaBuffer[0].x;

    if (hit) {
        let palette = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 2.1, 4.2) + u.zoom_params.w * 6.28318);
        // Base color
        if d.y < 0.5 { // Core
            col = mix(vec3<f32>(0.08, 0.25, 0.75), palette, 0.45) + palette * abs(p.y) * 0.35;
        } else { // Disk
            col = mix(vec3<f32>(0.15, 0.65, 0.8), palette, 0.35) * (1.0 + audio * 0.5);
        }

        // Lighting
        let n = calcNormal(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        col *= diff + 0.18;
        col += palette * fresnel * 0.55;
    }

    // Add volumetric glow
    col += vec3<f32>(0.1, 0.8, 1.0) * glow;

    let uv01 = (fragCoord + vec2<f32>(0.5)) / resolution;
    var pulsarShock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.6) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0);
            let shell = exp(-abs(length(delta) - age * 0.3) * 76.0) * exp(-age * 1.9);
            pulsarShock = max(pulsarShock, shell);
        }
    }
    col += vec3<f32>(0.4, 0.9, 1.4) * pulsarShock * (0.7 + plasmaBuffer[0].z * 0.35);
    let coord = vec2<i32>(id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.9, clamp(0.025 + plasmaBuffer[0].y * 0.008, 0.0, 0.05));
    col = acesToneMap(col * 1.08);
    let _alpha = clamp(select(0.05, 0.76, hit) + glow * 0.12 + pulsarShock * 0.2, 0.0, 0.96);
    let outColor = vec4<f32>(col, _alpha);
    let _depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
