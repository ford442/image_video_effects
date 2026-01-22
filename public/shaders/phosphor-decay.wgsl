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

    // Params
    let decayRate = mix(0.8, 0.99, u.zoom_params.x); // Persistence
    let mouseIntensity = mix(0.0, 2.0, u.zoom_params.y);
    let mouseRadius = mix(0.01, 0.2, u.zoom_params.z);
    let colorShift = u.zoom_params.w; // Shift color of trails?

    // Read previous frame (History)
    // dataTextureC is the read-only view of the previous frame's dataTextureA
    // Note: If this is the first frame, it might be empty/black.
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Read current input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mouse Beam
    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let beam = smoothstep(mouseRadius, 0.0, dist) * mouseIntensity;
    let beamColor = vec4<f32>(beam, beam, beam, 1.0); // White beam

    // Calculate decayed history
    // Option: shift hue of history?
    var decayed = history * decayRate;

    if (colorShift > 0.1) {
       // Simple tinting of trails: boost G, reduce R/B (Matrix style)
       decayed = decayed * vec4<f32>(0.95, 1.0, 0.95, 1.0);
    }

    // Combine:
    // We want the brighter of (Input + Beam) vs (History).
    // Or (Input + Beam) + History?
    // "Phosphor" logic is usually max(new, old * decay).

    let source = inputColor + beamColor;
    let finalColor = max(source, decayed);

    // Write output
    textureStore(writeTexture, global_id.xy, finalColor);

    // Store for next frame
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
