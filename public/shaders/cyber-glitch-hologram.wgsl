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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Parameters
    let hologram_intensity = u.zoom_params.x; // 0.0 - 1.0
    let glitch_amount = u.zoom_params.y;      // 0.0 - 1.0
    let scan_speed = u.zoom_params.z;         // 0.0 - 2.0
    let mouse_radius = u.zoom_params.w;       // 0.0 - 1.0

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_pos_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let uv_pos_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let dist = distance(uv_pos_aspect, mouse_pos_aspect);

    // Proximity factor: 1.0 near mouse, 0.0 far away
    let proximity = smoothstep(mouse_radius, 0.0, dist);

    // Local glitch boost based on mouse
    let active_glitch = glitch_amount * (1.0 + proximity * 3.0);

    // 1. Digital Glitch (Block shift)
    let block_size = 20.0;
    let block_y = floor(uv.y * block_size);
    // Random glitch trigger
    let noise_val = random(vec2<f32>(time * 5.0, block_y));
    var offset_x = 0.0;

    if (noise_val < active_glitch * 0.1) {
        offset_x = (random(vec2<f32>(time, block_y)) - 0.5) * 0.05 * active_glitch;
    }

    // 2. Chromatic Aberration (RGB Split)
    // Increases with glitch and proximity
    let split_amount = 0.002 * hologram_intensity + (0.01 * proximity * glitch_amount);

    let r_uv = uv + vec2<f32>(offset_x + split_amount, 0.0);
    let g_uv = uv + vec2<f32>(offset_x, 0.0);
    let b_uv = uv + vec2<f32>(offset_x - split_amount, 0.0);

    let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // 3. Scanlines
    let scan_line = sin(uv.y * 800.0 - time * scan_speed * 10.0);
    let scan_mask = 1.0 - (0.15 * hologram_intensity * (scan_line * 0.5 + 0.5));

    // 4. Hologram Tint (Cyan/Blue)
    let tint = vec3<f32>(0.2, 0.8, 1.0);
    // Mix original color with tint based on intensity
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let tint_color = tint * luma * 1.5;

    color = mix(color, tint_color, hologram_intensity * 0.4);

    // Apply scanlines
    color = color * scan_mask;

    // 5. White noise burst on click (optional) or high glitch
    if (noise_val > 0.98 && active_glitch > 0.8) {
         color = vec3<f32>(0.8, 0.9, 1.0); // Bright flash
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
