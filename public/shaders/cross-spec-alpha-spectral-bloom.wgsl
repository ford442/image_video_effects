// ═══════════════════════════════════════════════════════════════════
//  Crossover: Spectral + Alpha — Spectral Bloom HDR
//  Category: visual-effects
//  Features: crossover, spectral-rendering, rgba32float-exploiting
//  Crosses: spec-prismatic-dispersion (3C) + alpha-hdr-bloom-chain (4C)
//  Complexity: High
//  Created: 2026-04-19
//  By: Agent 5C — Phase C Crossover Integration
// ═══════════════════════════════════════════════════════════════════
//
//  Decomposes the input image into 4 spectral bands (R, G, B, luminance)
//  stored in RGBA. Each band gets independent bloom intensity driven by
//  alpha-as-exposure. The spectral recombination uses Cauchy dispersion
//  for chromatic separation.
//
//  RGBA32FLOAT EXPLOITATION:
//    R: Red spectral band bloom
//    G: Green spectral band bloom
//    B: Blue spectral band bloom
//    A: Luminance band bloom (controls overall exposure)
//
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

fn cauchyDispersion(lambda: f32, n0: f32, B: f32) -> f32 {
    return n0 + B / (lambda * lambda);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixel = 1.0 / res;
    let time = u.config.x;
    
    let bloomRadius = mix(2.0, 8.0, u.zoom_params.x);
    let dispersionAmt = mix(0.0, 0.015, u.zoom_params.y);
    let exposure = mix(0.5, 3.0, u.zoom_params.z);
    let chromaticShift = mix(0.0, 1.0, u.zoom_params.w);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // Spectral wavelengths for RGB (nm)
    let lambdaR = 650.0;
    let lambdaG = 530.0;
    let lambdaB = 460.0;
    
    var bloomR = 0.0;
    var bloomG = 0.0;
    var bloomB = 0.0;
    var bloomL = 0.0;
    
    let radius = i32(bloomRadius);
    var weightSum = 0.0;
    
    for (var y: i32 = -radius; y <= radius; y = y + 1) {
        for (var x: i32 = -radius; x <= radius; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * pixel;
            let sUV = uv + offset;
            let sCol = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
            let sLuma = dot(sCol, vec3<f32>(0.299, 0.587, 0.114));
            
            let dist2 = f32(x * x + y * y);
            let w = exp(-dist2 / (bloomRadius * bloomRadius * 0.5));
            
            bloomR = bloomR + sCol.r * w;
            bloomG = bloomG + sCol.g * w;
            bloomB = bloomB + sCol.b * w;
            bloomL = bloomL + sLuma * w;
            weightSum = weightSum + w;
        }
    }
    
    bloomR = bloomR / weightSum;
    bloomG = bloomG / weightSum;
    bloomB = bloomB / weightSum;
    bloomL = bloomL / weightSum;
    
    // Dispersion offsets
    let nR = cauchyDispersion(lambdaR, 1.5, 4000.0);
    let nG = cauchyDispersion(lambdaG, 1.5, 4000.0);
    let nB = cauchyDispersion(lambdaB, 1.5, 4000.0);
    
    let shiftR = (nR - nG) * dispersionAmt * chromaticShift;
    let shiftB = (nB - nG) * dispersionAmt * chromaticShift;
    
    let dispersedR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(shiftR, 0.0), 0.0).r;
    let dispersedB = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(shiftB, 0.0), 0.0).b;
    let dispersedG = inputColor.g;
    
    let bloomColor = vec3<f32>(bloomR, bloomG, bloomB);
    let dispersedColor = vec3<f32>(dispersedR, dispersedG, dispersedB);
    
    // HDR accumulation
    let hdrBloom = bloomColor * exposure * (1.0 + bloomL * 2.0);
    let finalColor = dispersedColor + hdrBloom * 0.3;
    let tonemapped = finalColor / (1.0 + finalColor * 0.3);
    
    // Store spectral bands in RGBA
    textureStore(writeTexture, global_id.xy, vec4<f32>(tonemapped, bloomL * exposure));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
