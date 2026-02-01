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

// Lighthouse Reveal
// Param 1: Beam Length (Radius)
// Param 2: Beam Width (Angle)
// Param 3: Edge Softness
// Param 4: Ambient Light

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Correct UV for aspect ratio for distance calculations
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouse = get_mouse();
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let radius = u.zoom_params.x;
    let beam_width = u.zoom_params.y; // 0.05 to 1.0 (roughly radians / PI)
    let softness = u.zoom_params.z;
    let ambient = u.zoom_params.w;
    let time = u.config.x;

    let dist = distance(uv_aspect, mouse_aspect);
    let angle = atan2(uv_aspect.y - mouse_aspect.y, uv_aspect.x - mouse_aspect.x);

    // Rotation speed
    let rotation = time * 2.0;

    // Normalize angle difference to -PI to PI
    var angle_diff = angle - rotation;
    let pi = 3.14159265;
    angle_diff = (fract((angle_diff / (2.0 * pi)) + 0.5) - 0.5) * 2.0 * pi;

    // Calculate Beam Mask
    // Angular falloff
    let angle_dist = abs(angle_diff);
    let angle_mask = 1.0 - smoothstep(beam_width * pi * 0.5, (beam_width * pi * 0.5) + softness + 0.01, angle_dist);

    // Radial falloff
    let radial_mask = 1.0 - smoothstep(radius, radius + softness + 0.01, dist);

    // Combined mask
    let mask = angle_mask * radial_mask;

    // Apply lighting
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let finalColor = mix(texColor.rgb * ambient, texColor.rgb, mask);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
