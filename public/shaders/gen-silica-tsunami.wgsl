// ----------------------------------------------------------------
// Silica Tsunami
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
    zoom_params: vec4<f32>,  // x=waveHeight, y=glassRefraction, z=particleDensity, w=audioReactivity
    ripples: array<vec4<f32>, 50>,
};

// Utils
fn hash31(p: vec3<f32>) -> f32 {
    var p3  = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// Map function
fn map(pos: vec3<f32>, time: f32) -> f32 {
    let waveHeight = u.zoom_params.x; // default 2.0
    let particleDensity = u.zoom_params.z; // default 1.0
    let audioReactivity = u.zoom_params.w; // default 1.5
    let audio = u.config.y * audioReactivity;

    var p = pos;
    let spacing = particleDensity;
    let half_spacing = spacing * 0.5;

    // Mouse attractor/repulsor
    let mouseActive = u.zoom_config.x;
    let mouse = u.zoom_config.yz;
    let mousePos = vec3<f32>(mouse.x * 20.0, 0.0, mouse.y * 20.0);

    if (mouseActive > 0.5) {
        let dToMouse = length(p.xz - mousePos.xz);
        let repel = smoothstep(5.0, 0.0, dToMouse) * 2.0;
        p.y += repel;
    }

    // Wave displacement
    let waveOffset = sin(p.x * 0.5 - time) * cos(p.z * 0.5 - time) * waveHeight;
    p.y -= waveOffset + audio * sin(p.x * 2.0);

    // Domain repetition
    let id = floor(p / spacing);
    p = fract(p / spacing) * spacing - half_spacing;

    // Base shape
    let r = 0.3 * (0.5 + 0.5 * hash31(id));
    return length(p) - r;
}

fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time);
    return normalize(vec3<f32>(
        map(p + e.xyy, time) - d,
        map(p + e.yxy, time) - d,
        map(p + e.yyx, time) - d
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let pixel = vec2<f32>(f32(id.x), f32(id.y));

    if (pixel.x >= dims.x || pixel.y >= dims.y) {
        return;
    }

    var uv = (pixel - 0.5 * dims) / dims.y;
    let time = u.config.x;

    var ro = vec3<f32>(0.0, 5.0, -time * 5.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y - 0.5, -1.0)); // look slightly down
    rd.xz = rot(0.2) * rd.xz;

    var t = 0.0;
    var d = 0.0;
    var p = vec3<f32>(0.0);
    var col = vec3<f32>(0.0);

    let max_steps = 100;
    let max_dist = 40.0;

    for (var i = 0; i < max_steps; i++) {
        p = ro + rd * t;
        d = map(p, time);
        if (d < 0.01 || t > max_dist) { break; }
        t += d * 0.8;
    }

    if (t < max_dist) {
        let n = calcNormal(p, time);
        let l = normalize(vec3<f32>(-1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let r = reflect(rd, n);

        let glassRefraction = u.zoom_params.y; // default 0.8
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);

        col = vec3<f32>(0.1, 0.4, 0.8) * diff; // base water color
        col += vec3<f32>(0.8, 0.9, 1.0) * fresnel * glassRefraction; // reflection/caustics
        col += pow(max(dot(r, l), 0.0), 32.0) * vec3<f32>(1.0); // spec

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.1, 0.2), 1.0 - exp(-0.02 * t * t));
    } else {
        col = vec3<f32>(0.05, 0.1, 0.2); // background
    }

    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
