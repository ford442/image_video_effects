// ═══════════════════════════════════════════════════════════════════
//  Luma Echo Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2024-01-01
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let audioMod = 1.0 + bass * 0.3;
    let strength = u.zoom_params.x * 2.0 * audioMod;
    let decay = 0.9 + u.zoom_params.y * 0.09;
    let radius = 0.1 + u.zoom_params.z * 0.4;
    let lumaWeight = u.zoom_params.w;

    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let lenD = length(dVec);
    let dir = select(vec2<f32>(0.0, 0.0), dVec / max(lenD, 0.0001), lenD > 0.0001);
    let influence = smoothstep(radius, 0.0, dist);
    let weight = mix(1.0, luma, lumaWeight);
    let mouseActive = select(0.0, 1.0, mousePos.x >= 0.0);
    let warp = dir * influence * strength * weight * 0.1 * mouseActive;

    let distortedUV = clamp(uv - warp, vec2<f32>(0.0), vec2<f32>(1.0));
    let warpedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let mixed = mix(warpedColor, history, decay);
    let outputColor = mix(mixed, warpedColor, isMouseDown * 0.5);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outputColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
