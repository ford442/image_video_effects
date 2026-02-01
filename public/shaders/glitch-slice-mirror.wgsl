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

    // Mirror Logic
    // Mirror the left side onto the right side, pivoted at mouse.x
    var target_uv = uv;
    if (uv.x > mouse.x) {
        target_uv.x = mouse.x - (uv.x - mouse.x);
    }

    // Glitch Logic near seam
    let dist_to_seam = abs(uv.x - mouse.x);
    let glitch_width = 0.1;

    var color = vec4<f32>(0.0);

    if (dist_to_seam < glitch_width) {
        // Intensity fades out as we move away from seam
        let intensity = (1.0 - dist_to_seam / glitch_width);

        // Blocky noise
        let block_size = vec2<f32>(0.05, 0.02);
        let seed = floor(uv / block_size) + time;
        let noise = hash(seed);

        if (noise > 0.8) {
            // Horizontal displacement
            target_uv.x = target_uv.x + (noise - 0.5) * 0.1 * intensity;
        }

        // Chromatic Aberration
        let split = 0.02 * intensity * noise;
        let r = textureSampleLevel(readTexture, u_sampler, target_uv + vec2<f32>(split, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, target_uv - vec2<f32>(split, 0.0), 0.0).b;
        color = vec4<f32>(r, g, b, 1.0);

        // Scanline darkening
        if (sin(uv.y * 200.0) > 0.9) {
            color = color * 0.5;
        }
    } else {
        color = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass depth (using distorted UV)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, target_uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
