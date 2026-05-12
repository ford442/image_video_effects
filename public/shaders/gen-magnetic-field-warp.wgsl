// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field Warp
//  Category: generative
//  Features: mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Shader Upgrade Agent
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.z, u.config.w);

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let time = u.config.x;

    // Audio reactivity via bass
    let bass = plasmaBuffer[0].x;
    let audio = u.config.y;

    // Mouse dipole
    let mouse = u.zoom_config.yz;
    let delta = uv - mouse;
    let dist = length(delta);
    let safe_dist = max(dist, 0.001);
    let warp_strength = u.zoom_params.x * 2.0 * (1.0 + bass);

    // Quadratic distortion based on mouse and audio
    let field_dir = select(vec2<f32>(0.0, 0.0), delta / safe_dist, dist > 0.001);
    let field = field_dir * (warp_strength / (safe_dist * safe_dist + 0.1)) * max(audio, 0.01);
    let warped_uv = uv + field * 0.05;

    // Clamp warped UVs to avoid out-of-bounds sampling
    let safe_uv = clamp(warped_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    // Fetch image
    let read_coords = vec2<i32>(safe_uv * vec2<f32>(res));
    let color = textureLoad(readTexture, read_coords, 0);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Spectral remapping
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let spectral_idx = u32(clamp(luma + audio * 0.5, 0.0, 1.0) * 255.0) % 256u;
    let plasma = plasmaBuffer[spectral_idx];

    let mix_factor = clamp(u.zoom_params.y, 0.0, 1.0);
    let mixed_color = mix(color, plasma, mix_factor);

    // Meaningful alpha based on effect intensity and luminance
    let effect_intensity = clamp(length(field) * 5.0, 0.0, 1.0);
    let target_alpha = clamp(0.6 + luma * 0.4 + bass * 0.2, 0.0, 1.0);
    let final_alpha = clamp(mix(color.a, target_alpha, effect_intensity * mix_factor), 0.0, 1.0);

    let final_color = vec4<f32>(mixed_color.rgb, final_alpha);

    textureStore(writeTexture, coords, final_color);
}
