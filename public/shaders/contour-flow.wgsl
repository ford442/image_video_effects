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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let flowSpeed = u.zoom_params.x * 5.0;      // Speed of the flow animation
    let flowLength = u.zoom_params.y * 0.05;    // Max length of displacement
    let mouseRadius = u.zoom_params.z * 0.5 + 0.01; // Radius of mouse influence
    let edgeDetect = u.zoom_params.w * 5.0;     // Sensitivity to edges (gradient mag)

    let mouse = u.zoom_config.yz; // Mouse coordinates (0-1)

    // 1. Calculate Luminance Gradient (Sobel-ish) to find contours
    let texel = vec2<f32>(1.0) / resolution;

    // Sample neighbors
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;

    let gradX = r - l;
    let gradY = b - t;

    // Tangent (Flow direction) is perpendicular to gradient
    // Gradient points uphill (brightest). Contours are perpendicular.
    let flowDir = normalize(vec2<f32>(-gradY, gradX) + vec2<f32>(0.0001));
    let gradMag = length(vec2<f32>(gradX, gradY));

    // 2. Calculate Mouse Influence
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    // Smooth falloff from center
    let mouseFactor = smoothstep(mouseRadius, 0.0, dist);

    // 3. Calculate Displacement
    // Only flow where there is detail (gradient) and where mouse is near.
    // Base flow on edges + mouse interaction.

    // Oscillate the flow back and forth or continuously?
    // Let's make it wiggle.
    let wave = sin(uv.x * 10.0 + uv.y * 10.0 + time * flowSpeed);

    // Strength combines:
    // - edgeDetect * gradMag: only flow on actual edges
    // - mouseFactor: only flow near mouse
    // - flowLength: global scaler
    let strength = (gradMag * edgeDetect + 0.2) * mouseFactor * flowLength;

    // Apply offset
    let offset = flowDir * strength * wave;

    // Sample with offset
    let color = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0);

    // Optional: Add a slight highlight to the flowing areas
    let highlight = length(offset) * 10.0; // visualize flow intensity

    textureStore(writeTexture, global_id.xy, color + vec4<f32>(highlight * 0.1));
}
