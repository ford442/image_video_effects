// ═══════════════════════════════════════════════════════════════════
//  Luma Melt
//  Category: liquid-effects
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
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let meltSpeed = u.zoom_params.x * 0.05 * (1.0 + bass * 0.5);
    let persistence = u.zoom_params.y;
    let radius = max(u.zoom_params.z, 0.01);
    let heat = u.zoom_params.w * 0.1;

    let newColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(newColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let mouseFactor = smoothstep(radius, 0.0, dist);

    let totalFlow = meltSpeed * luma + (heat * mouseFactor);

    let sourceUV = vec2<f32>(uv.x, uv.y - totalFlow);
    let clampedUV = clamp(sourceUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let history = textureSampleLevel(dataTextureC, u_sampler, clampedUV, 0.0);

    let blended = mix(newColor, history, persistence);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), blended);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), blended);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
