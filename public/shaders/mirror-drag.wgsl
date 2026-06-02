// ═══════════════════════════════════════════════════════════════════
//  Mirror Drag
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-trail, chromatic-ghost, audio-shatter, upgraded-rgba
//  Complexity: High
//  Chunks From: mirror-drag, bass_env, temporal-feedback
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let drag = u.zoom_params.x * bass_env(bass, mids);
    let mirror = u.zoom_params.y;
    let trailDecay = u.zoom_params.z;
    let shatterAmount = u.zoom_params.w;

    let mirroredUV = vec2<f32>(
        mix(uv.x, 1.0 - uv.x, mirror),
        uv.y
    );

    let mouseDiff = uv - mouse;
    let dragDistance = length(mouseDiff) * drag;
    let dragDir = select(vec2<f32>(0.0), mouseDiff / max(length(mouseDiff), 0.0001), length(mouseDiff) > 0.0001);

    let offset = dragDir * dragDistance * 0.1;
    let trailUV = clamp(mirroredUV - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let current = textureSampleLevel(readTexture, u_sampler, trailUV, 0.0);

    // Temporal trail echo
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, mirroredUV, 0.0);
    let decay = trailDecay * 0.9 + 0.05;
    let trail = mix(history * decay, current, isMouseDown * 0.1 + 0.05);

    // Chromatic ghost: R and B trail behind at different rates
    let rOffset = dragDir * dragDistance * 0.12;
    let bOffset = dragDir * dragDistance * 0.08;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(trailUV - rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(trailUV - bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let g = trail.g;

    let chromaColor = vec4<f32>(r, g, b, trail.a);

    // Audio shatter: treble breaks the mirror into angular shards
    let shardAngle = floor(atan2(mouseDiff.y, mouseDiff.x) * (4.0 + treble * 10.0)) / (4.0 + treble * 10.0);
    let shardDist = length(mouseDiff);
    let shardEdge = fract(shardDist * (10.0 + shatterAmount * 50.0 + bass * 20.0));
    let shatterGlow = smoothstep(0.9, 1.0, shardEdge) * treble * shatterAmount;

    let finalRGB = chromaColor.rgb + vec3<f32>(shatterGlow, shatterGlow * 0.5, shatterGlow * 0.3);
    let alpha = clamp(chromaColor.a + shatterGlow + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
