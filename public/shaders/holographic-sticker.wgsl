// ═══════════════════════════════════════════════════════════════════
//  Holographic Sticker
//  Category: visual-effects
//  Features: advanced-alpha, holographic, sticker-effect, mouse-driven, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
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
  zoom_params: vec4<f32>,  // x=HolographicIntensity, y=ColorShift, z=DepthWeight, w=StickerShape
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let holographicIntensity = clamp(u.zoom_params.x * (1.0 + bass * 0.3), 0.0, 1.0);
    let colorShift = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let stickerShape = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Sticker centered on mouse — drag the sticker around
    let mouse = u.zoom_config.yz;
    let toCenter = uv - mouse;

    // View-angle iridescence — rainbow phase shifts with depth + radius
    let angle = atan2(toCenter.y, toCenter.x);
    let phase = angle * 3.0 + colorShift * TAU + time * 0.5 + depth * PI;
    let rainbow = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    // Plasma palette overlay (multi-color holographic foil)
    let palIdx = u32(clamp((angle / TAU + 0.5 + time * 0.05) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    let foil = mix(rainbow, rainbow * (0.6 + palette * 0.7), 0.4);

    // Sticker edge shape (Gaussian — softer than smoothstep)
    let distFromCenter = length(toCenter);
    let r = stickerShape;
    let edgeGlow = exp(-pow(distFromCenter / max(r, 1e-3), 8.0));   // tightening sticker boundary

    let holographicColor = mix(baseSample.rgb, foil, holographicIntensity * edgeGlow);
    
    let depthAlpha = depthLayeredAlpha(holographicColor, uv, depthWeight);
    let lumaAlpha = luminanceKeyAlpha(holographicColor, 0.1, 0.05);
    let alpha = clamp(depthAlpha * lumaAlpha * edgeGlow, 0.0, 1.0);
    let finalAlpha = mix(baseSample.a, alpha, holographicIntensity * 0.7);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(holographicColor, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(holographicColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
