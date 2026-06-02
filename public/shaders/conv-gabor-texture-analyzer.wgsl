// ═══════════════════════════════════════════════════════════════════
//  Gabor Texture Analyzer
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, temporal, depth-aware
//  Convolution Type: gabor-filter-bank
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    R channel: Response to horizontal Gabor (0 deg)
//    G channel: Response to diagonal Gabor (45 deg)
//    B channel: Response to vertical Gabor (90 deg)
//    Alpha channel: Response to counter-diagonal Gabor (135 deg)
//
//  All four channels store signed floating-point filter responses — critical
//  because Gabor responses are naturally bipolar. 8-bit would need bias+scale
//  and would lose half the precision.
//
//  MOUSE INTERACTIVITY:
//    Mouse angle (atan2 from center) rotates the entire Gabor bank, causing
//    the texture color mapping to swirl and shift. Ripples inject frequency
//    modulation bursts.
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

fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
    var response = 0.0;
    let radius = i32(ceil(sigma * 3.0));
    let maxRadius = min(radius, 6);
    let cosTheta = cos(theta);
    let sinTheta = sin(theta);
    
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let x = f32(dx);
            let y = f32(dy);
            let xTheta = x * cosTheta + y * sinTheta;
            let yTheta = -x * sinTheta + y * cosTheta;
            
            let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma + 0.001));
            let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
            let kernel = gaussian * sinusoidal;
            
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            response += luma * kernel;
        }
    }
    return response;
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
    let pixel = vec2<i32>(global_id.xy);
    
    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Depth awareness
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = mix(0.7, 1.3, depth);
    
    // Parameters
    let freq = mix(0.05, 0.3, u.zoom_params.x) * depthFactor;
    let sigma = mix(1.5, 4.0, u.zoom_params.y);
    let responseScale = mix(0.5, 3.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse angle rotates Gabor bank
    let mouseAngle = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 4.0) * mouseInfluence;
    let rotationOffset = mouseAngle * mouseFactor + time * 0.1 * (1.0 - mouseFactor);
    
    // Bass-driven orientation offset
    let bassOrientation = bass * 0.8;
    
    // Ripple frequency bursts
    var rippleFreqMod = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 2.5) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.25) * 15.0, 2.0));
            rippleFreqMod = rippleFreqMod + wave * (1.0 - rElapsed / 2.5) * 2.0;
        }
    }
    
    let effectiveFreq = freq * (1.0 + rippleFreqMod);
    
    // Four-orientation Gabor filter bank with bass-driven rotation
    let r0 = gaborResponse(uv, 0.0 + rotationOffset + bassOrientation, effectiveFreq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398 + rotationOffset + bassOrientation, effectiveFreq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796 + rotationOffset + bassOrientation, effectiveFreq, sigma, pixelSize) * responseScale;
    let r135 = gaborResponse(uv, 2.356194 + rotationOffset + bassOrientation, effectiveFreq, sigma, pixelSize) * responseScale;
    
    // Map signed responses to psychedelic color palette
    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));
    
    // Composite: each orientation colors its response
    var color = vec3<f32>(0.0);
    color += pal0 * abs(r0);
    color += pal45 * abs(r45);
    color += pal90 * abs(r90);
    color += pal135 * abs(r135);
    
    let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
    color = color / totalResponse;
    
    // Boost saturation
    color = color * 1.3;
    
    // Chromatic aberration on oriented edges
    let edgeStrength = clamp(totalResponse * 0.03, 0.0, 1.0);
    let caOffset = pixelSize * edgeStrength * (1.0 + mids * 0.6);
    let chrR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(caOffset.x, 0.0), 0.0).r;
    let chrG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let chrB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(caOffset.x, 0.0), 0.0).b;
    let chromatic = vec3<f32>(chrR, chrG, chrB);
    color = mix(color, chromatic, edgeStrength * 0.35);
    
    // ACES tone mapping
    color = acesToneMap(color);
    
    // Temporal texture persistence
    let prevColor = textureLoad(dataTextureC, pixel, 0).rgb;
    let decay = 0.88;
    color = mix(color, prevColor * decay, 0.15 + bass * 0.18);
    
    // Semantic alpha: total response modulated by depth and treble
    let alpha = clamp(totalResponse * 0.15 * (0.5 + depth * 0.5) * (0.6 + treble * 0.4), 0.0, 1.0);
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, alpha));
    
    // Depth pass-through
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
