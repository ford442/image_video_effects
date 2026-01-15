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

// Spectral Slit Scan
// Mouse X controls RGB split intensity (temporal lag difference)
// Mouse Y controls the wave distortion of the trails

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Params
    // zoom_params.x: RGB Split (0.0 to 1.0)
    // zoom_params.y: Trail Length (0.0 to 1.0)
    // zoom_params.z: Wave Frequency
    // zoom_params.w: Wave Amplitude

    let rgbSplit = u.zoom_params.x;
    let trailLength = 0.5 + (u.zoom_params.y * 0.49); // 0.5 to 0.99
    let waveFreq = 2.0 + (u.zoom_params.z * 20.0);
    let waveAmp = u.zoom_params.w * 0.05;

    // Current Input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Calculate History Sampling UVs
    // We displace the history lookup to create the "slit scan" wave effect
    // The displacement is based on UV.y and Time
    let waveOffset = sin(uv.y * waveFreq - time * 2.0) * waveAmp;

    // We also pull the history towards the mouse slightly to make it interactive
    let distToMouse = uv - mousePos;
    let mousePull = normalize(distToMouse) * -0.005 * smoothstep(0.4, 0.0, length(distToMouse));

    let historyUV = uv + vec2<f32>(waveOffset, 0.0) + mousePull;

    let historyColor = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

    // Calculate dynamic decay rates for RGB
    var decay = vec3<f32>(trailLength);

    // Apply RGB split: R decays fast, B decays slow (or vice versa) based on Split param
    let splitFactor = rgbSplit * 0.2; // Max deviation
    decay.r = decay.r - splitFactor;
    decay.b = decay.b + splitFactor;

    // Clamp
    decay = clamp(decay, vec3<f32>(0.1), vec3<f32>(0.995));

    // Blend: New = Mix(Input, History, Decay)
    var finalColor = vec4<f32>(0.0);
    finalColor.r = mix(inputColor.r, historyColor.r, decay.r);
    finalColor.g = mix(inputColor.g, historyColor.g, decay.g);
    finalColor.b = mix(inputColor.b, historyColor.b, decay.b);
    finalColor.a = 1.0;

    // Initialize if history is empty
    if (historyColor.a < 0.1) {
        finalColor = inputColor;
    }

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
}
