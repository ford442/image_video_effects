// ═══════════════════════════════════════════════════════════════════════════════
//  Video Echo Chamber - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Depth-Layered
//  Features: advanced-alpha, temporal-feedback, echo-chamber
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

// Mode 3: Accumulative Alpha (Feedback Systems)
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.5, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined alpha for echo chamber
fn calculateEchoAlpha(
    uv: vec2<f32>,
    brightness: f32,
    params: vec4<f32>
) -> f32 {
    let baseAlpha = brightness * depthLayeredAlpha(uv, params.z);
    return clamp(baseAlpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    
    // Parameters
    let accumulationRate = u.zoom_params.x;
    let echoDecay = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let echoCount = i32(u.zoom_params.w * 8.0 + 2.0);
    
    // Current frame
    let current = textureLoad(readTexture, coord, 0);
    
    // Previous accumulated frame
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Create echo effect by sampling at different scales
    var echoAccum = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    for (var i: i32 = 0; i < echoCount; i++) {
        let fi = f32(i);
        let scale = 1.0 - fi * 0.05;
        let echoUV = (uv - 0.5) / scale + 0.5;
        
        if (echoUV.x >= 0.0 && echoUV.x <= 1.0 && echoUV.y >= 0.0 && echoUV.y <= 1.0) {
            let echoSample = textureSampleLevel(dataTextureC, u_sampler, echoUV, 0.0);
            let weight = pow(echoDecay, fi);
            echoAccum += echoSample.rgb * weight;
            totalWeight += weight;
        }
    }
    
    let echoColor = echoAccum / max(totalWeight, 0.001);
    
    // Blend current with echo
    let blended = mix(echoColor, current.rgb, 0.3);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let brightness = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = calculateEchoAlpha(uv, brightness, u.zoom_params);
    
    // Accumulate alpha over time
    let accumulated = accumulativeAlpha(
        blended,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    textureStore(dataTextureA, coord, accumulated);
    textureStore(writeTexture, global_id.xy, accumulated);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
