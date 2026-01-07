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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FrostAmount, y=LensRadius, z=EdgeSoftness, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let frost_amt = u.zoom_params.x; // 0.0 to 1.0
    let lens_radius = u.zoom_params.y * 0.4 + 0.05; // 0.05 to 0.45
    let edge_softness = u.zoom_params.z * 0.2 + 0.01;
    let aberration = u.zoom_params.w * 0.02;

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Lens mask: 0 inside lens (clear), 1 outside (frost)
    let lens_mask = smoothstep(lens_radius, lens_radius + edge_softness, dist);

    // Generate Frost Noise
    let noise_val = hash12(uv * 100.0 + u.config.x * 0.1); // animated noise
    let frost_offset = (noise_val - 0.5) * 0.05 * frost_amt * lens_mask;

    // Sample with offset
    var final_color: vec4<f32>;

    if (lens_mask > 0.001) {
         // Outside or edge of lens: blurred/frosted
         // Cheap blur by jittering sampling
         let sample_uv = uv + vec2<f32>(frost_offset);
         final_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
         // Frost whitening
         final_color = mix(final_color, vec4<f32>(0.9, 0.95, 1.0, 1.0), 0.2 * frost_amt * lens_mask);
    } else {
         // Inside lens: clear
         final_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    }

    // Edge Aberration
    // At the boundary (lens_mask approx 0.5), we add aberration
    let edge_factor = 1.0 - abs(lens_mask * 2.0 - 1.0); // Peak at 0.5? No, smoothstep is monotonic.
    // Actually we want the derivative or just a band around radius.
    // Let's reuse lens_mask transition area.
    let ab_mask = smoothstep(lens_radius, lens_radius + edge_softness * 0.5, dist) * (1.0 - smoothstep(lens_radius + edge_softness * 0.5, lens_radius + edge_softness, dist));

    if (ab_mask > 0.01 && aberration > 0.0) {
        let r_off = normalize(dist_vec) * aberration * 2.0;
        let r = textureSampleLevel(readTexture, u_sampler, uv - r_off, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, uv + r_off, 0.0).b;
        final_color = vec4<f32>(r, final_color.g, b, final_color.a);
    }

    // Smooth transition for color if we split logic
    // Actually simpler to just apply frost offset to UV and mix
    // But we did branch for optimization/logic clarity.
    // Let's refine:

    let uv_r = uv + vec2<f32>(frost_offset) + vec2<f32>(aberration * ab_mask, 0.0);
    let uv_g = uv + vec2<f32>(frost_offset);
    let uv_b = uv + vec2<f32>(frost_offset) - vec2<f32>(aberration * ab_mask, 0.0);

    let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    var color = vec4<f32>(col_r, col_g, col_b, 1.0);

    // Apply frost tint
    color = mix(color, vec4<f32>(0.9, 0.95, 1.0, 1.0), 0.3 * frost_amt * lens_mask);

    textureStore(writeTexture, global_id.xy, color);
}
