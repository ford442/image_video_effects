// ═══════════════════════════════════════════════════════════════════════════════
//  Lens Flare Brush - Advanced Alpha with Luminance Key
//  Category: glow/light-effects
//  Alpha Mode: Luminance Key Alpha + Effect Intensity
//  Features: advanced-alpha, lens-flare, mouse-interactive
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

// Mode 5: Effect Intensity Alpha for brush size
fn effectIntensityAlpha(intensity: f32, falloff: f32) -> f32 {
    return mix(0.3, 1.0, intensity * falloff);
}

// Combined alpha for lens flare
fn calculateFlareAlpha(
    color: vec3<f32>,
    intensity: f32,
    falloff: f32,
    params: vec4<f32>
) -> f32 {
    // params.x = brush intensity
    // params.y = luminance threshold
    // params.z = softness
    
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z);
    let effectAlpha = effectIntensityAlpha(intensity, falloff);
    
    return clamp(lumaAlpha * effectAlpha, 0.0, 1.0);
}

// Lens flare element
fn flareElement(uv: vec2<f32>, pos: vec2<f32>, size: f32) -> f32 {
    let d = length(uv - pos);
    return exp(-d * d / (size * size));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let brushIntensity = u.zoom_params.x;
    let flareSize = u.zoom_params.y * 0.5 + 0.05;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = u.zoom_params.w * 0.2;
    
    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);
    
    // Multiple flare elements
    var flareAccum = vec3<f32>(0.0);
    
    // Main flare at mouse
    let mainFlare = flareElement(uv, mousePos, flareSize);
    
    // Ghost flares
    for (var i: i32 = 0; i < 5; i++) {
        let fi = f32(i);
        let ghostPos = mousePos + vec2<f32>(
            sin(fi * 1.3 + time * 0.2) * 0.2,
            cos(fi * 0.9) * 0.15
        );
        let ghostSize = flareSize * (0.5 - fi * 0.08);
        let ghost = flareElement(uv, ghostPos, ghostSize);
        
        let ghostColor = vec3<f32>(
            0.5 + 0.5 * sin(fi * 1.2),
            0.5 + 0.5 * sin(fi * 1.2 + 2.0),
            0.5 + 0.5 * sin(fi * 1.2 + 4.0)
        );
        
        flareAccum += ghostColor * ghost * brushIntensity;
    }
    
    // Main flare color
    let mainColor = vec3<f32>(1.0, 0.9, 0.7) * mainFlare * brushIntensity * 2.0;
    let finalColor = flareAccum + mainColor;
    
    // Falloff from brush center
    let brushFalloff = 1.0 - smoothstep(0.0, flareSize * 3.0, mouseDist);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateFlareAlpha(finalColor, brushIntensity, brushFalloff, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
