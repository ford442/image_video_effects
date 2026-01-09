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
  zoom_params: vec4<f32>,  // x=BrickSize, y=Refraction, z=Grout, w=MouseClear
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    let brick_count = u.zoom_params.x * 40.0 + 5.0; // 5 to 45
    let refraction = u.zoom_params.y * 0.1;
    let grout_width = u.zoom_params.z * 0.1;
    let mouse_clear_radius = u.zoom_params.w * 0.4;

    let aspect = resolution.x / resolution.y;
    // Scale UVs to create brick grid
    let uv_scaled = uv * vec2<f32>(brick_count * aspect, brick_count);

    let brick_id = floor(uv_scaled);
    let brick_uv = fract(uv_scaled); // 0-1 within brick

    // Center of the brick in UV space
    let brick_center_uv = (brick_id + 0.5) / vec2<f32>(brick_count * aspect, brick_count);

    // Mouse distance to pixel
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Mask for mouse clearing effect (1.0 near mouse, 0.0 far)
    let clear_mask = smoothstep(mouse_clear_radius, mouse_clear_radius * 0.5, dist);

    // Grout logic
    var is_grout = 0.0;
    if (brick_uv.x < grout_width || brick_uv.x > 1.0 - grout_width ||
        brick_uv.y < grout_width || brick_uv.y > 1.0 - grout_width) {
        is_grout = 1.0;
    }

    // Refraction: bulge center of brick
    let b_uv_centered = brick_uv - 0.5;
    // Simple lens distortion inside brick
    let lens = dot(b_uv_centered, b_uv_centered);
    // Distort from center outward or inward
    let distort_offset = b_uv_centered * (0.5 - lens) * refraction;

    // Mix between brick center (solid/pixelated look) and true UV based on refraction?
    // Actually, glass bricks distort the image behind them.
    // They usually show a mini-fisheye view of the scene behind the brick.
    // So we sample relative to the brick center, but using the brick_uv to offset.

    var sample_uv = brick_center_uv + distort_offset;

    // If near mouse, revert to normal UV
    sample_uv = mix(sample_uv, uv, clear_mask);

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

    // Darken grout
    if (is_grout > 0.5 && clear_mask < 0.5) {
        color = color * 0.5;
    }

    textureStore(writeTexture, global_id.xy, color);

     // Depth pass-through
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, sample_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
