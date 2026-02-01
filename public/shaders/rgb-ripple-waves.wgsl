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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uv_aspect, mouse_aspect);

    // Parameters
    let frequency = 50.0;
    let speed = 5.0;
    let amplitude = 0.02 * exp(-dist * 2.0); // Decay with distance

    // Phase shifts for RGB
    let phase_r = 0.0;
    let phase_g = 1.0; // Phase offset
    let phase_b = 2.0; // Phase offset

    // Calculate waves
    let wave_r = sin(dist * frequency - time * speed + phase_r);
    let wave_g = sin(dist * frequency - time * speed + phase_g);
    let wave_b = sin(dist * frequency - time * speed + phase_b);

    // Displace UVs
    var displacement_r = vec2<f32>(0.0);
    var displacement_g = vec2<f32>(0.0);
    var displacement_b = vec2<f32>(0.0);

    if (dist > 0.001) {
        // Calculate direction in aspect-corrected space for circular ripples
        let dir_aspect = normalize(uv_aspect - mouse_aspect);
        // Convert direction back to UV space (undo aspect correction)
        let dir_uv = vec2<f32>(dir_aspect.x / aspect, dir_aspect.y);

        displacement_r = dir_uv * wave_r * amplitude;
        displacement_g = dir_uv * wave_g * amplitude;
        displacement_b = dir_uv * wave_b * amplitude;
    }

    let r = textureSampleLevel(readTexture, u_sampler, uv + displacement_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + displacement_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + displacement_b, 0.0).b;

    let final_color = vec4<f32>(r, g, b, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
