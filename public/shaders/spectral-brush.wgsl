// ═══════════════════════════════════════════════════════════════════
//  Spectral Brush
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Chunks From: spectral-brush
//  Created: 2026-05-10
//  By: Phase A Shader Upgrade Agent
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);

    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;

    // Params
    let brushSize = u.zoom_params.x * 0.2;
    let spectralShift = u.zoom_params.y * 6.28 + bass * 1.0;
    // Persistence: 1.0 = slow decay, 0.0 = fast decay
    let decay = 0.005 + (1.0 - u.zoom_params.z) * 0.1;
    let edgeHardness = u.zoom_params.w;

    // Mouse interaction
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Read history (mask)
    let prevMask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Update mask
    var mask = max(0.0, prevMask - decay);

    // Invert smoothstep logic
    let brushVal = 1.0 - smoothstep(brushSize * (1.0 - edgeHardness * 0.9), brushSize, dist);

    mask = max(mask, brushVal);

    // Write mask (alpha follows mask intensity)
    textureStore(dataTextureA, coord, vec4<f32>(mask, 0.0, 0.0, mask));

    // Sample original image
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Calculate spectral version
    // Invert + Hue Shift + Boost Saturation
    let inverted = 1.0 - original.rgb;
    let spectral = hueShift(inverted, spectralShift + time);

    // Mix
    let finalColor = mix(original.rgb, spectral, mask);

    // Meaningful alpha based on luminance and effect intensity
    let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(original.a, clamp(luminance + 0.3, 0.0, 1.0), mask);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
}
