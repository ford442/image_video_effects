// ═══════════════════════════════════════════════════════════════════════════════
//  pp-bloom.wgsl - High Quality Bloom Post-Process
//  
//  Usage: Apply in Slot 1 or 2 after a base effect
//  Input: readTexture (previous slot output)
//  Output: writeTexture (bloom added to input)
//
//  Techniques:
//    - Multi-tap Gaussian blur approximation
//    - HDR threshold extraction
//    - Anamorphic bloom (optional via uniforms)
//    - Quality levels (4-16 taps based on performance)
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

// Quality settings (tap counts)
const QUALITY_LOW: i32 = 4;
const QUALITY_MED: i32 = 8;
const QUALITY_HIGH: i32 = 16;

// Gaussian weights for different tap counts
fn getWeights(taps: i32) -> array<f32, 16> {
    // Pre-computed normalized Gaussian weights
    if (taps == 4) {
        return array<f32, 16>(0.383f, 0.242f, 0.061f, 0.006f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f);
    }
    if (taps == 8) {
        return array<f32, 16>(0.199f, 0.176f, 0.121f, 0.065f, 0.028f, 0.009f, 0.002f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f);
    }
    // High quality - 16 taps
    return array<f32, 16>(0.088f, 0.085f, 0.079f, 0.070f, 0.059f, 0.047f, 0.035f, 0.024f, 0.015f, 0.008f, 0.004f, 0.002f, 0.001f, 0.0f, 0.0f, 0.0f);
}

fn getOffsets(taps: i32, radius: f32, invRes: vec2<f32>) -> array<vec2<f32>, 16> {
    var offsets: array<vec2<f32>, 16>;
    for (var i: i32 = 0; i < taps; i = i + 1) {
        let dist = f32(i + 1) / f32(taps);
        // Anamorphic stretch in Y based on param2
        let anamorphic = 1.0 + u.zoom_params.y * 2.0; // 1.0 - 3.0 stretch
        offsets[i] = vec2<f32>(
            invRes.x * dist * radius,
            invRes.y * dist * radius * anamorphic
        );
    }
    return offsets;
}

fn extractBright(color: vec3<f32>, threshold: f32) -> vec3<f32> {
    let luminance = dot(color, vec3<f32>(0.299f, 0.587f, 0.114f));
    let contribution = max(luminance - threshold, 0.0f);
    // Soft knee
    let knee = threshold * 0.5f;
    let soft = max(luminance - threshold + knee, 0.0f);
    let softContribution = min(soft, knee) * (soft / max(knee, 0.001f));
    
    return color * (contribution + softContribution) / max(luminance, 0.001f);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let invRes = 1.0f / resolution;
    
    // Parameters
    // param1: Bloom intensity (0-1)
    // param2: Anamorphic stretch (0-1)
    // param3: Threshold (0-1, where bloom starts)
    // param4: Quality level (0=low, 0.33=med, 0.66=high)
    let intensity = u.zoom_params.x;
    let threshold = u.zoom_params.z;
    let qualityParam = u.zoom_params.w;
    
    var taps: i32;
    if (qualityParam < 0.33f) {
        taps = QUALITY_LOW;
    } else if (qualityParam < 0.66f) {
        taps = QUALITY_MED;
    } else {
        taps = QUALITY_HIGH;
    }
    
    // Sample original color
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0f);
    
    // Extract bright areas
    let bright = extractBright(original.rgb, threshold);
    
    // Multi-tap blur in both directions
    let weights = getWeights(taps);
    let radius = 4.0f + intensity * 8.0f; // 4-12 pixel radius
    let offsets = getOffsets(taps, radius, invRes);
    
    var blurred = bright * weights[0];
    
    // Horizontal + vertical blur (simplified)
    for (var i: i32 = 0; i < taps; i = i + 1) {
        let offset = offsets[i];
        
        // Horizontal samples
        let h1 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, 0.0f), 0.0f).rgb,
            threshold
        );
        let h2 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(offset.x, 0.0f), 0.0f).rgb,
            threshold
        );
        
        // Vertical samples
        let v1 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0f, offset.y), 0.0f).rgb,
            threshold
        );
        let v2 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0f, offset.y), 0.0f).rgb,
            threshold
        );
        
        // Diagonal samples for better quality
        let d1 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0f).rgb,
            threshold
        );
        let d2 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0f).rgb,
            threshold
        );
        let d3 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, -offset.y), 0.0f).rgb,
            threshold
        );
        let d4 = extractBright(
            textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset.x, offset.y), 0.0f).rgb,
            threshold
        );
        
        let avg = (h1 + h2 + v1 + v2 + d1 + d2 + d3 + d4) * 0.125f;
        blurred += avg * weights[i];
    }
    
    // Normalize
    var totalWeight = weights[0];
    for (var i: i32 = 1; i < taps; i = i + 1) {
        totalWeight += weights[i] * 8.0f; // 8 samples per iteration
    }
    blurred /= totalWeight;
    
    // Additive bloom with intensity
    let bloomContribution = blurred * intensity * 2.0f;
    
    // HDR addition (allow values > 1.0)
    var finalColor = original.rgb + bloomContribution;
    
    // Optional: lens dirt effect (simulated vignette on bloom)
    let lensDirt = 1.0f - length(uv - 0.5f) * 0.5f;
    finalColor += blurred * intensity * 0.3f * lensDirt;
    
    // Store bloom in dataTextureA for potential multi-pass
    textureStore(dataTextureA, coord, vec4<f32>(blurred, 1.0f));
    
    // Write final
    textureStore(writeTexture, coord, vec4<f32>(finalColor, original.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r, 0.0f, 0.0f, 1.0f));
}
