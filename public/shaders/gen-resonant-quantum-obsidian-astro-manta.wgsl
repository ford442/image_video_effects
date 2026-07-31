// ----------------------------------------------------------------
// Resonant Quantum-Obsidian Astro-Manta
// Category: generative
// Tags: organic, biomechanical, quantum, cosmic, audio-reactive, raymarching
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Math Constants
const PI = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Main SDF
fn map(p: vec3<f32>) -> f32 {
    var p_mod = p;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_world = vec3<f32>((mouse.x - 0.5) * 10.0, -(mouse.y - 0.5) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_world);
    if (u.zoom_config.w > 0.0) {
        p_mod -= normalize(p - mouse_world) * smoothstep(3.0, 0.0, dist_to_mouse);
    }

    // Manta shape logic (simplified for skeleton)
    let body = length(p_mod * vec3<f32>(1.0, 3.0, 0.5)) - 1.0;

    // Wing undulation
    let wing_wave = sin(p_mod.x * 2.0 - u.zoom_params.x * 3.0) * 0.5 * p_mod.x;
    p_mod.y += wing_wave;

    let wings = length(p_mod * vec3<f32>(0.2, 10.0, 1.0)) - 0.5;

    return smin(body, wings, 0.8);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(textureDimensions(writeTexture));
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var p = ro;
    var hit = false;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) { break; }
        t += d;
    }

    // Shading
    var col = vec3<f32>(0.05, 0.0, 0.1); // Void background

    if (hit) {
        let n = calcNormal(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);

        // Audio reactivity from plasma buffer
        let audioBass = plasmaBuffer[0].x * u.zoom_params.y;

        // Obsidian base + glowing veins
        let baseColor = vec3<f32>(0.1);
        let glowColor = vec3<f32>(0.2, 0.8, 1.0) * audioBass * 2.0;

        // Fake vein pattern based on position
        let veins = smoothstep(0.8, 1.0, sin(p.x * 10.0) * sin(p.z * 10.0));

        col = baseColor * diff + glowColor * veins;
    }

    // Volumetric fog/bloom overlay
    col += vec3<f32>(0.1, 0.3, 0.5) * (1.0 - exp(-0.05 * t)) * u.zoom_params.z * max(0.5, u.zoom_params.w);

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
