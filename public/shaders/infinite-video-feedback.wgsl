// ═══════════════════════════════════════════════════════════════════
//  Infinite Video Feedback
//  Category: image
//  Features: mouse-driven, temporal-persistence, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
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
  zoom_params: vec4<f32>,  // x=AccumulationRate, y=RecursionDepth, z=DepthWeight, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

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

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.5, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let accumulationRate = u.zoom_params.x;
    let recursionDepth = u.zoom_params.y * 0.02 * (1.0 + bass * 0.3 + mids * 0.3);
    let depthWeight = u.zoom_params.z;
    let colorShift = u.zoom_params.w + treble * 0.2;
    
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Infinite recursion effect
    var accumulatedColor = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    for (var i: i32 = 0; i < 5; i++) {
        let fi = f32(i);
        let scale = 1.0 - fi * recursionDepth;
        let recursiveUV = (uv - 0.5) / scale + 0.5;
        
        if (recursiveUV.x >= 0.0 && recursiveUV.x <= 1.0 && recursiveUV.y >= 0.0 && recursiveUV.y <= 1.0) {
            let recursiveSample = textureSampleLevel(dataTextureC, u_sampler, recursiveUV, 0.0);
            let weight = pow(0.7, fi);
            let hueShift = vec3<f32>(
                recursiveSample.r * (1.0 + colorShift * sin(fi)),
                recursiveSample.g,
                recursiveSample.b * (1.0 + colorShift * cos(fi))
            );
            accumulatedColor += hueShift * weight;
            totalWeight += weight;
        }
    }
    
    let finalColor = accumulatedColor / max(totalWeight, 0.001);
    let newAlpha = depthLayeredAlpha(uv, depthWeight) * length(finalColor);
    
    let accumulated = accumulativeAlpha(
        finalColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    let rgbResult = mix(accumulated.rgb, current.rgb, 0.05);
    let finalAlpha = mix(current.a, 1.0, accumulationRate * 0.7);
    let result = vec4<f32>(rgbResult, finalAlpha);
    
    textureStore(dataTextureA, coord, result);
    textureStore(writeTexture, global_id.xy, result);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}
