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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    // x: min grid size (0.0 = high res/no pixelation, 1.0 = big blocks)
    // y: max grid size
    // z: radius
    // w: softness

    let min_grid = mix(1000.0, 50.0, u.zoom_params.x); // High number = small pixels
    let max_grid = mix(1000.0, 10.0, u.zoom_params.y);
    let radius = u.zoom_params.z;
    let softness = u.zoom_params.w;

    var dVec = uv - mousePos;
    dVec.x *= aspect;
    let dist = length(dVec);

    let t = smoothstep(radius, radius + softness + 0.001, dist);
    let current_grid = mix(max_grid, min_grid, t); // Near mouse = max_grid (low res) or min_grid (high res)?

    // "Focal Pixelate" usually means clear in center, pixelated outside.
    // So let's invert logic:
    // Near mouse (dist < radius) => High Res (min_grid is actually just normal sampling if we handle it right)
    // Far from mouse => Low Res (max_grid)

    // Let's re-parameterize for clarity in usage:
    // Param X: Pixelation Amount (at edge)
    // Param Y: Focus Size (Radius)
    // Param Z: Focus Falloff (Softness)
    // Param W: Invert (0 = Clear Center, 1 = Pixelated Center)

    let pixel_strength = mix(500.0, 20.0, u.zoom_params.x); // 500 = small blocks, 20 = huge blocks
    let focus_radius = u.zoom_params.y;
    let focus_falloff = u.zoom_params.z;
    let invert = u.zoom_params.w > 0.5;

    var mix_factor = smoothstep(focus_radius, focus_radius + focus_falloff + 0.001, dist);
    if (invert) {
        mix_factor = 1.0 - mix_factor;
    }

    // if mix_factor is 0 (center), we want high res. If 1 (edge), we want pixel_strength.
    // Ideally high res is direct sampling.
    // But for pixelation code:
    let blocks = mix(2000.0, pixel_strength, mix_factor);

    let pixel_uv = floor(uv * blocks) / blocks + (0.5 / blocks); // Center sample

    let color = textureSampleLevel(readTexture, non_filtering_sampler, pixel_uv, 0.0).rgb;

    textureStore(writeTexture, global_id.xy, vec4(color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
