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
  zoom_config: vec4<f32>, // y,z is mouse
  zoom_params: vec4<f32>, // x: warp strength, y: echo decay, z: radius, w: luma weight
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let strength = u.zoom_params.x * 2.0; // Warp strength
    let decay = 0.9 + u.zoom_params.y * 0.09; // Echo decay
    let radius = 0.1 + u.zoom_params.z * 0.4;
    let lumaWeight = u.zoom_params.w;

    // Current Image
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Calculate Warp Vector
    var warp = vec2<f32>(0.0);
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        // Warp calculation: push away based on proximity
        let influence = smoothstep(radius, 0.0, dist);

        // Luma factor: brighter pixels might move less (heavier) or more
        // Let's say bright pixels are 'lighter' and move more
        let weight = mix(1.0, luma, lumaWeight);

        warp = normalize(dVec) * influence * strength * weight * 0.1;
    }

    // Sample distorted UV
    let distortedUV = uv - warp;
    let warpedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Read History (Echo)
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Combine
    var outputColor = warpedColor;

    // Echo logic: Mix current warped frame with history
    let mixed = mix(warpedColor, history, decay);

    // If mouse is down, we inject more of the warped current frame to "break" the echo
    outputColor = mix(mixed, warpedColor, isMouseDown * 0.5);

    // Write output
    outputColor.a = 1.0;
    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outputColor);
}
