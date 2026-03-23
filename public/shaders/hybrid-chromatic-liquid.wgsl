// ═══════════════════════════════════════════════════════════════════
//  Hybrid Chromatic Liquid
//  Category: distortion
//  Features: hybrid, liquid-displacement, chromatic-aberration, flow-field
//  Chunks From: liquid-metal.wgsl (fresnel), hyperbolic-dreamweaver.wgsl (chromaticAberration),
//               luma-flow-field.wgsl (flow-field pattern)
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Fluid-like distortion with RGB channel separation flowing
//           along a noise-generated flow field
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK 1: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK 2: valueNoise (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ═══ CHUNK 3: fbm2 (from gen_grid.wgsl) ═══
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ CHUNK 4: fresnelSchlick (from crystal-facets.wgsl) ═══
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ HYBRID LOGIC: Flow Field + Chromatic Liquid ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let flowScale = mix(1.0, 5.0, u.zoom_params.x);        // x: Flow field scale
    let distortionStrength = mix(0.02, 0.15, u.zoom_params.y); // y: Liquid distortion
    let chromaticAmount = u.zoom_params.z * 0.08;          // z: RGB split
    let flowSpeed = mix(0.2, 1.5, u.zoom_params.w);        // w: Animation speed
    
    // Calculate flow field from FBM
    let flowUV = uv * flowScale + time * flowSpeed * 0.1;
    let angle1 = fbm2(flowUV, 4) * 6.28318;
    let angle2 = fbm2(flowUV + vec2<f32>(5.2, 1.3), 4) * 6.28318;
    
    // Create flow vectors
    let flowX = cos(angle1);
    let flowY = sin(angle2);
    let flow = vec2<f32>(flowX, flowY);
    
    // Liquid displacement accumulates along flow
    var displacedUV = uv;
    let steps = 5;
    for (var i: i32 = 0; i < steps; i++) {
        let fi = f32(i) / f32(steps);
        let noiseVal = fbm2(displacedUV * flowScale + time * 0.2, 3);
        displacedUV += flow * distortionStrength * noiseVal * (1.0 - fi);
    }
    
    // Chromatic aberration with different flow for each channel
    let rOffset = displacedUV + flow * chromaticAmount + vec2<f32>(chromaticAmount, 0.0);
    let gOffset = displacedUV;
    let bOffset = displacedUV - flow * chromaticAmount - vec2<f32>(chromaticAmount, 0.0);
    
    // Sample with wrapping for liquid effect
    rOffset.x = fract(rOffset.x);
    rOffset.y = fract(rOffset.y);
    gOffset.x = fract(gOffset.x);
    gOffset.y = fract(gOffset.y);
    bOffset.x = fract(bOffset.x);
    bOffset.y = fract(bOffset.y);
    
    // Sample input texture
    let r = textureSampleLevel(readTexture, u_sampler, rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bOffset, 0.0).b;
    var color = vec3<f32>(r, g, b);
    
    // Add liquid highlights based on distortion magnitude
    let distortionMag = length(displacedUV - uv);
    let highlight = vec3<f32>(0.3, 0.5, 0.7) * distortionMag * 5.0;
    color += highlight;
    
    // Fresnel-like edge effect
    let edgeDist = length(uv - 0.5);
    let fresnel = fresnelSchlick(1.0 - edgeDist, 0.1);
    color = mix(color, vec3<f32>(0.8, 0.9, 1.0), fresnel * 0.3);
    
    // Alpha based on distortion
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.5, 1.0, luma + distortionMag * 2.0);
    
    // Sample and write depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, gOffset, 0.0).r;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, clamp(alpha, 0.0, 1.0)));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth * (1.0 - distortionMag), 0.0, 0.0, 0.0));
}
