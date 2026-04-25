// ═══════════════════════════════════════════════════════════════════
//  Morphological Erosion Dilation
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: morphological
//  Complexity: Medium
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    R channel: Erosion result (min filter luminance)
//    G channel: Dilation result (max filter luminance)
//    B channel: Morphological gradient (dilation - erosion = edge thickness)
//    Alpha: Top-hat transform (original - opening = isolated bright peaks)
//
//  Why RGBA32FLOAT matters: Morphological gradient magnitudes can be extremely
//  small (0.001) or large (2.0+) in HDR content. 8-bit would quantize the
//  gradient to ~4 levels, destroying the delicate edge structure.
//
//  MOUSE INTERACTIVITY:
//    Mouse position controls the structuring element shape — near mouse it
//    becomes elongated (directional morphology), creating flow-like patterns.
//    Ripples trigger momentary dilation "explosions."
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
    let kernelRadius = i32(mix(2.0, 6.0, u.zoom_params.x));
    let erosionDilationBlend = u.zoom_params.y;  // 0=erosion, 1=dilation
    let gradientBoost = mix(0.5, 3.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse-driven structuring element deformation
    let mouseDist = length(uv - mousePos);
    let mouseAngle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * mouseInfluence;
    
    // Ripple dilation explosions
    var rippleExplosion = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 2.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-rDist * rDist * 80.0) * (1.0 - rElapsed / 2.0);
            rippleExplosion = rippleExplosion + wave;
        }
    }
    let effectiveRadius = kernelRadius + i32(rippleExplosion * 4.0);
    let maxRadius = min(effectiveRadius, 8);
    
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let centerLuma = dot(center.rgb, vec3<f32>(0.299, 0.587, 0.114));
    
    var minVal = vec3<f32>(999.0);
    var maxVal = vec3<f32>(-999.0);
    var minLuma = 999.0;
    var maxLuma = -999.0;
    
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            // Directional structuring element near mouse
            var dxF = f32(dx);
            var dyF = f32(dy);
            if (mouseFactor > 0.01) {
                let cosA = cos(mouseAngle);
                let sinA = sin(mouseAngle);
                let rotX = dxF * cosA - dyF * sinA;
                let rotY = dxF * sinA + dyF * cosA;
                // Elongate along mouse angle
                dxF = mix(dxF, rotX * 1.5, mouseFactor);
                dyF = mix(dyF, rotY * 0.6, mouseFactor);
            }
            
            // Circular structuring element check
            if (dxF*dxF + dyF*dyF > f32(maxRadius*maxRadius)) { continue; }
            
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let sample = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            
            minVal = min(minVal, sample);
            maxVal = max(maxVal, sample);
            minLuma = min(minLuma, luma);
            maxLuma = max(maxLuma, luma);
        }
    }
    
    let erosion = minVal;
    let dilation = maxVal;
    let gradient = (dilation - erosion) * gradientBoost;
    let topHat = center.rgb - erosion;
    
    let gradientLuma = dot(gradient, vec3<f32>(0.299, 0.587, 0.114));
    let topHatLuma = dot(topHat, vec3<f32>(0.299, 0.587, 0.114));
    
    // Blend erosion <-> dilation via param, edge-highlight in between
    let blendRGB = mix(erosion, dilation, erosionDilationBlend);
    let finalRGB = blendRGB + gradient * 0.3;
    
    // Pack: RGB = blended morphology, Alpha = top-hat luminance
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalRGB, topHatLuma));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
