// ═══════════════════════════════════════════════════════════════════
//  Reaction Convolution
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: gray-scott-reaction-diffusion-filter
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    R: Chemical A concentration (needs f32 precision for stable PDE integration)
//    G: Chemical B concentration
//  B: Filtered image mixed with R-D pattern
//    Alpha: Reaction rate (feed/kill parameter spatially varying from mouse distance)
//
//  Runs 1 step of Gray-Scott reaction-diffusion per frame as a FILTER on
//  the input image, using image luminance to seed the A/B concentrations.
//
//  MOUSE INTERACTIVITY:
//    Mouse position injects chemical B (creating pattern nucleation).
//    Mouse down increases feed rate locally. Ripples create traveling
//    reaction fronts across the image.
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
    let diffA = mix(0.8, 1.0, u.zoom_params.x);  // Diffusion rate A
    let diffB = mix(0.2, 0.5, u.zoom_params.y);  // Diffusion rate B
    let feedBase = mix(0.01, 0.09, u.zoom_params.z);  // Feed rate
    let mouseInfluence = u.zoom_params.w;
    
    // Use image luminance to seed concentrations
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // Seed A from image brightness, B from edges
    let centerA = inputLuma;
    let dx = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let dy = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    let edge = length(dx - inputColor) + length(dy - inputColor);
    let centerB = edge * 2.0;
    
    // Neighbors for Laplacian
    let n = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0);
    let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -pixelSize.y), 0.0);
    let e = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0);
    let w = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixelSize.x, 0.0), 0.0);
    
    let nLuma = dot(n.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let sLuma = dot(s.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let eLuma = dot(e.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let wLuma = dot(w.rgb, vec3<f32>(0.299, 0.587, 0.114));
    
    let nEdge = length(n.rgb - inputColor) + length(n.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y * 2.0), 0.0).rgb);
    let sEdge = length(s.rgb - inputColor) + length(s.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -pixelSize.y * 2.0), 0.0).rgb);
    let eEdge = length(e.rgb - inputColor) + length(e.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x * 2.0, 0.0), 0.0).rgb);
    let wEdge = length(w.rgb - inputColor) + length(w.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixelSize.x * 2.0, 0.0), 0.0).rgb);
    
    // Laplacian approximations
    let lapA = (nLuma + sLuma + eLuma + wLuma) * 0.25 - inputLuma;
    let lapB = (nEdge + sEdge + eEdge + wEdge) * 0.25 - edge * 2.0;
    
    // Mouse injection of B
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 15.0) * mouseInfluence;
    let mouseB = mouseFactor * (1.0 + mouseDown * 2.0);
    
    // Ripple reaction fronts
    var rippleFeed = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.2) * 12.0, 2.0));
            rippleFeed = rippleFeed + wave * (1.0 - rElapsed / 3.0) * 0.05;
        }
    }
    
    let effectiveFeed = feedBase + rippleFeed + mouseFactor * 0.03;
    let kill = effectiveFeed * 0.5 + mouseFactor * 0.02;  // Classic ratio
    
    let reaction = centerA * centerB * centerB;
    
    let newA = centerA + (diffA * lapA - reaction + effectiveFeed * (1.0 - centerA)) * 0.5;
    let newB = centerB + (diffB * lapB + reaction - (kill + effectiveFeed) * centerB + mouseB) * 0.5;
    
    // Clamp for stability
    let clampedA = clamp(newA, 0.0, 1.0);
    let clampedB = clamp(newB, 0.0, 1.0);
    
    // Mix input with R-D pattern
    let pattern = clampedA - clampedB;
    let rdColor = vec3<f32>(
        pattern * 0.8 + clampedB * 0.5,
        pattern * 0.5 + clampedA * 0.3,
        clampedB * 0.8 + 0.1
    );
    let mixFactor = 0.5 + mouseFactor * 0.3;
    let finalColor = mix(inputColor, rdColor, mixFactor);
    
    // Store: R=A, G=B, B=mixed image, Alpha=local reaction rate
    textureStore(writeTexture, global_id.xy, vec4<f32>(clampedA, clampedB, finalColor.b, effectiveFeed));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
