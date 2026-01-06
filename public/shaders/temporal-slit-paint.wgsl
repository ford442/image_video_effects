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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let brushSize = mix(0.01, 0.3, u.zoom_params.x);
    let decay = mix(0.9, 1.0, u.zoom_params.y);
    let noiseAmt = u.zoom_params.z * 0.1;
    let mode = u.zoom_params.w; // 0 = Paint Video, 1 = Reveal History (not impl)

    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2(aspect, 1.0), mouse * vec2(aspect, 1.0));

    var finalColor: vec4<f32>;
    let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Brush logic
    let brushSoftness = 0.05;
    let brushMask = 1.0 - smoothstep(brushSize - brushSoftness, brushSize, dist);

    if (brushMask > 0.0) {
        // Sample current video with some noise/jitter
        let noise = vec2<f32>(
            fract(sin(dot(uv + u.config.x, vec2(12.9898, 78.233))) * 43758.5453),
            fract(cos(dot(uv + u.config.x * 2.0, vec2(23.421, 56.789))) * 23421.123)
        ) * noiseAmt;

        let videoColor = textureSampleLevel(readTexture, u_sampler, uv + noise, 0.0);

        // Mix video onto history
        finalColor = mix(historyColor, videoColor, brushMask);
    } else {
        // Just decay history
        finalColor = historyColor * decay;
    }

    // Ensure alpha is 1
    finalColor.a = 1.0;

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
