struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// Simple hash function for noise
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / vec2<f32>(dims);

    // Parameters
    let obs_strength = u.zoom_params.x; // Observation Field
    let speed = u.zoom_params.y; // Fluctuation Speed
    let energy = u.zoom_params.z; // Energy Level
    let uncertainty = u.zoom_params.w; // Uncertainty

    let time = u.config.y * (0.5 + speed * 2.0);
    let mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;

    // Distance to mouse (Observation)
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Calculate observation probability (collapse wave function)
    // Closer to mouse = higher probability of seeing the "real" image
    let radius = mix(0.1, 0.8, obs_strength);
    let collapse = smoothstep(radius, 0.0, dist);

    // Generate Quantum Noise (Visual Fluctuations)
    let seed = vec3<f32>(uv * 50.0, time);
    let noise = hash3(seed);

    // Original Image
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgba;

    // Quantum Color (Schrodinger's Cat states)
    // Shift hue based on energy
    let q_color = 0.5 + 0.5 * sin(time + uv.xyx * 10.0 + vec3<f32>(0.0, 2.0, 4.0));
    let chaotic_color = mix(noise, q_color, energy);

    // Mix based on collapse
    // If collapsed (near mouse), show image. Else show chaos.
    // Also use uncertainty to add noise even when collapsed

    let mix_factor = (1.0 - collapse) * (0.5 + 0.5 * uncertainty);

    var final_color = mix(base_color.rgb, chaotic_color, mix_factor);

    // Add "Probability Cloud" glow around the transition
    let glow = (1.0 - abs(collapse * 2.0 - 1.0)) * energy * 0.5;
    final_color += vec3<f32>(0.2, 0.5, 1.0) * glow;

    textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));
}
