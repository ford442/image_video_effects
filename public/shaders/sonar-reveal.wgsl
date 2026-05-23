// ═══════════════════════════════════════════════════════════════════
//  Sonar Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, audio-driven, upgraded-rgba
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

    let size = u.zoom_params.x * 0.4 + 0.05;
    let intensity = u.zoom_params.y * 2.0;
    let softness = u.zoom_params.z * 0.2;
    let colorMode = u.zoom_params.w;

    let audioPulse = 1.0 + bass * 0.5 + mids * 0.2 + treble * 0.1;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let gray = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let dimColor = vec3<f32>(gray * 0.3);

    let reveal = 1.0 - smoothstep(size, size + softness + 0.01, dist);

    let ringWidth = 0.02 + softness * 0.1;
    let ring = smoothstep(ringWidth, 0.0, abs(dist - size));

    let ringColorVec = mix(vec3<f32>(0.2, 1.0, 0.5), vec3<f32>(1.0, 0.3, 0.1), step(0.5, colorMode));

    let finalRGB = mix(dimColor, baseColor.rgb, reveal) + ringColorVec * ring * intensity * audioPulse;
    let finalAlpha = baseColor.a;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let finalColor = vec4<f32>(finalRGB, finalAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
