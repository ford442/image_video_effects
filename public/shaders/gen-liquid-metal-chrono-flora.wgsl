// ----------------------------------------------------------------
// Liquid-Metal Chrono-Flora
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// Utility Functions
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Map function
fn map(p: vec3<f32>) -> f32 {
    var pos = p;

    // Mouse distortion
    if (u.zoom_config.w > 0.0) {
        // Implement mouse gravity well
        let m = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z) * 2.0 - 1.0;
        let dist = length(pos.xy - m);
        let pull = exp(-dist * 2.0) * 0.5;
        pos -= vec3<f32>(m * pull, 0.0);
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mid = clamp(plasmaBuffer[0].y, 0.0, 1.0);

    // Params
    let bloomSpeed = u.zoom_params.y;
    let temporalDistortion = u.zoom_params.z;

    // Core geometry
    let time = u.config.x * 0.5 * bloomSpeed;

    // Temporal distortion waves causing time-reversed ripples
    let timeWave = sin(length(pos) * 2.0 - time * 3.0) * temporalDistortion;
    let effectiveTime = time + timeWave;

    // Domain distortion and SDF combination
    var d = 100.0;

    // Radial distortion
    let angle = atan2(pos.x, pos.z);
    let radius = length(pos.xz);

    let petals = 6.0;
    let petalAngle = angle * petals + effectiveTime;

    // Folding flower structure
    let q = vec3<f32>(
        radius * cos(petalAngle) - 1.0 - bass * 0.3,
        pos.y + sin(radius * 3.0 - effectiveTime * 2.0) * 0.5,
        radius * sin(petalAngle)
    );

    // Base Torus combined with sphere for petals
    let d1 = sdTorus(q, vec2<f32>(1.5, 0.2 + mid * 0.1));
    let d2 = length(pos) - (1.0 + bass * 0.2); // Core sphere

    d = smin(d1, d2, 0.8);

    return d * 0.5; // Scale down for safety
}

// Compute Normal
fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let coords = vec2<f32>(id.xy);
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (coords - 0.5 * dims) / min(dims.x, dims.y);

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    for (var i = 0; i < 150; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var out_depth = 1.0;

    let metallicShine = u.zoom_params.x;
    let chronoIntensity = u.zoom_params.w;

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = get_normal(p);

        // Liquid metal shading
        let viewDir = normalize(ro - p);
        let refl = reflect(-viewDir, n);

        // Base chrome reflection
        let envCol = vec3<f32>(0.8, 0.9, 1.0) * max(0.0, refl.y * 0.5 + 0.5) * metallicShine;

        // Chrono energy in crevices
        let ao = clamp(map(p + n * 0.1) * 10.0, 0.0, 1.0);
        let energyCol = vec3<f32>(0.8, 0.1, 0.9) * (1.0 - ao) * chronoIntensity;

        col = envCol + energyCol;

        // Specular
        let spec = pow(max(dot(refl, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0), 32.0);
        col += vec3<f32>(1.0) * spec * metallicShine;

        out_depth = t / 20.0;
    }

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(0.0));
}
