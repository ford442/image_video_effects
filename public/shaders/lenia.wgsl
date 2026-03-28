// ═══════════════════════════════════════════════════════════════════════════════
//  Lenia - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Luminance Key
//  Features: advanced-alpha, cellular-automata, continuous-life
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

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.05) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
}

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Kernel growth function (Bell curve)
fn growthKernel(x: f32) -> f32 {
    return exp(-pow((x - 0.5) / 0.15, 2.0) * 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    
    // Parameters
    let radius = u.zoom_params.x * 10.0 + 3.0;
    let growthRate = u.zoom_params.y * 0.1;
    let accumulationRate = u.zoom_params.z;
    let threshold = u.zoom_params.w;
    
    // Sample neighborhood
    let pixelSize = 1.0 / u.config.zw;
    var neighborSum = 0.0;
    var weightSum = 0.0;
    
    for (var y: i32 = -2; y <= 2; y++) {
        for (var x: i32 = -2; x <= 2; x++) {
            if (x == 0 && y == 0) { continue; }
            let offset = vec2<f32>(f32(x), f32(y)) * pixelSize;
            let dist = length(vec2<f32>(f32(x), f32(y)));
            let weight = 1.0 / (1.0 + dist * dist);
            let neighbor = textureSampleLevel(dataTextureC, u_sampler, uv + offset, 0.0);
            neighborSum += neighbor.r * weight;
            weightSum += weight;
        }
    }
    
    let avgNeighbor = neighborSum / weightSum;
    let center = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
    
    // Lenia update rule
    let growth = growthKernel(avgNeighbor) * 2.0 - 1.0;
    let newValue = center + growthRate * growth;
    
    // Clamp and threshold
    let clamped = clamp(newValue, 0.0, 1.0);
    let finalValue = smoothstep(threshold * 0.5, threshold, clamped);
    
    // Color based on value
    let color = vec3<f32>(
        finalValue * 0.8,
        finalValue * (0.5 + 0.5 * sin(finalValue * 3.14)),
        finalValue * 0.9
    );
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let newAlpha = luminanceKeyAlpha(color, 0.1, 0.05) * finalValue;
    
    let accumulated = accumulativeAlpha(
        color,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    textureStore(dataTextureA, coord, vec4<f32>(finalValue, finalValue, finalValue, accumulated.a));
    textureStore(writeTexture, global_id.xy, accumulated);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
