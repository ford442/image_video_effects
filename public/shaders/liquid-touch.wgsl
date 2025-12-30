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

    // Params
    let viscosity = u.zoom_params.x;     // 0.0-1.0 (How fast ripples fade)
    let brush_size = u.zoom_params.y;    // 0.0-1.0
    let refraction = u.zoom_params.z;    // 0.0-1.0
    let tint_strength = u.zoom_params.w; // 0.0-1.0

    // Read previous state from dataTextureC (ping-pong input)
    // State: R = Height/Intensity, G = Unused, B = Unused, A = Unused
    let old_state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var height = old_state.r;

    // Decay the height (Viscosity)
    // Higher viscosity = slower decay? Or standard fluid term?
    // Let's map viscosity param to decay factor.
    // Param 0.0 -> Fast decay (0.9), Param 1.0 -> Slow decay (0.99)
    let decay = 0.9 + (viscosity * 0.095);
    height = height * decay;

    // Mouse Interaction
    // Add height if mouse is pressed or just moving?
    // "mouse-driven" -> u.zoom_config.w is MouseDown (1.0)
    let mouse = u.zoom_config.yz;
    let mouse_down = u.zoom_config.w;

    // Always leave a trail if mouse is moving?
    // Let's assume yes, or just check distance.
    // If mouse is (0,0) it might be uninitialized, but let's ignore that edge case for now.

    let d_vec = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec.x * aspect, d_vec.y);
    let dist = length(d_vec_aspect);

    // Brush radius
    let radius = 0.01 + (brush_size * 0.05);

    // If mouse is near, add to height
    // We check mouse_down if we only want to paint when clicking.
    // Memory said "Mouse responsive", usually implies movement or click.
    // Let's allow painting on movement, maybe stronger on click.
    // But `mouse-driven` implies we get valid coordinates.
    // If we want it to be "Liquid Touch", it should react to touch/mouse.

    if (dist < radius) {
        let add = (1.0 - dist/radius);
        // Add more if mouse down, or just constant
        let intensity = 0.5 + (mouse_down * 0.5);
        height = min(height + add * intensity * 0.2, 2.0); // Cap height
    }

    // Diffusion (spread to neighbors)
    // Simple box blur on height field would be better in a separate pass,
    // but here we are single pass.
    // We can't easily read neighbors from dataTextureC consistently for diffusion in same pass
    // without risking read/write races if we were writing to same, but we write to A.
    // However, just adding at mouse + decay is more like "Paint" than "Liquid Simulation".
    // Real liquid needs neighbor sampling.

    // Let's sample neighbors from C
    let texel = vec2<f32>(1.0/resolution.x, 1.0/resolution.y);
    let n_u = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let n_d = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let n_l = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
    let n_r = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;

    // Average
    let avg = (n_u + n_d + n_l + n_r) * 0.25;

    // Blend current height towards average (Smooth/Diffuse)
    height = mix(height, avg, 0.5);

    // Write new state to dataTextureA (History)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(height, 0.0, 0.0, 1.0));

    // Render Logic
    // Use gradient of height to distort UVs (Refraction)
    let grad_x = n_r - n_l;
    let grad_y = n_d - n_u;

    let distort = vec2<f32>(grad_x, grad_y) * refraction * 2.0;
    let sample_uv = uv - distort;

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    // Tint based on height
    // High spots get tinted blue/cyan
    if (tint_strength > 0.0) {
        let tint_col = vec3<f32>(0.0, 1.0, 1.0); // Cyan
        color = mix(color, tint_col, height * tint_strength * 0.5);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
