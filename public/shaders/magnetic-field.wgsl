// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field
//  Category: distortion
//  Features: animated, physics, mouse-driven, audio-reactive, audio-driven, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
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

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let strength = u.zoom_params.x * (1.0 + bass * 0.5);
    let radius = u.zoom_params.y;
    let density = u.zoom_params.z;
    let mode = u.zoom_params.w;

    let aspect = u.config.z / u.config.w;
    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let diffLen = length(diff);
    let dir = select(vec2<f32>(0.0), diff / max(diffLen, 0.0001), diffLen > 0.0001);

    let inRadius = dist < radius;
    let angle = atan2(diff.y, diff.x);
    let field = sin(angle * 20.0 + dist * (density * 100.0) - time * 2.0);
    let falloff = smoothstep(radius, 0.0, dist);
    let effect = falloff * strength * 0.2;
    let wiggle = dir * field * 0.02 * strength;
    let repelDir = select(-1.0, 1.0, mode > 0.5);
    let offset = dir * effect * repelDir + wiggle;
    let finalOffset = select(vec2<f32>(0.0), offset, inRadius);

    let finalUV = clamp(uv - finalOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let distortionMag = length(finalOffset) * 10.0;
    let fieldGlow = smoothstep(0.0, 0.5, distortionMag) * (0.5 + mids * 0.3);
    let finalAlpha = clamp(color.a + fieldGlow + treble * 0.1, 0.0, 1.0);
    let finalColor = vec4<f32>(color.rgb, finalAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
