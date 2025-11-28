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

    // Bounds check
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    // Normalize coordinates to 0.0 - 1.0
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Zoom and Pan from zoom_params (passed via renderer.updateZoomParams)
    // x=fgSpeed (Zoom), y=bgSpeed (Pan X), z=parallaxStrength (Pan Y)
    let zoom = u.zoom_params.x;
    let pan = vec2<f32>(u.zoom_params.y, u.zoom_params.z);

    // Apply zoom and pan logic
    // Coordinates are centered at 0.5
    let modifiedUV = (uv - 0.5) / zoom + 0.5 + (pan - 0.5);

    let fragUV = modifiedUV;

    // Create a simple animated color pattern
    let color1 = vec3<f32>(sin(fragUV.x * 20.0 + time), cos(fragUV.y * 20.0 + time), 0.5);
    let color2 = vec3<f32>(0.1, 0.2, 0.4);
    let pattern = mix(color1, color2, smoothstep(0.4, 0.6, sin(length(fragUV - 0.5) * 15.0 + time)));

    // Sample the input texture (image or video)
    let textureColor = textureSampleLevel(readTexture, u_sampler, fragUV, 0.0);

    // Mix the generated pattern with the input texture
    let finalColor = mix(pattern, textureColor.rgb, 0.6);

    // Write output
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Update depth for next frame (Pass-through)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
