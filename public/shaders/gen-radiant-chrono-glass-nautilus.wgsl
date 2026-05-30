// ═══════════════════════════════════════════════════════════════════
//  Radiant Chrono-Glass Nautilus
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-31
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Spiral Tightness, y=Plasma Bloom, z=Glass Refraction, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn rotate3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a = normalize(axis);
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * a.x * a.x + c,           oc * a.x * a.y - a.z * s,  oc * a.z * a.x + a.y * s,
        oc * a.x * a.y + a.z * s,  oc * a.y * a.y + c,           oc * a.y * a.z - a.x * s,
        oc * a.z * a.x - a.y * s,  oc * a.y * a.z + a.x * s,  oc * a.z * a.z + c
    );
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// Logarithmic spiral SDF
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let t = u.config.x;
    // Audio drives chamber breathing (bass) scaled by the Audio Reactivity param
    let audio = plasmaBuffer[0].x * u.zoom_params.w;

    // Gravity well interaction
    let mouse = u.zoom_config.yz;
    let mouseDist = length(p.xy - (mouse * 2.0 - 1.0) * 2.0);
    p = rotate3D(vec3<f32>(0.0, 0.0, 1.0), mouseDist * 0.5) * p;

    // Spiral domain
    let a = atan2(p.y, p.x);
    let r = length(p.xy);
    let z = p.z;

    let tightness = u.zoom_params.x; // 0.1 to 1.0
    let spiral_a = a * tightness + log(r) * 2.0 + t * 0.5;

    // Create nautilus chambers
    let shell = length(vec2<f32>(fract(spiral_a * 1.5) - 0.5, z * 2.0)) - 0.2 - audio * 0.1;
    let interior = length(vec2<f32>(fract(spiral_a * 1.5 + 0.5) - 0.5, z * 2.0)) - 0.15 + audio * 0.2;

    // Smoothly combine chambers
    let dist = smin(shell, interior, 0.2);

    // ID mapping
    var id = 1.0;
    if (shell > interior) { id = 2.0; } // 1.0 = shell, 2.0 = interior
    return vec2<f32>(dist * 0.5, id);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    var uv = (fragCoord * 2.0 - resolution) / min(resolution.x, resolution.y);

    // Audio reactivity: mids tint the glass shimmer, treble sparkles the bloom
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var id = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        id = res.y;
        if (d < 0.001 || t > 10.0) { break; }
        t += d;
        if (id == 2.0) {
            glow += 0.01 / (0.01 + d * d) * u.zoom_params.y; // Plasma Bloom
        }
    }

    var col = vec3<f32>(0.0);
    let hit = t < 10.0;
    var fresnel = 0.0;
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let refraction = u.zoom_params.z;
        let f = pow(1.0 - max(dot(n, -rd), 0.0), refraction); // Fresnel
        fresnel = f;

        let shell = vec3<f32>(0.1, 0.8, 0.9) * f + vec3<f32>(0.9, 0.1, 0.5) * (1.0 - f);
        let interior = vec3<f32>(0.2, 0.0, 0.8) + vec3<f32>(0.0, 0.8, 1.0) * glow;
        col = select(interior, shell, id == 1.0);
        // Mid-frequency chromatic shimmer across the glass
        col += vec3<f32>(0.2, 0.05, 0.3) * f * mids;
    }

    col += vec3<f32>(0.0, 0.5, 1.0) * glow * 0.1;
    col += vec3<f32>(1.0, 0.9, 0.7) * glow * treble * 0.05; // treble sparkle

    // Alpha: glass coverage from fresnel + plasma bloom energy, never flat 1.0
    let alpha = clamp(select(0.0, 0.3, hit) + fresnel * 0.5 + glow * 0.15, 0.0, 1.0);
    let out = vec4<f32>(col, alpha);

    // Depth: ray-march hit distance (near = closer)
    let depth = select(0.0, clamp(1.0 - t / 10.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
