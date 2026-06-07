// ═══════════════════════════════════════════════════════════════════
//  Pixel Focus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, filter, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
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

    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 0.001);
    var mouse = u.zoom_config.yz;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let mosaicSize = clamp(u.zoom_params.x, 0.0, 1.0);
    let focusRadius = max(u.zoom_params.y, 0.001);
    let hardness = clamp(u.zoom_params.z, 0.0, 1.0);
    let chromatic = clamp(u.zoom_params.w + treble * 0.1, 0.0, 1.0);

    // Calculate distance to mouse
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    // Mixing factor: 0.0 = Pixelated, 1.0 = Clear
    let focus = clamp(
        1.0 - smoothstep(focusRadius, focusRadius + (1.0 - hardness) * 0.2, dist),
        0.0, 1.0
    );

    // Pixelation Logic
    var density = (50.0 + (1.0 - mosaicSize) * 450.0) * (1.0 + bass * 0.1 + mids * 0.05);
    density = max(density, 1.0);
    let pixelUV = floor(uv * density) / density;

    // Sample Clear
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Sample Pixelated — branchless chromatic aberration
    let useChromatic = step(0.05, chromatic);
    let offset = chromatic * 0.01;
    let plainSample = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0);
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(pixelUV + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(pixelUV - vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let colPixel = vec3<f32>(
        mix(plainSample.r, rSample.r, useChromatic),
        plainSample.g,
        mix(plainSample.b, bSample.b, useChromatic)
    );

    let finalRGB = mix(colPixel, colClear, focus);

    // Alpha: focus region = opaque, pixelated zone weighted by luma
    let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(focus * 0.6 + luma * 0.3 + 0.1, 0.0, 1.0);
    let finalColor = vec4<f32>(finalRGB, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
