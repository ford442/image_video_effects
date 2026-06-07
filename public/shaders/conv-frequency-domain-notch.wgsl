// ═══════════════════════════════════════════════════════════════════
//  Frequency Domain Notch
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, temporal, depth-aware
//  Convolution Type: spatial-frequency-notch-approximation
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Filtered image with specific frequencies removed/boosted
//    Alpha: Frequency response magnitude — how strongly each frequency
//           band was modified. Creates a spectral importance map.
//
//  Approximates removing specific spatial frequencies using a bank of tuned
//  sinusoidal convolution kernels. Removes moire patterns, aliasing artifacts,
//  or creates "frequency painting" by selectively boosting/cutting bands.
//
//  MOUSE INTERACTIVITY:
//    Mouse position selects which frequency band to boost/cut.
//    Distance from mouse maps to frequency. Ripples create transient
//    frequency sweeps.
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

fn notchFilterResponse(freq: f32, targetFreq: f32, bandwidth: f32) -> f32 {
    let dist = abs(freq - targetFreq);
    return 1.0 - exp(-dist * dist / (bandwidth * bandwidth + 0.001));
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
    let depthFactor = mix(0.6, 1.4, depth);
    
    // Parameters
    let numBands = i32(mix(2.0, 6.0, u.zoom_params.x));
    let bandwidth = mix(0.02, 0.1, u.zoom_params.y) * (1.0 + treble * 0.3);
    let boostCut = mix(-1.0, 1.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse selects target frequency
    let mouseDist = length(uv - mousePos);
    let mouseFreq = mouseDist * 2.0;
    let mouseFactor = exp(-mouseDist * mouseDist * 4.0) * mouseInfluence;
    
    // Ripple frequency sweeps
    var rippleFreq = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 8.0, 2.0));
            rippleFreq = rippleFreq + wave * (1.0 - rElapsed / 3.0) * 0.5;
        }
    }
    
    // Bass-driven notch frequency modulation
    let bassFreqMod = bass * 0.1;
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var filtered = vec3<f32>(0.0);
    var totalResponse = 0.0;
    
    let maxRadius = 6;
    
    for (var band = 0; band < numBands; band++) {
        let bandFreq = mix(0.05, 0.5, f32(band) / f32(numBands - 1)) + rippleFreq + bassFreqMod;
        let targetFreq = mix(bandFreq, mouseFreq, mouseFactor) * depthFactor;
        
        // Sinusoidal convolution kernel for this band
        var bandAccum = vec3<f32>(0.0);
        var bandWeight = 0.0;
        
        for (var dy = -maxRadius; dy <= maxRadius; dy++) {
            for (var dx = -maxRadius; dx <= maxRadius; dx++) {
                let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
                let d = length(vec2<f32>(f32(dx), f32(dy)));
                let sample = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
                
                // Cosine kernel at target frequency
                let kernel = cos(d * targetFreq * 6.28318) * exp(-d * d * 0.05);
                bandAccum += sample * kernel;
                bandWeight += abs(kernel);
            }
        }
        
        if (bandWeight > 0.001) {
            bandAccum = bandAccum / bandWeight;
        }
        
        // Notch or boost this band
        let response = notchFilterResponse(bandFreq, targetFreq, bandwidth);
        let modResponse = mix(response, 2.0 - response, step(0.0, boostCut));
        let bandResult = mix(bandAccum, bandAccum * (1.0 + abs(boostCut)), step(0.0, boostCut) * response);
        
        filtered += bandResult;
        totalResponse += modResponse;
    }
    
    filtered = filtered / f32(numBands);
    
    // Colorize by frequency band response
    let responseNorm = clamp(totalResponse / f32(numBands), 0.0, 1.0);
    let freqColor = palette(responseNorm + time * 0.05, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    var finalColor = mix(filtered, filtered * freqColor * 1.5, abs(boostCut) * 0.3);
    
    // Chromatic aberration on filtered bands
    let caStrength = responseNorm * (1.0 + mids * 0.5) * 0.6;
    let caOffset = pixelSize * caStrength;
    let chrR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(caOffset.x, 0.0), 0.0).r;
    let chrG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let chrB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(caOffset.x, 0.0), 0.0).b;
    let chromatic = vec3<f32>(chrR, chrG, chrB);
    finalColor = mix(finalColor, chromatic, caStrength * 0.4);
    
    // ACES tone mapping
    finalColor = acesToneMap(finalColor);
    
    // Temporal feedback morphing
    let prevColor = textureLoad(dataTextureC, pixel, 0).rgb;
    let decay = 0.88;
    finalColor = mix(finalColor, prevColor * decay, 0.15 + bass * 0.2);
    
    // Semantic alpha: spectral response modulated by depth and audio
    let alpha = responseNorm * (0.5 + depth * 0.5) * (0.6 + bass * 0.4);
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
    
    // Depth pass-through
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
