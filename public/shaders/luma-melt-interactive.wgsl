// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // History Write
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // History Read
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

// Luma Melt Interactive
// Param1: Melt Speed
// Param2: Trail Persistence (Decay)
// Param3: Mouse Heat Radius
// Param4: Mouse Heat Intensity

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let meltSpeed = u.zoom_params.x * 0.05; // Vertical flow per frame
    let persistence = u.zoom_params.y; // 0..1
    let radius = max(u.zoom_params.z, 0.01);
    let heat = u.zoom_params.w * 0.1;

    // Current video frame
    let newColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(newColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Mouse Influence (Heat)
    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let mouseFactor = smoothstep(radius, 0.0, dist);

    // Calculate source UV for the melt
    // The pixel at 'uv' receives color from 'uv - flow'.
    // Flow depends on Luma (brighter melts faster) and Mouse (Heat melts faster).

    let totalFlow = meltSpeed * luma + (heat * mouseFactor);

    // We sample from UP (y - flow).
    let sourceUV = vec2<f32>(uv.x, uv.y - totalFlow);

    // Read history from dataTextureC
    // If sourceUV is off screen, we take 0 or repeat? Clamp.
    let clampedUV = clamp(sourceUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // History sample (previous frame's melted state)
    let history = textureSampleLevel(dataTextureC, u_sampler, clampedUV, 0.0);

    // Blend: We want the video to constantly "feed" the melt.
    // Result = Mix(NewVideo, History, Persistence).
    // If Persistence is high, we see mostly history (trails).
    // If Persistence is low, we see mostly new video.

    // But we also want the history itself to move.
    // By sampling history at 'sourceUV', we are effectively moving the history image down.

    let blended = mix(newColor, history, persistence);

    // Write to display
    textureStore(writeTexture, global_id.xy, blended);

    // Write to history (dataTextureA)
    textureStore(dataTextureA, global_id.xy, blended);
}
