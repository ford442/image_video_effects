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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2 (w=isMouseDown)
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn get_lum(c: vec3<f32>) -> f32 {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let layers = floor(mix(2.0, 12.0, u.zoom_params.x));
    let shadowStr = u.zoom_params.y;
    let shadowDist = u.zoom_params.z * 0.05;
    let grain = u.zoom_params.w * 0.2;

    // Mouse Light Source
    let mousePos = u.zoom_config.yz;
    let center = vec2(0.5, 0.5);

    // Light is defined by mouse position relative to center
    // Let's make it intuitive: if mouse is at Top-Right, light comes from Top-Right.
    // Shadows should fall to Bottom-Left.
    // So to check if a pixel is occluded, we look towards the light (Top-Right).
    // Vector towards light:
    let lightVec = normalize(mousePos - center);
    let distStrength = length(mousePos - center) * 2.0;

    // The offset to sample the "blocker"
    // If we are at P, and light is at L, the blocker B would be at P + (dir to L) * dist.
    // If B's "height" (luminance) is greater than P's height, B casts shadow on P.

    let offset = lightVec * shadowDist * clamp(distStrength, 0.2, 1.0);

    let sampleUV = uv + offset;

    let col = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let lum = get_lum(col);

    // Quantize
    let q_lum = floor(lum * layers) / layers;

    // Shadow sample
    let shadow_col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let shadow_lum = floor(get_lum(shadow_col) * layers) / layers;

    var finalCol = col;
    // Quantize color values to create the cutout look
    finalCol = floor(col * layers) / layers;

    // Apply Shadow
    // We only shadow if the blocker is TALLER (brighter) than us.
    // And ideally if we are darker?
    // Let's just say if blocker is higher.
    if (shadow_lum > q_lum) {
        finalCol = finalCol * (1.0 - shadowStr);
    }

    // Grain
    let noise = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
    finalCol += (noise - 0.5) * grain;

    textureStore(writeTexture, global_id.xy, vec4(finalCol, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
