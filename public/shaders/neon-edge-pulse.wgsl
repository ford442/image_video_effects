// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Edge Pulse - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha + Luminance Key
//  Features: advanced-alpha, pulsing-edges, neon-glow
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Combined alpha
fn calculateEdgePulseAlpha(
    color: vec3<f32>,
    uv: vec2<f32>,
    pixelSize: vec2<f32>,
    pulseIntensity: f32,
    params: vec4<f32>
) -> f32 {
    let edgeAlpha = edgePreserveAlpha(uv, pixelSize, params.x);
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z);
    return clamp(edgeAlpha * lumaAlpha * pulseIntensity, 0.0, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let pulseSpeed = u.zoom_params.y * 5.0;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = u.zoom_params.w * 0.2;
    
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * audioReactivity);
    
    // Edge detection
    let stepX = pixelSize.x;
    let stepY = pixelSize.y;
    
    let t_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let m_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let m_c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let m_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;
    let b_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    
    fn luma(c: vec3<f32>) -> f32 {
        return dot(c, vec3<f32>(0.299, 0.587, 0.114));
    }
    
    let gx = -luma(m_l) + luma(m_r);
    let gy = -luma(t_c) + luma(b_c);
    let edgeStrength = sqrt(gx * gx + gy * gy);
    
    // Pulsing neon color
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(time * 3.0 * audioReactivity),
        0.5 + 0.5 * sin(time * 3.0 * audioReactivity + 2.09),
        0.5 + 0.5 * sin(time * 3.0 * audioReactivity + 4.18)
    );
    
    let emission = neonColor * edgeStrength * (0.5 + pulse) * 3.0;
    
    let alpha = calculateEdgePulseAlpha(emission, uv, pixelSize, 0.5 + pulse, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
