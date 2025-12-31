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

    // Params
    let direction = u.zoom_params.x; // < 0.5 Horizontal, > 0.5 Vertical
    let threshold = u.zoom_params.y; // Luma threshold
    let strength = u.zoom_params.z * 0.2; // Offset strength
    let blockSize = u.zoom_params.w * 50.0 + 1.0;

    // Mouse control for threshold
    let mouseThreshold = u.zoom_config.z; // Mouse Y controls threshold too
    let effectiveThreshold = (threshold + mouseThreshold) * 0.5;

    // Blocky UV
    let blockUV = floor(uv * resolution / blockSize) * blockSize / resolution;

    // Sample for luma check
    let color = textureSampleLevel(readTexture, u_sampler, blockUV, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    var offsetUV = uv;

    if (luma > effectiveThreshold) {
        let offset = luma * strength;
        if (direction > 0.5) {
            // Vertical
            offsetUV.y = offsetUV.y + offset;
        } else {
            // Horizontal
            offsetUV.x = offsetUV.x + offset;
        }
    }

    let finalColor = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);

    textureStore(writeTexture, global_id.xy, finalColor);
}
