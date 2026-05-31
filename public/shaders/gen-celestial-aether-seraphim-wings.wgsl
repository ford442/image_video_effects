// ----------------------------------------------------------------
// Celestial Aether-Seraphim Wings
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};
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

// 2D Rotation
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth Min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Wing SDF (KIFS Fractal)
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    // Ascent over time
    p.y += u.config.x * 2.0 * u.zoom_params.w;

    // Domain Repetition
    p.y = (fract(p.y / 8.0 + 0.5) - 0.5) * 8.0;

    var d = 1000.0;

    // Base fold
    p.x = abs(p.x);

    let time = u.config.x * 0.5;
    let beat = sin(time * 3.14 + u.config.y * 2.0) * 0.2;

    for (var i = 0; i < 5; i++) {
        p.x = abs(p.x) - u.zoom_params.x * 1.5;
        p.y = abs(p.y) - 0.5;
        p.z = abs(p.z) - 0.2;

        let pXY = rot(0.4 + beat) * p.xy;
        p.x = pXY.x;
        p.y = pXY.y;

        let pYZ = rot(0.2 - beat*0.5) * p.yz;
        p.y = pYZ.x;
        p.z = pYZ.y;

        // Wing feather structures
        let feather = length(p.xz) - u.zoom_params.y * (1.0 - f32(i) * 0.15);
        d = smin(d, feather, 0.3);
    }

    // Audio reactive fracturing
    let fracture = sin(pos.x * 10.0) * cos(pos.y * 10.0) * sin(pos.z * 10.0);
    d += fracture * u.config.y * 0.1;

    return d;
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
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
    let uv = (vec2<f32>(coords) - vec2<f32>(0.5) * res) / res.y;

    var ro = vec3<f32>(0.0, -2.0, -5.0 + u.config.x * 0.2);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    let mouseX = (u.zoom_config.y - 0.5) * 6.28;
    let mouseY = (u.zoom_config.z - 0.5) * 3.14;

    let roYZ = rot(-mouseY) * ro.yz;
    ro.y = roYZ.x;
    ro.z = roYZ.y;
    let rdYZ = rot(-mouseY) * rd.yz;
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let roXZ = rot(mouseX) * ro.xz;
    ro.x = roXZ.x;
    ro.z = roXZ.y;
    let rdXZ = rot(mouseX) * rd.xz;
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    var t = 0.0;
    var max_t = 30.0;
    var d = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 90; i++) {
        let p = ro + rd * t;
        d = map(p);

        // Accumulate glow near surfaces
        glow += 0.01 / (0.01 + abs(d));

        if (d < 0.001 || t > max_t) { break; }
        t += d * 0.6; // Smaller step size for safety with smin and domain mod
    }

    var col = vec3<f32>(0.0);

    if (t < max_t) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let viewDir = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        // Thin-film interference iridescence
        let hue = fract(u.zoom_params.z + t * 0.1 + fresnel * 0.5);
        let base_col = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(hue) + vec3<f32>(0.0, 0.33, 0.67)));

        col = base_col * (0.2 + fresnel * 0.8);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        col += vec3<f32>(diff * 0.3) * base_col;

        // Audio reactive brightness
        col += vec3<f32>(u.config.y * 1.5) * fresnel * base_col;
    }

    // Add volumetric glow
    let glowCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(u.zoom_params.z) + vec3<f32>(0.5, 0.0, 0.2)));
    col += vec3<f32>(glow * 0.015) * glowCol;

    // Atmospheric Fog
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.05 * t));

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
