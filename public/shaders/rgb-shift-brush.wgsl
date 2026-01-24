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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Params
    let shiftAmount = u.zoom_params.x * 0.1; // Max shift 0.1 UV
    let brushSize = mix(0.01, 0.2, u.zoom_params.y);
    let decay = mix(0.9, 0.995, u.zoom_params.z);
    let hueShift = u.zoom_params.w;

    // 1. Update Feedback Mask (in DataTextureA)
    // Read previous mask from DataTextureC (using red channel)
    let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Calculate Brush Influence
    let aspect = resolution.x / resolution.y;
    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    let brush = smoothstep(brushSize, brushSize * 0.5, dist); // 1.0 at center, 0.0 at edge

    // New mask value
    let newVal = min(1.0, prevVal * decay + brush);

    // Write to DataTextureA for next frame
    textureStore(dataTextureA, global_id.xy, vec4(newVal, 0.0, 0.0, 1.0));

    // 2. Render Effect
    // Use newVal to control RGB split

    let shift = shiftAmount * newVal;

    // Shift direction could be based on mouse movement, but here we'll just use fixed or noise
    let angle = time * 2.0;
    let dir = vec2(cos(angle), sin(angle));

    let r_uv = uv + dir * shift;
    let b_uv = uv - dir * shift;

    var r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    // Optional Hue Shift on the trail
    if (hueShift > 0.0) {
        // Simple inversion or tinting where the mask is active
        if (newVal > 0.1) {
           r = mix(r, 1.0 - r, hueShift * newVal);
           b = mix(b, 1.0 - b, hueShift * newVal);
        }
    }

    textureStore(writeTexture, global_id.xy, vec4(r, g, b, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
