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
  config: vec4<f32>;
  zoom_config: vec4<f32>;
  zoom_params: vec4<f32>;
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes: mouse in zoom_config.yz; zoom_params: x=networkDensity, y=signalSpeed, z=decayRate, w=branchComplexity

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898,78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let pulseStrength = u.zoom_config.x;

    // Generate neural points
    let density = max(1.0, u.zoom_params.x);
    var neuralActivity = 0.0;

    for (var i: u32 = 0u; i < 8u; i = i + 1u) {
        let seed = f32(i) * 12.345;
        let neuronPos = vec2<f32>(
            hash(vec2<f32>(seed, 0.0)),
            hash(vec2<f32>(seed, 1.0))
        );

        // Distance to neuron
        let dist = distance(uv, neuronPos);
        let connectionDist = distance(neuronPos, mousePos);

        // Pulse propagation
        let signalSpeed = u.zoom_params.y;
        let pulseTime = time - connectionDist * signalSpeed;
        let pulse = sin(pulseTime * 10.0) * exp(-pulseTime * u.zoom_params.z);

        // Branching patterns
        let branches = max(1.0, u.zoom_params.w);
        let angle = atan2(uv.y - neuronPos.y, uv.x - neuronPos.x);
        let branchPattern = sin(angle * branches + time * 2.0) * 0.5 + 0.5;

        neuralActivity = neuralActivity + pulse * branchPattern / (dist * 5.0 + 1.0);
    }

    // Mouse pulse wave
    let mouseDist = distance(uv, mousePos);
    let mousePulse = sin(mouseDist * 15.0 - time * 8.0) * exp(-mouseDist * 3.0) * pulseStrength;

    // Combine activities
    let totalActivity = neuralActivity + mousePulse;

    // Color mapping based on activity
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv + totalActivity * 0.1, 0.0).rgb;
    let electricBlue = vec3<f32>(0.0, 0.5, 1.0) * max(0.0, totalActivity);
    let synapsePurple = vec3<f32>(0.8, 0.0, 1.0) * max(0.0, -totalActivity);

    var finalColor = baseColor + electricBlue + synapsePurple;

    // Add dendritic glow
    let glow = exp(-abs(totalActivity) * 2.0) * 0.5;
    finalColor = finalColor + vec3<f32>(0.5, 0.8, 1.0) * glow;

    // Glial cell shimmer
    let shimmer = hash(uv * 100.0 + time) * 0.1 * pulseStrength;
    finalColor = finalColor + shimmer;

    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    let depth = 1.0 - clamp(mouseDist * 2.0, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}