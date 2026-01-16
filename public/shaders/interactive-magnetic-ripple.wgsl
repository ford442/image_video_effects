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

// Interactive Magnetic Ripple
// Param1: Field Strength
// Param2: Frequency
// Param3: Damping
// Param4: Aberration

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let strength = u.zoom_params.x * 0.5; // Max distortion strength
    let freq = u.zoom_params.y * 50.0;
    let damping = u.zoom_params.z;
    let aberration = u.zoom_params.w * 0.05;

    var totalDisplacement = vec2<f32>(0.0);

    // Magnetic pull towards mouse
    if (mousePos.x >= 0.0) {
        let diff = mousePos - uv;
        // Correct for aspect ratio in distance
        let diffAspect = vec2<f32>(diff.x * aspect, diff.y);
        let dist = length(diffAspect);

        let dir = normalize(diff);

        // 1. Magnetic Pull (Attracts pixels)
        // Stronger near mouse, falls off
        let mag = strength / (dist + 0.1);

        // 2. Ripple Modulation
        // cos(dist * freq - time * speed)
        let ripple = cos(dist * freq - time * 5.0) * exp(-dist * damping * 5.0);

        totalDisplacement = dir * (mag * 0.1 + ripple * 0.05);
    }

    // Aberration
    let rUV = uv - totalDisplacement * (1.0 + aberration);
    let gUV = uv - totalDisplacement;
    let bUV = uv - totalDisplacement * (1.0 - aberration);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let color = vec4<f32>(r, g, b, 1.0);

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
