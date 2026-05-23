// ═══════════════════════════════════════════════════════════════════
//  Sonic Boom
//  Category: distortion
//  Features: multi-shock, persistent-tail, gaussian-ring, audio-reactive, branchless, hex-bokeh, early-exit, upgraded-rgba
//  Complexity: Medium
//  Created: 2025-12-31
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PHI: f32 = 1.61803398874989484820;

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>( 0.0,  0.0),
    vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
    vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let dim = vec2<i32>(i32(u.config.z), i32(u.config.w));
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / vec2<f32>(f32(dim.x), f32(dim.y));
    let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let radius   = u.zoom_params.x;
    let width    = u.zoom_params.y;
    let strength = u.zoom_params.z * (1.0 + bass * 0.5);
    let split    = u.zoom_params.w;

    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_pixel = (uv - mouse_pos) * aspect;
    let dist = length(to_pixel);
    let dir = to_pixel / max(dist, 1e-4);

    let prevTail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    let widthHalf = max(width * 0.5, 1e-4);
    let invWH = 1.0 / widthHalf;
    let d0 = (dist - radius) * invWH;
    let d1 = (dist - radius / PHI) * invWH;
    let d2 = (dist - radius / (PHI * PHI)) * invWH;
    let ring0 = exp(-d0 * d0 * 4.0);
    let ring1 = exp(-d1 * d1 * 6.0) * 0.55;
    let ring2 = exp(-d2 * d2 * 8.0) * 0.30;
    let ringSum = ring0 + ring1 + ring2;
    let ringFinal = max(ringSum, prevTail * 0.85);

    let texel = 1.0 / vec2<f32>(dim);
    var hTail: f32 = 0.0;
    for (var i: i32 = 0; i < 7; i = i + 1) {
        hTail = hTail + textureSampleLevel(dataTextureC, non_filtering_sampler, uv + HEX_TAPS[i] * texel * 2.0, 0.0).r;
    }
    let ringBlur = max(ringSum, (hTail / 7.0) * 0.85);

    let distortion = dir * ringBlur * strength * 0.1 * (1.0 + mids * 0.3);
    let doppler = (ring0 - ring2) * split * 8.0;
    let uv_r = clamp(uv - distortion * (1.0 + split * 10.0 + doppler), vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_g = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_b = clamp(uv - distortion * (1.0 - split * 10.0 - doppler), vec2<f32>(0.0), vec2<f32>(1.0));

    let c = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    let alpha = clamp(ringBlur * 0.7 + abs(doppler) * 0.5 + treble * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(r, c.g, b, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
