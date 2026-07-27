// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Void-Tortoise
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


// ----------------------------------------------------------------
// Mouse Interaction:
// Mouse x and y coordinates from u.zoom_config.yz are mapped to
// gravitational drag on the environment.
//
// Audio Reactivity:
// Uses plasmaBuffer[0].x which is modulated by Evolution Speed (u.config.w)
//
// Sliders (u.config):
// x - Time
// y - Audio Reactivity multiplier
// z - Brightness multiplier
// w - Evolution Speed multiplier
// ----------------------------------------------------------------
struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec2<f32>,
    config: vec4<f32>, // Time, Audio Reactivity, Brightness, Evolution Speed
    zoom_config: vec4<f32>, // Zoom, MouseX, MouseY, Custom
}

struct Particle {
    position: vec4<f32>,
    velocity: vec4<f32>,
    color: vec4<f32>,
    life: f32,
}

// 3D Rotation Matrix Function
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// Smooth Minimum for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// KIFS Fractal for the shell's pocket dimension
fn kifs(p: vec3<f32>, time: f32) -> f32 {
    var z = p;
    var scale = 1.0;
    for (var i = 0; i < 4; i++) {
        z = abs(z) - vec3<f32>(0.5, 0.5, 0.5);
        z = z * rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), time * 0.1);
        z = z * 2.0;
        scale = scale * 2.0;
    }
    return (length(z) - 1.0) / scale;
}

// Main SDF Map
fn map(p: vec3<f32>, time: f32, audio_reactivity: f32, mouse: vec2<f32>) -> vec2<f32> {
    var p_distorted = p;

    // Gravitational Drag from mouse
    let mouse_pos = vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse > 0.0) {
        let twist_angle = 1.0 / (dist_to_mouse + 0.5) * 2.0;
        p_distorted = p_distorted * rot3D(normalize(mouse_pos + vec3<f32>(0.0, 0.0, 1.0)), twist_angle);
    }

    // Tortoise Body Base
    let body = length(p_distorted * vec3<f32>(1.0, 2.0, 1.0)) - 1.5;

    // Tortoise Shell (Pocket Dimension)
    let shell_base = length(p_distorted * vec3<f32>(1.0, 1.5, 1.0) - vec3<f32>(0.0, 0.5, 0.0)) - 1.6;
    let shell_fractal = kifs(p_distorted, time);
    let shell = max(shell_base, shell_fractal * 0.5);

    // Blending body and shell
    let tortoise = smin(body, shell, 0.3);

    // Material IDs
    var mat_id = 1.0; // Body
    if (shell < body) {
        mat_id = 2.0; // Shell
    }

    return vec2<f32>(tortoise, mat_id);
}

// Raymarching Loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio_reactivity: f32, mouse: vec2<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat_id = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, time, audio_reactivity, mouse);
        if (d.x < 0.001) {
            mat_id = d.y;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d.x;
    }
    return vec2<f32>(t, mat_id);
}

// Main compute shader entry point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.resolution;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) / resolution.xy) * 2.0 - 1.0;
    let aspect = resolution.x / resolution.y;
    let screen_uv = vec2<f32>(uv.x * aspect, uv.y);

    let time = u.config.x * u.config.w;
    let audio_bass = plasmaBuffer[0].x * u.config.y;
    let mouse = u.zoom_config.yz;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let rd = normalize(vec3<f32>(screen_uv, -1.5));

    // Raymarching
    let result = raymarch(ro, rd, time, audio_bass, mouse);
    let t = result.x;
    let mat_id = result.y;

    var color = vec3<f32>(0.0); // Background void

    if (t < 20.0) {
        // Shading based on mat_id
        if (mat_id == 1.0) {
            // Body shading (obsidian-glass)
            color = vec3<f32>(0.1, 0.15, 0.2);
        } else if (mat_id == 2.0) {
            // Shell shading (fractal emissive)
            let emissive_color = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(time + t * 5.0) * 0.5 + 0.5);
            color = emissive_color * (1.0 + audio_bass * 2.0);
        }
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(color * u.config.z, 1.0));
}
