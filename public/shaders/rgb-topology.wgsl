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
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let density = mix(10.0, 100.0, u.zoom_params.x);
    let parallax = u.zoom_params.y * 0.1;
    let lineThickness = u.zoom_params.z * 0.2 + 0.05;
    let glow = u.zoom_params.w;

    // Parallax logic
    // Mouse determines view angle
    // Mouse center (0.5, 0.5) is neutral
    let tilt = (mouse - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * parallax;

    // We sample R, G, B at different offsets to simulate depth layering
    // Let R be top (closest), G middle, B bottom (furthest)
    // Or R, G, B as layers.

    // Offsets
    let offsetR = tilt * 1.0;
    let offsetG = tilt * 0.5;
    let offsetB = tilt * 0.0; // Base layer

    // Sample
    // We want the contour of Red at uv+offsetR
    // But wait, if we look from an angle, the red layer should be shifted relative to where we are?
    // Let's just shift the UV lookup.

    let rVal = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let gVal = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let bVal = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    // Generate contours
    // sin(val * density)

    // Function to get line strength
    // abs(sin(val * density)) < thickness -> line
    let rLine = smoothstep(lineThickness, 0.0, abs(sin(rVal * density + u.config.x)));
    let gLine = smoothstep(lineThickness, 0.0, abs(sin(gVal * density + u.config.x * 1.1))); // slightly different phase
    let bLine = smoothstep(lineThickness, 0.0, abs(sin(bVal * density + u.config.x * 0.9)));

    // Composite
    // Additive blending of lines
    var finalColor = vec3<f32>(0.0);

    finalColor += vec3<f32>(rLine, 0.0, 0.0);
    finalColor += vec3<f32>(0.0, gLine, 0.0);
    finalColor += vec3<f32>(0.0, 0.0, bLine);

    // Add glow
    // Glow is based on the value itself
    if (glow > 0.0) {
        finalColor += vec3<f32>(rVal, 0.0, 0.0) * glow * 0.5;
        finalColor += vec3<f32>(0.0, gVal, 0.0) * glow * 0.5;
        finalColor += vec3<f32>(0.0, 0.0, bVal) * glow * 0.5;
    }

    // Background dimming
    finalColor += vec3<f32>(0.05); // Dark background

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
