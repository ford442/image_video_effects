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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=LagRed, y=LagBlue, z=MouseInfluence, w=Unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    // High lag value = slow update = more ghosting
    let baseLagR = u.zoom_params.x; // 0..1
    let baseLagB = u.zoom_params.y; // 0..1
    let mouseInfluence = u.zoom_params.z;

    // Mouse influence
    let mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));

    // Increase lag near mouse? Or decrease?
    // Let's make mouse *slow down* time (increase lag).
    // range: 0 to 1
    let influence = smoothstep(0.5, 0.0, dist) * mouseInfluence;

    // Effective lag
    // If lag is 1.0, we never update (freeze). If 0.0, instant update.
    let lagR = clamp(baseLagR + influence, 0.0, 0.99);
    let lagB = clamp(baseLagB + influence * 0.5, 0.0, 0.99);

    // Read History (Previous Frame)
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    // history.r = Old Red
    // history.b = Old Blue
    // history.g = Old Green (but we usually don't lag green, to keep structure)

    // Read Current Input
    let curr = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Update Channels
    // New = History * Lag + Curr * (1 - Lag)
    // This is an exponential moving average (EMA)

    let newR = mix(curr.r, history.r, lagR);
    let newB = mix(curr.b, history.b, lagB);
    let newG = curr.g; // Green is instant (anchor)

    let finalColor = vec4<f32>(newR, newG, newB, 1.0);

    // Output for display
    textureStore(writeTexture, global_id.xy, finalColor);

    // Output for history
    textureStore(dataTextureA, global_id.xy, finalColor);

    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
