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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime
  zoom_params: vec4<f32>,  // x=Segments, y=Speed, z=Zoom, w=Unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters mapped to sliders
    // Default to 6.0 segments if param is 0
    let segments = max(u.zoom_params.x * 20.0, 6.0); 
    let speed = u.zoom_params.y * 0.5;
    let zoom_input = max(u.zoom_params.z, 0.5);

    // Center UVs to -1.0 to 1.0
    var centered = uv - 0.5;
    
    // Convert to Polar
    let radius = length(centered);
    var angle = atan2(centered.y, centered.x);

    // Animate rotation
    angle += time * speed;

    // Kaleidoscope Logic
    // Divide the circle into segments and mirror them
    let segment_angle = 6.28318 / segments;
    angle = abs(fract(angle / segment_angle) * 2.0 - 1.0) * segment_angle;

    // Convert back to Cartesian
    // Add rotation back to keep it spinning or static
    // angle -= time * speed; // Uncomment to counter-rotate image inside segment

    let new_pos = vec2<f32>(cos(angle), sin(angle)) * radius / zoom_input;
    let final_uv = new_pos + 0.5;

    // Bounds check to avoid streaking edges
    var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (final_uv.x >= 0.0 && final_uv.x <= 1.0 && final_uv.y >= 0.0 && final_uv.y <= 1.0) {
        color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);
    }

    textureStore(writeTexture, global_id.xy, color);

    // Update depth (Pass-through or sample at new UV)
    // Sampling at new UV keeps the depth aligned with the visual distortion
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, final_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
