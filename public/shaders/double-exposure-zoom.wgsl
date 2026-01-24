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

// Double Exposure Zoom
// Param 1: Rotation (Input 0..1 maps to -PI..PI)
// Param 2: Zoom Level (Input 0..1 maps to 0.25x .. 4.0x)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Mouse handling
    var mouse = u.zoom_config.yz;
    // If mouse is inactive (often -1 or similar check, but config.yz is usually valid 0-1 if inside canvas)
    // We can just assume it's valid or default to center if needed.
    // Usually Renderer sets it to last known position.

    // Parameters
    let rot = (u.zoom_params.x - 0.5) * 6.28318; // -PI to PI
    // Logarithmic zoom scale feels more natural
    let zoom = pow(2.0, (u.zoom_params.y - 0.5) * 4.0); // 2^-2 (0.25) to 2^2 (4.0)

    // Sample Base Layer
    let col1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Calculate UV for Second Layer (Transformed)
    // Pivot is Mouse
    var uv2 = uv - mouse;

    // Aspect Correct Rotation
    uv2.x *= aspect;
    let c = cos(rot);
    let s = sin(rot);
    let rx = uv2.x * c - uv2.y * s;
    let ry = uv2.x * s + uv2.y * c;
    uv2 = vec2<f32>(rx, ry);
    uv2.x /= aspect;

    // Apply Zoom
    uv2 /= zoom;

    // Translate back
    uv2 += mouse;

    // Sample Second Layer
    // We sample with clamp-to-edge usually, which might look like streaks at the border.
    // Let's fade it out if it goes too far to look cleaner.
    var col2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

    // Blend: Screen Mode
    // result = 1 - (1 - a) * (1 - b)
    let blended = 1.0 - (1.0 - col1.rgb) * (1.0 - col2.rgb);

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(blended, 1.0));
}
