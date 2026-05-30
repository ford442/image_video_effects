// ═══════════════════════════════════════════════════════════════════
//  Scanline Wave
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-persistence, chromatic-CRT, upgraded-rgba
//  Complexity: High
//  Chunks From: scanline-wave, bass_env, temporal-feedback
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
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let waveAmount = u.zoom_params.x * bass_env(bass, mids);
    let lineCount = mix(50.0, 300.0, u.zoom_params.y);
    let persistence = u.zoom_params.z;
    let rollSpeed = u.zoom_params.w;

    let lineIdx = floor(uv.y * lineCount);
    let lineCenter = (lineIdx + 0.5) / lineCount;
    let linePhase = lineCenter * 6.28318 + time * rollSpeed * 2.0;

    // Scanline offset with bass-driven amplitude
    let offset = sin(linePhase) * waveAmount * 0.02 * (1.0 + bass * 0.5);
    let waveUV = clamp(uv + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let base = textureSampleLevel(readTexture, u_sampler, waveUV, 0.0);

    // Temporal persistence: previous scanline state bleeds forward
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let decay = persistence * 0.85 + 0.1;
    let trail = mix(history * decay, base, 0.15 + isMouseDown * 0.2);

    // Chromatic CRT aberration per scanline
    let chromaShift = waveAmount * 0.005 * (1.0 + treble);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(waveUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(waveUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let crtColor = vec4<f32>(r, base.g, b, base.a);

    // Scanline intensity modulation
    let scanline = sin(uv.y * lineCount * 3.14159) * 0.5 + 0.5;
    let scanlineDark = mix(1.0, 0.7, scanline * waveAmount);

    // Audio roll: bass shifts entire field vertically
    let rollOffset = fract(uv.y + bass * 0.05) - uv.y;
    let rolledUV = clamp(uv + vec2<f32>(0.0, rollOffset), vec2<f32>(0.0), vec2<f32>(1.0));
    let rolled = textureSampleLevel(readTexture, u_sampler, rolledUV, 0.0);
    let mixed = mix(crtColor, rolled, bass * 0.3);

    let finalRGB = mixed.rgb * scanlineDark;
    let alpha = clamp(mixed.a + waveAmount * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
