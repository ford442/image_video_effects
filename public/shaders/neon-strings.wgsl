// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Strings - Advanced Alpha with Luminance Key
//  Category: glow/light-effects
//  Alpha Mode: Luminance Key Alpha + Effect Intensity
//  Features: advanced-alpha, strings, neon, vibration
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

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    let stringCount = u.zoom_params.x * 20.0 + 5.0;
    let vibration = u.zoom_params.y * 0.02;
    let intensity = u.zoom_params.z * 3.0;
    let lumaThreshold = u.zoom_params.w * 0.3;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // String pattern
    let stringY = fract(uv.y * stringCount);
    let stringIndex = floor(uv.y * stringCount);
    
    // Vibration
    let vibrate = sin(time * 10.0 * audioReactivity + stringIndex) * vibration;
    let stringDist = abs(stringY - 0.5 + vibrate);
    let stringGlow = smoothstep(0.02, 0.0, stringDist);
    
    // Neon color per string
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(stringIndex * 0.5 + time),
        0.5 + 0.5 * sin(stringIndex * 0.5 + time + 2.09),
        0.5 + 0.5 * sin(stringIndex * 0.5 + time + 4.18)
    );
    
    let emission = neonColor * stringGlow * intensity;
    let alpha = luminanceKeyAlpha(emission, lumaThreshold, 0.05) * stringGlow;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
