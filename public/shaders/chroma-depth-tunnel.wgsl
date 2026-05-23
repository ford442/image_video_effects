// ═══════════════════════════════════════════════════════════════════
//  Chroma Depth Tunnel
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Shader Upgrade Swarm — Phase A
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
  zoom_params: vec4<f32>,  // x=Speed, y=Density, z=ChromaSep, w=CenterFade
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    var mousePos = u.zoom_config.yz;
    if (mousePos.x < 0.0) { mousePos = vec2<f32>(0.5, 0.5); }

    let speed = (u.zoom_params.x - 0.5) * 2.0;
    let density = u.zoom_params.y * 5.0 + 1.0;
    let chroma = u.zoom_params.z * 0.05 * (1.0 + bass * 0.3);
    let centerFade = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    var p = uv - mousePos;
    let p_aspect = vec2<f32>(p.x * aspect, p.y);

    let radius = length(p_aspect);
    let angle = atan2(p.y, p.x);

    let u_coord = angle / 3.14159265;
    let v_coord = 1.0 / (radius + 0.001);
    let tunnelUV = vec2<f32>(u_coord, v_coord * density + time * speed);

    let r_uv = tunnelUV + vec2<f32>(chroma, 0.0);
    let g_uv = tunnelUV;
    let b_uv = tunnelUV - vec2<f32>(chroma, 0.0);

    let r_col = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g_col = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
    let b_col = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    var color = vec3<f32>(r_col, g_col, b_col);

    var fog = 1.0;
    if (centerFade > 0.0) {
        fog = smoothstep(0.0, centerFade, radius);
        color = color * fog;
    }

    // Alpha encodes tunnel depth: inner rings (high v_coord) are more opaque
    let tunnel_depth = clamp(v_coord * 0.02, 0.0, 1.0);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(fog * (0.4 + tunnel_depth * 0.4 + luma * 0.2), 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(color, alpha));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(d, 0.0, 0.0, 0.0));
}
