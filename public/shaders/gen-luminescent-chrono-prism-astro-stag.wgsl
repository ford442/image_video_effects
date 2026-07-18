// ----------------------------------------------------------------
// Luminescent Chrono-Prism Astro-Stag
// Category: generative
// ----------------------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Temporal Distortion, y=Rift Density, z=Fractal Intensity, w=Prismatic Refraction
    ripples: array<vec4<f32>, 50>,
};

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


// --- SDF FUNCTIONS ---
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// --- NOISE / FBM ---
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// --- SCENE MAP ---
fn map(p_in: vec3<f32>, time: f32, audio: f32, params: vec4<f32>) -> f32 {
    let mouse = u.zoom_config.yz;
    let p = p_in - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
    // Stag Core
    var body = sdCapsule(p, vec3<f32>(0.0, 0.0, -1.0), vec3<f32>(0.0, 0.0, 1.0), 0.5);
    // Add biomechanical noise details
    body += noise(p * 5.0 - vec3<f32>(0.0, 0.0, time)) * 0.1;

    // Antlers & Fractals (warped space)
    var tp = p;
    tp.x = abs(tp.x);
    let antler = sdCapsule(tp, vec3<f32>(0.3, 0.5, 1.0), vec3<f32>(0.8, 1.5, 1.2), 0.1);

    // Smooth blend
    var scene = smin(body, antler, 0.2);

    // Apply temporal shockwaves
    scene += sin(length(p) * 10.0 - time * 5.0) * audio * 0.05 * params.x;

    return scene;
}

// --- RAYMARCHING ---
fn calcNormal(p: vec3<f32>, time: f32, audio: f32, params: vec4<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy, time, audio, params) +
                     e.yyx * map(p + e.yyx, time, audio, params) +
                     e.yxy * map(p + e.yxy, time, audio, params) +
                     e.xxx * map(p + e.xxx, time, audio, params));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) { return; }

    let uv = (fragCoord - 0.5 * resolution) / resolution.y;
    let time = u.config.x;
    let audio = u.config.y;
    let params = u.zoom_params; // Temporal, Rift, Fractal, Refraction

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var p = ro;
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p, time, audio, params);
        if (d < 0.001 || t > 10.0) { break; }
        t += d;
    }

    // Shading
    var col = vec3<f32>(0.01, 0.02, 0.05); // Volumetric Void BG
    if (t < 10.0) {
        let n = calcNormal(p, time, audio, params);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Liquid Aurora / Prismatic colors
        let baseColor = vec3<f32>(0.1, 0.8, 1.0) + sin(p * 2.0 + time) * 0.2;
        col = baseColor * diff + fresnel * vec3<f32>(0.8, 0.2, 1.0) * params.z;
    }

    // Bloom / Volumetric Glow
    col += vec3<f32>(0.1, 0.3, 0.8) * exp(-t * 0.2) * params.y;

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
