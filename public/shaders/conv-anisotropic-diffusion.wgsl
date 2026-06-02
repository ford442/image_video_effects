// ═══════════════════════════════════════════════════════════════════
//  Anisotropic Diffusion
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: perona-malik-anisotropic-diffusion
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Diffused image (iterative smoothing along edges)
//    Alpha: Diffusion coefficient per pixel (how much smoothing was applied).
//           This creates a "process map" useful for stacking effects —
//           downstream shaders can read alpha to know which regions were simplified.
//
//  Perona-Malik anisotropic diffusion: smooths along edges but not across them.
//  Creates an oil-painting effect that progressively simplifies into flat regions.
//
//  MOUSE INTERACTIVITY:
//    Mouse position acts as a "heat source" where diffusion is accelerated,
//    creating melting/oil-paint drips emanating from the cursor.
//    Ripples inject transient diffusion fronts.
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
    return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let pixel = vec2<i32>(global_id.xy);
    
    // Parameters
    let kappa = mix(0.01, 0.2, u.zoom_params.x);
    let dt = mix(0.05, 0.25, u.zoom_params.y);
    let iterations = i32(mix(1.0, 5.0, u.zoom_params.z));
    let mouseInfluence = u.zoom_params.w;
    
    // Depth awareness: preserve edges more in foreground
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthKappa = kappa * (1.0 - depth * 0.4);
    
    // Audio reactivity: bass drives diffusion strength
    let bass = plasmaBuffer[0].x;
    let audioDt = dt * (1.0 + bass * 0.8);
    
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var current = center;
    var avgCoeff = 0.0;
    
    for (var iter = 0; iter < iterations; iter++) {
        let n = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 1.0) * pixelSize, 0.0).rgb;
        let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -1.0) * pixelSize, 0.0).rgb;
        let e = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 0.0) * pixelSize, 0.0).rgb;
        let w = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 0.0) * pixelSize, 0.0).rgb;
        
        let gradN = length(n - current);
        let gradS = length(s - current);
        let gradE = length(e - current);
        let gradW = length(w - current);
        
        let cN = diffusionCoefficient(gradN, depthKappa);
        let cS = diffusionCoefficient(gradS, depthKappa);
        let cE = diffusionCoefficient(gradE, depthKappa);
        let cW = diffusionCoefficient(gradW, depthKappa);
        
        let mouseDist = length(uv - mousePos);
        let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * mouseInfluence;
        let mouseBoost = 1.0 + mouseFactor * 5.0;
        
        var rippleFront = 0.0;
        let rippleCount = u32(u.config.y);
        for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
            let ripple = u.ripples[i];
            let rPos = ripple.xy;
            let rStart = ripple.z;
            let rElapsed = time - rStart;
            if (rElapsed > 0.0 && rElapsed < 3.0) {
                let rDist = length(uv - rPos);
                let wave = exp(-pow((rDist - rElapsed * 0.25) * 15.0, 2.0));
                rippleFront = rippleFront + wave * (1.0 - rElapsed / 3.0);
            }
        }
        let rippleBoost = 1.0 + rippleFront * 3.0;
        
        let fluxN = cN * (n - current);
        let fluxS = cS * (s - current);
        let fluxE = cE * (e - current);
        let fluxW = cW * (w - current);
        
        let effectiveDt = audioDt * mouseBoost * rippleBoost;
        current = current + effectiveDt * (fluxN + fluxS + fluxE + fluxW);
        
        avgCoeff = (cN + cS + cE + cW) * 0.25;
    }
    
    let paintBoost = 1.0 + mouseInfluence * 0.3;
    var finalColor = mix(center, current, paintBoost);
    
    // Temporal accumulation
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalColor = mix(finalColor, prev, 0.15);
    
    // Chromatic aberration on edges
    let edgeMag = length(center - current);
    let caOffset = edgeMag * 0.025;
    let rSample = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(caOffset, 0.0), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(caOffset, 0.0), 0.0).b;
    finalColor = vec3<f32>(rSample, finalColor.g, bSample);
    
    // ACES tone mapping
    finalColor = acesToneMap(finalColor);
    
    // Semantic alpha: diffusion coefficient modulated by depth (foreground = sharper = lower alpha)
    let alpha = clamp(avgCoeff * (1.0 - depth * 0.4), 0.0, 1.0);
    
    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
