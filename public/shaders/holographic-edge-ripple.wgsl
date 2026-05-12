// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Edge Ripple - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha + Depth-Layered
//  Features: advanced-alpha, holographic, ripple, edge
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=EdgeThreshold, y=RippleSpeed, z=RippleIntensity, w=HolographicShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 2: Edge-Preserve Alpha
fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let rippleSpeed = u.zoom_params.y * 5.0 * (1.0 + bass * 0.4);
    let rippleIntensity = u.zoom_params.z * (1.0 + bass * 0.3);
    let holographicShift = u.zoom_params.w;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Edge detection
    let l = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let edge = length(r - l);
    
    // Ripple on edges
    let ripple = sin(edge * 50.0 - time * rippleSpeed) * rippleIntensity;
    
    // Holographic color (plasma palette + sin gradient hybrid)
    let phase = time + ripple + holographicShift * TAU;
    let holographic = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));
    let palIdx = u32(clamp((edge * 5.0 + holographicShift) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    let foil = mix(holographic, holographic * (0.6 + palette * 0.7), 0.4);

    // Composite with background
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let emission = bg * (1.0 - edge * 0.6) + foil * edge * (1.0 + ripple);
    let alpha = edgePreserveAlpha(uv, pixelSize, edgeThreshold) * (0.5 + ripple * 0.5);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
