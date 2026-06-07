// ═══════════════════════════════════════════════════════════════════
//  Chronos Brush
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal-painting, depth-aware-opacity, chromatic-brush, upgraded-rgba
//  Complexity: High
//  Chunks From: chronos-brush, bass_env, temporal-feedback
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let clickCount = u.config.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOpacity = mix(0.7, 1.0, depth);

    let brushSize = u.zoom_params.x * bass_env(bass, mids);
    let colorShiftSpeed = u.zoom_params.y;
    let fadeAmount = u.zoom_params.z;
    let opacity = u.zoom_params.w * depthOpacity;

    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);

    let radius = 0.02 + brushSize * 0.15;
    let brush = 1.0 - smoothstep(radius * 0.8, radius, dist);

    let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let liveColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Chromatic brush: cycle HSL hue per click via time
    let hue = fract(sin(clickCount * 0.5 + time * colorShiftSpeed * 0.5 + bass * 0.1) * 43758.5453);
    let sat = 0.8 + mids * 0.2;
    let val = 0.9 + treble * 0.1;

    // HSV to RGB inline
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let brushTint = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let tintColor = vec3<f32>(sat * val) * mix(vec3<f32>(val), brushTint, sat);

    let tintedLive = vec4<f32>(liveColor.rgb * tintColor, liveColor.a);

    let decay = 1.0 - fadeAmount * 0.05 * (1.0 - bass * 0.03);
    var newHistoryColor = historyColor * decay;

    let mixFactor = brush * opacity * (1.0 + bass * 0.3);
    newHistoryColor = mix(newHistoryColor, tintedLive, mixFactor);

    let alpha = clamp(newHistoryColor.a + brush * 0.15 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(newHistoryColor.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
