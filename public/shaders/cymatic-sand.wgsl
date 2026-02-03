// ═══════════════════════════════════════════════════════════════
//  Cymatic Sand
//  Simulates Chladni plate patterns (sand on a vibrating plate)
// ═══════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Parameters
    // Mouse determines n and m modes
    // Map mouse 0..1 to modes 1..20
    let n = floor(mouse.x * 20.0) + 1.0;
    let m = floor(mouse.y * 20.0) + 1.0;

    // Sliders
    let sandAmount = u.zoom_params.x;
    let lineWidth = u.zoom_params.y * 0.1 + 0.01;
    let grainSize = u.zoom_params.z * 500.0 + 100.0;
    let contrast = u.zoom_params.w + 1.0;

    // Adjust UV to -1..1 for symmetry
    let p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Chladni Formula
    // A common variation: cos(n*pi*x)*cos(m*pi*y) - cos(m*pi*x)*cos(n*pi*y)
    let pi = 3.14159;
    let wave = cos(n * pi * p.x) * cos(m * pi * p.y) - cos(m * pi * p.x) * cos(n * pi * p.y);

    // Nodal lines are where wave is close to 0
    let vibration = abs(wave);

    // Sand Simulation
    // Sand accumulates where vibration is low
    // Probability of sand being at pixel p
    let sandProb = 1.0 - smoothstep(0.0, lineWidth, vibration);

    // Procedural Sand Grain
    // High frequency noise
    let noiseVal = hash(uv * grainSize);

    // Threshold noise based on probability
    // If noise > (1.0 - sandProb), draw sand
    // Adjust density with sandAmount
    let sand = step(1.0 - sandProb * sandAmount, noiseVal);

    // Background Image
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Darken background slightly to show white sand
    color *= 0.5;

    // Add Sand
    // Sand color is white/beige
    let sandColor = vec3<f32>(0.9, 0.85, 0.7);
    color = mix(color, sandColor, sand);

    // Optional: Visualise vibration (heat map) for debugging or effect
    // color += vec3<f32>(vibration * 0.1, 0.0, 0.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
