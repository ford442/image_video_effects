// ═══════════════════════════════════════════════════════════════════
//  alucinate - Psychedelic interactive warping and color shifting
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, chromatic-aberration, warping
//  Upgraded: 2026-03-22
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
  config: vec4<f32>,      // x=time, y=ripple_count, z=width, w=height
  zoom_config: vec4<f32>, // x=zoom, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // distortion params
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.5;

    let mouse_uv = u.zoom_config.yz;
    let mouse_active = u.zoom_config.w > 0.0;
    let dist_to_mouse = distance(uv, mouse_uv);
    let mouse_effect = smoothstep(0.3, 0.0, dist_to_mouse) * f32(mouse_active);

    let warp_freq = mix(4.0, 10.0, mouse_effect);
    let warp_amp = mix(0.02, 0.1, mouse_effect);
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let radius = distance(uv, vec2(0.5));
    let warp_offset_x = sin(uv.y * warp_freq - time) * cos(radius * 10.0 + time) * warp_amp;
    let warp_offset_y = cos(uv.x * warp_freq + time) * sin(radius * 10.0 - time) * warp_amp;
    let warped_uv = uv + vec2(warp_offset_x, warp_offset_y);

    let shift_amount = mix(0.005, 0.02, mouse_effect) * sin(time * 2.0);
    let r = textureSampleLevel(readTexture, u_sampler, warped_uv + vec2(shift_amount, shift_amount), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, warped_uv - vec2(shift_amount, shift_amount), 0.0).b;
    
    let color = vec3<f32>(r, g, b);
    
    // Calculate alpha based on color luminance and warp intensity
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let warpAlpha = mix(0.8, 1.0, mouse_effect + warp_amp * 10.0);
    let alpha = mix(warpAlpha * 0.85, warpAlpha, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);
    
    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
