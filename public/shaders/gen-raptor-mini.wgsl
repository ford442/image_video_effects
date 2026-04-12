// ----------------------------------------------------------------
// Raptor Mini
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
    zoom_params: vec4<f32>,  // x=Turn Speed, y=Max Speed, z=Rage Duration, w=Rage Speed Boost
    ripples: array<vec4<f32>, 50>,
};

// Agent state mapped to extraBuffer conceptually, but rendered generatively here
fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
    let time = u.config.x;

    // Audio rage mode affects visual intensity
    let rage = u.config.y * u.zoom_params.w;

    // Simulating raptor agents through a generative cellular noise approach
    var col = vec3<f32>(0.0);

    let scale_pattern = 4.0;
    var st = uv * scale_pattern * 5.0;

    // Simulate raptors moving toward mouse
    let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0) * vec2<f32>(f32(dims.x) / f32(dims.y), 1.0);

    // Turn Speed controls how intensely they swerve towards the mouse
    let turn_speed = u.zoom_params.x;
    let base_dir = normalize(uv);
    let target_dir = normalize(mouse - uv);
    let dir_to_mouse = mix(base_dir, target_dir, turn_speed);

    // Offset cells by time and speed
    st += dir_to_mouse * time * u.zoom_params.y;

    let id = floor(st);
    let f = fract(st) - 0.5;

    let rng = hash21(id);
    let dist = length(f) - 0.2 * (1.0 + rage * 0.5);

    if(dist < 0.0) {
        // Raptor body
        col = vec3<f32>(0.2, 0.8, 0.3) * (0.5 + 0.5 * rng.x) + vec3<f32>(rage * 0.8, 0.0, 0.0);

        // Scale pattern on raptor
        let scale_tex = fract(length(f * u.zoom_params.z * 10.0));
        col *= scale_tex;
    } else {
        // Trail / Background
        col = mix(vec3<f32>(0.01, 0.02, 0.03), vec3<f32>(0.05, 0.1, 0.05), pow(max(0.0, 1.0 - length(uv - mouse)), 2.0));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}