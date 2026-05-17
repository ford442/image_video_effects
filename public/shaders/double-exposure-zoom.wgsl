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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════
//  Double Exposure Zoom
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-17
//  By: The Interactivist
// ═══════════════════════════════════════════════════════════════════
// Blends the image with a zoomed and rotated copy of itself,
// pivoting around a spring-damped mouse cursor. Uses attack/release
// audio envelope for smoothed bass reactivity and temporal feedback
// trails that age through alpha.
//
// Param 1: Rotation (0..1 maps to -PI..PI)
// Param 2: Zoom Level (0..1 maps to 0.25x .. 4.0x)
// Param 3: Edge Fade (0..1)
// Param 4: Audio Reactivity (0..1)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let mouse = u.zoom_config.yz;

    // Read persistent state from dataTextureC pixel (0,0)
    let prevState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);

    // Attack/release audio envelope
    let bassRaw = plasmaBuffer[0].x;
    let k = select(0.15, 0.8, bassRaw > prevState.r);
    let bassSmooth = mix(prevState.r, bassRaw, k);

    // Spring-damper mouse follow
    let smoothMouse = mix(prevState.gb, mouse, vec2<f32>(0.08));

    let rot = (u.zoom_params.x - 0.5) * 6.28318;
    let zoomRaw = u.zoom_params.y;
    let edgeFade = u.zoom_params.z;
    let audioReact = u.zoom_params.w;

    // Mouse distance from center modulates zoom intensity
    let mouseDist = length(mouse - 0.5);
    let zoomMod = zoomRaw + mouseDist * 0.3;

    // Audio-reactive zoom with smoothed envelope
    let zoom = clamp(pow(2.0, (zoomMod - 0.5) * 4.0 + bassSmooth * audioReact * 2.0), 0.01, 100.0);

    let col1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var uv2 = uv - smoothMouse;
    uv2.x *= aspect;
    let c = cos(rot);
    let s = sin(rot);
    uv2 = vec2<f32>(uv2.x * c - uv2.y * s, uv2.x * s + uv2.y * c);
    uv2.x /= aspect;
    uv2 /= zoom;
    uv2 += smoothMouse;

    let col2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

    // Edge fade for transformed layer
    let edgeDist = min(min(uv2.x, 1.0 - uv2.x), min(uv2.y, 1.0 - uv2.y));
    let edgeMask = smoothstep(0.0, 0.05 + edgeFade * 0.45, edgeDist);
    let col2Faded = vec4<f32>(col2.rgb, col2.a * edgeMask);

    // RGBA-aware screen blend
    let blendedRGB = 1.0 - (1.0 - col1.rgb) * (1.0 - col2Faded.rgb);
    let blendAlpha = 1.0 - (1.0 - col1.a) * (1.0 - col2Faded.a);

    // Temporal feedback trails
    let prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let trailAmt = 0.15 + bassSmooth * audioReact * 0.25;
    let finalRGB = mix(blendedRGB, prevFrame.rgb, trailAmt);
    let finalAlpha = mix(blendAlpha, prevFrame.a * 0.96, trailAmt);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));

    // Persist state to dataTextureA: scalar state at (0,0), image elsewhere
    if (global_id.x == 0u && global_id.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(bassSmooth, smoothMouse.x, smoothMouse.y, 0.0));
    } else {
        textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));
    }

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
