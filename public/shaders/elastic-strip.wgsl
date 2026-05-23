// ═══════════════════════════════════════════════════════════════════
//  Elastic Strip
//  Category: image
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
    let mouse = u.zoom_config.yz;

    let stripCount = mix(10.0, 100.0, u.zoom_params.x) * (1.0 + bass * 0.2);
    let strength = (u.zoom_params.y - 0.5) * 2.0;
    let falloff = u.zoom_params.z;
    let direction = u.zoom_params.w;

    let isHoriz = step(0.5, direction);

    let stripCoord = mix(uv.x, uv.y, isHoriz);
    let mouseStrip = mix(mouse.x, mouse.y, isHoriz);
    let mouseDisplace = mix(mouse.y, mouse.x, isHoriz);

    let cell = floor(stripCoord * stripCount) / stripCount;
    let stripCenter = cell + (0.5 / stripCount);

    let dist = abs(stripCenter - mouseStrip);

    let influence = exp(-pow(dist / max(falloff * 0.5 + 0.01, 0.0001), 2.0));

    let shift = (mouseDisplace - 0.5) * strength * influence;

    let sourceUV = vec2<f32>(
        uv.x - select(0.0, shift, isHoriz > 0.5),
        uv.y - select(shift, 0.0, isHoriz > 0.5)
    );
    let clampedUV = clamp(sourceUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let color = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), color);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
