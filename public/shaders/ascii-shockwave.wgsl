// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

// Simple hash for noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Shockwave logic
    let aspect = resolution.x / resolution.y;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uv_aspect, mouse_aspect);

    // Wave parameters
    let wave_speed = 2.0;
    let max_radius = 2.0;
    let current_radius = fract(time * wave_speed / max_radius) * max_radius; // Loop the wave
    // Alternatively, just base it on distance from mouse, always active?
    // Let's make it a continuous pulse from the mouse.

    let pulse = sin(dist * 20.0 - time * 10.0); // -1 to 1

    // Define "ASCII" region - where the pulse is high
    let is_ascii = pulse > 0.5;

    var final_color = vec4<f32>(0.0);

    if (is_ascii) {
        // Quantize coordinates
        let cells = 80.0;
        let cell_size = 1.0 / cells;
        let grid_uv = floor(uv * cells) / cells;
        let center_uv = grid_uv + cell_size * 0.5;

        let color = textureSampleLevel(readTexture, u_sampler, center_uv, 0.0);
        let luminance = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

        // Procedural "character"
        let local_uv = fract(uv * cells); // 0 to 1 inside cell
        // Simple pattern based on luminance
        // If lum > 0.5, draw a box, else draw a dot
        var char_mask = 0.0;
        if (luminance > 0.8) {
            // Fill
            char_mask = 1.0;
        } else if (luminance > 0.5) {
            // Box outline
            let border = 0.1;
            if (local_uv.x < border || local_uv.x > 1.0-border || local_uv.y < border || local_uv.y > 1.0-border) {
                char_mask = 1.0;
            }
        } else if (luminance > 0.2) {
            // Cross
            if (abs(local_uv.x - local_uv.y) < 0.1 || abs(local_uv.x - (1.0 - local_uv.y)) < 0.1) {
                char_mask = 1.0;
            }
        } else {
            // Dot
            if (distance(local_uv, vec2<f32>(0.5)) < 0.2) {
                char_mask = 1.0;
            }
        }

        // Matrix Green style
        final_color = vec4<f32>(0.0, luminance * char_mask, 0.0, 1.0);
        // Mix a bit of original color so it's not purely green
        final_color = mix(final_color, color * char_mask, 0.3);

    } else {
        // Normal image
        final_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    }

    // Add a glowing ring at the transition
    let glow = smoothstep(0.4, 0.5, pulse) * smoothstep(0.6, 0.5, pulse);
    final_color = final_color + vec4<f32>(0.0, 1.0, 0.0, 0.0) * glow;

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
