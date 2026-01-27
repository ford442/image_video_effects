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
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous Frame
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / vec2<f32>(dims);

    let radius = u.zoom_params.x; // Field Radius
    let time_lag = u.zoom_params.y; // Time Lag (mix factor)
    let ghosting = u.zoom_params.z; // Ghosting
    let warp_strength = u.zoom_params.w; // Warp

    let mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;

    // Field Calculation
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Field strength (1.0 near mouse, 0.0 far away)
    // Actually, "Temporal Distortion" implies SLOW time far away? Or fast near mouse?
    // Let's say near mouse is "Real Time", far away is "Slow Time" (laggy).
    let field = smoothstep(radius + 0.2, radius, dist); // 1.0 near mouse

    // Warp space based on time field
    // Spiral twist
    let angle = atan2(dist_vec.y, dist_vec.x);
    let twist = sin(dist * 10.0 - u.config.y * 2.0) * warp_strength * field;
    let warped_uv = uv + vec2<f32>(cos(angle + twist), sin(angle + twist)) * 0.01 * warp_strength;

    // Sample Current Frame
    let current_color = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0);

    // Sample Previous Frame (dataTextureC)
    let prev_color = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0); // No warp on history to create smear

    // Mix Logic
    // If field is high (near mouse), update fast (mix -> 1.0)
    // If field is low (far), update slow (mix -> low value)

    // Base update rate (global time lag)
    let base_rate = mix(0.05, 1.0, 1.0 - time_lag);

    // Local update rate modulated by field
    // Near mouse: update rate = 1.0 (instant)
    // Far: update rate = base_rate
    let update_rate = mix(base_rate, 1.0, field);

    // Ghosting (Feedback Decay)
    // If ghosting is high, the previous frame persists longer
    // We modify the mix factor based on ghosting
    // High ghosting -> lower update rate
    let final_mix = update_rate * (1.0 - ghosting * 0.5);

    // Color Accumulation
    // New Color = lerp(Old, New, rate)
    let new_pixel = mix(prev_color, current_color, final_mix);

    // Visualize the field slightly (temporal distortion shimmer)
    let shimmer = sin(uv.y * 100.0 + u.config.y * 10.0) * 0.05 * (1.0 - field) * ghosting;
    let final_color = new_pixel.rgb + vec3<f32>(shimmer);

    // Write to Output (Display)
    textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));

    // Write to Feedback Buffer (dataTextureA -> becomes dataTextureC next frame)
    // We store the accumulated color
    textureStore(dataTextureA, coord, new_pixel);
}
