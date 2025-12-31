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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let strength = u.zoom_params.x;        // Distortion strength (0.0 - 1.0)
    let radius = u.zoom_params.y * 0.4;    // Event horizon size (0.0 - 0.4)
    let aberration = u.zoom_params.z;      // Chromatic aberration (0.0 - 0.1)
    let density = u.zoom_params.w;         // Falloff density (0.1 - 5.0)

    // Mouse Interaction (Center of Gravity Well)
    let mouse = u.zoom_config.yz;

    // Calculate vector from mouse to current pixel (aspect corrected)
    let d_vec_raw = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec_raw.x * aspect, d_vec_raw.y);
    let dist = length(d_vec_aspect);

    var final_color = vec3<f32>(0.0, 0.0, 0.0);

    // Apply distortion if outside event horizon (or minimal radius)
    if (dist > radius) {
        // We want a pinch effect that pulls the background towards the mouse.
        // Formula: sample_uv = uv - offset
        // To pull IN, offset must point AWAY from center?
        // No. If we sample at `uv - little_bit_towards_center`, we are grabbing a pixel that is closer to the center and moving it OUT to the current pixel. This magnifies the center (Zoom In / Bulge).
        // Gravity wells usually magnify the background (lensing).

        // Calculate displacement
        let dist_surface = dist - radius;
        let falloff = 1.0 / (pow(dist_surface, density) * 10.0 + 1.0);
        let pull = strength * falloff;

        // Direction from center to pixel (normalize(d_vec_aspect))
        // We want to sample closer to the center.
        let dir = normalize(d_vec_aspect);

        let shift_aspect = dir * pull * 0.1;
        let shift = vec2<f32>(shift_aspect.x / aspect, shift_aspect.y);

        let sample_uv_center = uv - shift;

        // Chromatic Aberration
        let uv_r = sample_uv_center + shift * aberration * 5.0;
        let uv_b = sample_uv_center - shift * aberration * 5.0;

        let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, sample_uv_center, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

        final_color = vec3<f32>(r, g, b);

        // Add a subtle accretion disk glow at the edge
        let glow = exp(-dist_surface * 20.0) * strength;
        final_color += vec3<f32>(0.5, 0.2, 0.8) * glow;

    } else {
        // Inside Event Horizon - Black
        // Maybe a little texture inside?
        final_color = vec3<f32>(0.0, 0.0, 0.0);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
