// ═══════════════════════════════════════════════════════════════════
//  Pixel Focus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, filter
//  Complexity: Medium
//  Chunks From: original pixel-focus
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
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
  zoom_params: vec4<f32>,  // x=MosaicSize, y=FocusRadius, z=Hardness, w=Chromatic
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 0.001);
    var mouse = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;

    // Params
    let mosaicSize = clamp(u.zoom_params.x, 0.0, 1.0);
    let focusRadius = max(u.zoom_params.y, 0.001);
    let hardness = clamp(u.zoom_params.z, 0.0, 1.0);
    let chromatic = clamp(u.zoom_params.w, 0.0, 1.0);

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
    var density = (50.0 + (1.0 - mosaicSize) * 450.0) * (1.0 + bass * 0.1);
    density = max(density, 1.0);
    let pixelUV = floor(uv * density) / density;

    // Sample Clear
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Sample Pixelated
    // Add optional chromatic aberration to the pixelated part
    var colPixel: vec3<f32>;
    if (chromatic > 0.05) {
        let offset = chromatic * 0.01;
        let r = textureSampleLevel(readTexture, u_sampler, pixelUV + vec2<f32>(offset, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, pixelUV - vec2<f32>(offset, 0.0), 0.0).b;
        colPixel = vec3<f32>(r, g, b);
    } else {
        colPixel = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0).rgb;
    }

    let finalColor = mix(colPixel, colClear, focus);

    // Alpha: focus region = opaque, pixelated zone weighted by luma
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(focus * 0.6 + luma * 0.3 + 0.1, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
