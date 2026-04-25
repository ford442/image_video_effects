// ═══════════════════════════════════════════════════════════════════
//  Difference of Gaussians Cascade
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: multi-scale-DoG
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    Each channel stores a different DoG scale response (all signed).
//    R: Fine-scale edges (small sigma difference)
//    G: Medium-scale edges
//    B: Coarse-scale edges
//    Alpha: Ultra-coarse scale / residual
//
//  Final compositing maps the 4-scale response vector to psychedelic
//  color via cosine palette. Signed responses in f32 are essential.
//
//  MOUSE INTERACTIVITY:
//    Mouse controls which scale is emphasized — near mouse = fine detail,
//    far from mouse = coarse structure. Creates a focus-pull effect.
//    Ripples inject transient scale bursts.
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

fn gaussianSample(uv: vec2<f32>, pixelSize: vec2<f32>, sigma: f32) -> f32 {
    var accum = 0.0;
    var weightSum = 0.0;
    let radius = i32(ceil(sigma * 2.5));
    let maxRadius = min(radius, 5);
    
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let d = length(vec2<f32>(f32(dx), f32(dy)));
            let w = exp(-d * d / (2.0 * sigma * sigma + 0.001));
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let lum = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            accum += lum * w;
            weightSum += w;
        }
    }
    return accum / max(weightSum, 0.001);
}

fn dog(uv: vec2<f32>, pixelSize: vec2<f32>, sigma1: f32, sigma2: f32) -> f32 {
    return gaussianSample(uv, pixelSize, sigma1) - gaussianSample(uv, pixelSize, sigma2);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
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
    
    // Parameters
    let scaleBase = mix(0.5, 3.0, u.zoom_params.x);
    let contrast = mix(0.5, 4.0, u.zoom_params.y);
    let colorShift = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse distance modulates scale emphasis
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 5.0) * mouseInfluence;
    
    // Ripple scale bursts
    var rippleBurst = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 2.5) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.25) * 12.0, 2.0));
            rippleBurst = rippleBurst + wave * (1.0 - rElapsed / 2.5) * 2.0;
        }
    }
    
    // Four-scale DoG cascade
    let s0 = scaleBase;
    let s1 = s0 * 1.6;
    let s2 = s1 * 1.6;
    let s3 = s2 * 1.6;
    
    let dog0 = dog(uv, pixelSize, s0 * (1.0 + rippleBurst * 0.3), s0 * 1.6) * contrast;
    let dog1 = dog(uv, pixelSize, s1 * (1.0 + rippleBurst * 0.2), s1 * 1.6) * contrast;
    let dog2 = dog(uv, pixelSize, s2 * (1.0 + rippleBurst * 0.1), s2 * 1.6) * contrast;
    let dog3 = dog(uv, pixelSize, s3, s3 * 1.6) * contrast;
    
    // Mouse emphasis: near = fine detail, far = coarse
    let emphasis = mix(vec4<f32>(0.1, 0.3, 0.5, 0.9), vec4<f32>(0.8, 0.5, 0.3, 0.1), mouseFactor);
    
    let rResponse = dog0 * emphasis.x;
    let gResponse = dog1 * emphasis.y;
    let bResponse = dog2 * emphasis.z;
    let aResponse = dog3 * emphasis.w;
    
    // Map 4D response to psychedelic color
    let palR = palette(rResponse * 0.3 + 0.5 + colorShift, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let palG = palette(gResponse * 0.3 + 0.5 + colorShift + 0.25, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let palB = palette(bResponse * 0.3 + 0.5 + colorShift + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    
    let totalWeight = abs(rResponse) + abs(gResponse) + abs(bResponse) + 0.001;
    var color = (palR * abs(rResponse) + palG * abs(gResponse) + palB * abs(bResponse)) / totalWeight;
    
    // Boost edges
    color = color * (1.0 + length(vec3<f32>(rResponse, gResponse, bResponse)) * 0.5);
    
    // Store: RGB = colored multi-scale edges, Alpha = ultra-coarse DoG (signed)
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, aResponse));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
