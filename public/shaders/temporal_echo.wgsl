// ═══════════════════════════════════════════════════════════════════════════════
//  Temporal Echo (Alt) - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Depth-Layered
//  Features: advanced-alpha, temporal-echo, frame-accumulation
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    
    let accumulationRate = u.zoom_params.x;
    let echoDelay = u.zoom_params.y * 0.1;
    let depthWeight = u.zoom_params.z;
    let feedback = u.zoom_params.w;
    
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Echo offset
    let echoUV = uv + vec2<f32>(sin(time * 0.5) * echoDelay, cos(time * 0.3) * echoDelay);
    let echo = textureSampleLevel(dataTextureC, u_sampler, fract(echoUV), 0.0);
    
    let brightness = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = brightness * depthLayeredAlpha(uv, depthWeight);
    
    let accumulated = accumulativeAlpha(
        current.rgb,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    let finalResult = mix(accumulated, echo, feedback * 0.3);
    
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, global_id.xy, finalResult);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
