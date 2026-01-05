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
    let brushRadius = mix(0.01, 0.25, u.zoom_params.x);
    let strength = mix(0.1, 2.0, u.zoom_params.y);
    // z used for decay? Or mode?
    let decay = mix(0.8, 0.99, u.zoom_params.z);

    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2(aspect, 1.0), mouse * vec2(aspect, 1.0));

    // "Repel/Smear" logic:
    // We want to sample from a position that pushes pixels away or drags them.
    // Simple repel:
    let dir = normalize(uv - mouse);
    // Push amount drops with distance
    let influence = (1.0 - smoothstep(0.0, brushRadius, dist)) * strength;

    // If influence is high, we sample from closer to mouse (pulling/dragging) or further (pushing)?
    // Smear usually means: color at X comes from X - velocity.
    // If we assume mouse acts as a brush pushing color, pixels should move in direction of push.
    // So at `uv`, we want to sample `uv - push_dir`.
    // Let's use `influence` to offset the sample from history.

    let offset = dir * influence * 0.05; // 0.05 scale factor

    // Sample history with offset
    var historyColor = textureSampleLevel(dataTextureC, u_sampler, uv - offset, 0.0);

    // Sample current video
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mix based on something?
    // If we want the "smear" to persist, we rely heavily on history.
    // Let's mix video into history slowly, unless we are smearing.
    // If smearing (influence > 0), use history more.

    var finalColor = mix(videoColor, historyColor, decay);

    // Inject video if history gets too old?
    // Or just simple feedback loop:
    // result = mix(video, distorted_history, mix_ratio)

    // If influence > 0, we want distorted history to dominate.
    if (influence > 0.0) {
        finalColor = mix(finalColor, historyColor, 0.9);
    }

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
