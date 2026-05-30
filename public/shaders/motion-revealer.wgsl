// ═══════════════════════════════════════════════════════════════════
//  Motion Revealer
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-painting, depth-aware-stroke, chromatic-mixing, upgraded-rgba
//  Complexity: High
//  Chunks From: motion-revealer, bass_env, temporal-feedback
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
    let mouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOpacity = mix(0.6, 1.0, depth);

    let brushSize = u.zoom_params.x * bass_env(bass, mids);
    let fadeSpeed = u.zoom_params.y;
    let softness = u.zoom_params.z;
    let opacity = u.zoom_params.w * depthOpacity;

    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);

    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);

    let radius = 0.01 + brushSize * 0.4;
    let edgeWidth = softness * radius;
    let brush = 1.0 - smoothstep(radius - max(edgeWidth, 0.001), radius, dist);

    let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let liveColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let decay = 1.0 - (fadeSpeed * 0.1) * (1.0 - bass * 0.05);
    var newHistoryColor = historyColor * decay;

    let mixFactor = brush * opacity * (1.0 + bass * 0.3);
    newHistoryColor = mix(newHistoryColor, liveColor, mixFactor);

    // Chromatic color mixing: bass shifts R, mids shift G, treble shifts B
    let chromaShift = vec3<f32>(
        sin(time * 2.0 + bass * 3.14) * 0.05,
        sin(time * 1.5 + mids * 3.14) * 0.05,
        sin(time * 2.5 + treble * 3.14) * 0.05
    );
    let chromaColor = vec4<f32>(
        clamp(newHistoryColor.r + chromaShift.r, 0.0, 1.0),
        clamp(newHistoryColor.g + chromaShift.g, 0.0, 1.0),
        clamp(newHistoryColor.b + chromaShift.b, 0.0, 1.0),
        newHistoryColor.a
    );

    let alpha = clamp(chromaColor.a + brush * 0.2 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(chromaColor.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
