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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse = u.zoom_config.yz; // Mouse position 0-1

    // Params
    let freq = u.zoom_params.x * 50.0 + 5.0;
    let amp = u.zoom_params.y;
    let speed = u.zoom_params.z * 5.0;
    let depth = u.zoom_params.w * 20.0 + 2.0; // Levels of quantization

    // Aspect ratio correction for distance
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    let wave = sin(dist * freq - time * speed);
    // mixVal oscillates between 0 and 1 based on wave
    let mixVal = smoothstep(0.4, 0.6, wave * 0.5 + 0.5);

    // Falloff based on distance (effect strongest at mouse)
    let falloff = smoothstep(1.0, 0.0, dist);
    let effectStrength = mixVal * amp * falloff;

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Quantize
    let levels = floor(depth);
    let quantized = floor(original * levels) / levels;

    let finalColor = mix(original, quantized, effectStrength);

    textureStore(writeTexture, global_id.xy, finalColor);
}
