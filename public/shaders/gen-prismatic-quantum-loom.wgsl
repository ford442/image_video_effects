#include "_prelude.wgsl"

// Core parameters mapped from UI
// u.zoom_params.x = Thread Density
// u.zoom_params.y = Chromatic Shift
// u.zoom_params.z = Gravity Well Strength
// u.zoom_params.w = Quantum Fluctuation Speed

// Math constants and helpers
const PI: f32 = 3.14159265359;

// Domain repetition
fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
    return (p + 0.5 * c) % c - 0.5 * c;
}

// 2D Rotation
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function
fn map(pos: vec3<f32>) -> f32 {
    let time = u.config.x * u.zoom_params.w;
    var p = pos;

    // Apply domain warping based on time
    p.x += sin(p.z * 0.5 + time) * 0.2;
    p.y += cos(p.x * 0.5 + time * 0.8) * 0.2;

    // Audio reactivity (using dataTextureC as audio texture)
    let audioSample = textureLoad(dataTextureC, vec2<i32>(i32((abs(pos.x) + abs(pos.y)) * 10.0), 0), 0).x;
    let audioPulse = audioSample * 0.5;

    // Domain repetition
    let spacing = vec3<f32>(1.5 / u.zoom_params.x);
    p = opRep(p, spacing);

    // SDF of intersecting threads
    let threadRadius = 0.05 + audioPulse;
    let d1 = length(p.xy) - threadRadius;
    let d2 = length(p.yz) - threadRadius;
    let d3 = length(p.zx) - threadRadius;

    return min(min(d1, d2), d3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (coord.x >= resolution.x || coord.y >= resolution.y) {
        return;
    }

    // Normalized device coordinates (-1 to 1)
    let uv = (coord - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Gravity Interaction
    if (u.zoom_config.w > 0.5) {
        let mousePos = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(resolution.x/resolution.y, 1.0);
        let distToMouse = length(uv - mousePos);
        let pull = exp(-distToMouse * 3.0) * u.zoom_params.z;
        // WGSL cannot assign to a swizzle (rd.xy += ...): build the pulled xy, then renormalise.
        let pulledXY = rd.xy + (mousePos - uv) * pull;
        rd = normalize(vec3<f32>(pulledXY, rd.z));
    }

    // Raymarching loop
    var t = 0.0;
    var color = vec3<f32>(0.0);
    var glow = 0.0;

    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = map(p);

        if (d < 0.001 || t > 10.0) {
            break;
        }

        t += d;
        // Accumulate chromatic glow
        glow += 0.02 / (0.01 + d * d);
    }

    // Chromatic shifting based on depth and params
    let shift = u.zoom_params.y;
    color += vec3<f32>(
        sin(t * 1.0 + shift) * 0.5 + 0.5,
        sin(t * 1.2 + shift + 2.0) * 0.5 + 0.5,
        sin(t * 1.4 + shift + 4.0) * 0.5 + 0.5
    ) * glow * 0.05;

    // Tonemapping
    color = color / (1.0 + color);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}