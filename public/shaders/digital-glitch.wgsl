// ═══════════════════════════════════════════════════════════════════
//  Digital Glitch
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-04-15
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash21(p: vec2<f32>) -> f32 {
    var n = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(n) * 43758.5453123);
}

fn hash33(p: vec3<f32>) -> f32 {
    var n = dot(p, vec3<f32>(127.1, 311.7, 74.7));
    return fract(sin(n) * 43758.5453123);
}

fn floatToByte(v: f32) -> u32 {
    return u32(clamp(v, 0.0, 1.0) * 255.0);
}

fn byteToFloat(b: u32) -> f32 {
    return f32(b & 0xFFu) / 255.0;
}

fn bitRotateRight(b: u32, n: u32) -> u32 {
    let shift = n % 8u;
    return ((b >> shift) | (b << (8u - shift))) & 0xFFu;
}

fn bitRotateLeft(b: u32, n: u32) -> u32 {
    let shift = n % 8u;
    return ((b << shift) | (b >> (8u - shift))) & 0xFFu;
}

fn xorCorrupt(b: u32, mask: u32) -> u32 {
    return (b ^ mask) & 0xFFu;
}

fn bitFlip(b: u32, pos: u32) -> u32 {
    return b ^ (1u << (pos % 8u));
}

fn randomBitFlip(b: u32, seed: f32, probability: f32) -> u32 {
    let bitPos = u32(seed * 1000.0) % 8u;
    return select(b, bitFlip(b, bitPos), seed < probability);
}

fn nibbleSwap(b: u32) -> u32 {
    return ((b & 0x0Fu) << 4u) | ((b & 0xF0u) >> 4u);
}

fn bitReverse(b: u32) -> u32 {
    var result = 0u;
    result = result | ((b & 0x01u) << 7u);
    result = result | ((b & 0x02u) << 5u);
    result = result | ((b & 0x04u) << 3u);
    result = result | ((b & 0x08u) << 1u);
    result = result | ((b & 0x10u) >> 1u);
    result = result | ((b & 0x20u) >> 3u);
    result = result | ((b & 0x40u) >> 5u);
    result = result | ((b & 0x80u) >> 7u);
    return result;
}

fn reduceBitDepth(b: u32, bits: u32) -> u32 {
    let shift = clamp(8u - bits, 0u, 8u);
    return (b >> shift) << shift;
}

fn getCorruptionMask(uv: vec2<f32>, time: f32, patternType: f32, intensity: f32) -> u32 {
    let t = time * 0.5;
    let stripe = floor(uv.x * 32.0 + sin(t * 2.0) * 4.0);
    let stripeMask = u32(stripe) % 255u;
    let blockCoord = floor(uv * vec2<f32>(16.0));
    let blockSeed = hash21(blockCoord + vec2<f32>(floor(t), 0.0));
    let blockMask = u32(blockSeed * 255.0);
    let scanLine = abs(uv.y - fract(t * 0.2));
    let scanActive = step(scanLine, 0.02);
    let scanMask = select(0u, 0xAAu, scanActive > 0.5);
    let noiseVal = hash21(uv * 1000.0 + t);
    let noiseMask = u32(noiseVal * 255.0);
    let patternSelect = fract(patternType * 4.0 + t * 0.1);
    
    let s0 = step(patternSelect, 0.25);
    let s1 = step(0.25, patternSelect) * step(patternSelect, 0.5);
    let s2 = step(0.5, patternSelect) * step(patternSelect, 0.75);
    let s3 = step(0.75, patternSelect);
    
    var mask = select(0u, stripeMask, s0 > 0.0);
    mask = select(mask, blockMask, s1 > 0.0);
    mask = select(mask, scanMask, s2 > 0.0);
    mask = select(mask, noiseMask, s3 > 0.0);
    
    mask = select(mask, mask & 0x0Fu, intensity < 0.5);
    
    return mask;
}

fn corruptByte(b: u32, corruptionType: f32, seed: f32, intensity: f32) -> u32 {
    let typeIdx = u32(corruptionType * 5.0) % 6u;
    let rotAmt = u32(seed * 8.0);
    let xorMask = u32(seed * 255.0);
    let flipProb = intensity * 0.3;
    
    let case0 = bitRotateRight(b, rotAmt);
    let case1 = xorCorrupt(b, xorMask);
    let case2 = randomBitFlip(b, seed, flipProb);
    let case3 = nibbleSwap(b);
    let case4 = bitReverse(b);
    let case5 = xorCorrupt(bitRotateLeft(b, 2u), u32(seed * 128.0));
    
    var result = select(0u, case0, typeIdx == 0u);
    result = select(result, case1, typeIdx == 1u);
    result = select(result, case2, typeIdx == 2u);
    result = select(result, case3, typeIdx == 3u);
    result = select(result, case4, typeIdx == 4u);
    result = select(result, case5, typeIdx == 5u);
    
    return result & 0xFFu;
}

fn propagateError(color: vec3<f32>, uv: vec2<f32>, readTex: texture_2d<f32>, 
                  resolution: vec2<f32>, propagationAmount: f32, time: f32) -> vec3<f32> {
    let texelSize = 1.0 / resolution;
    var corruptedColor = color;
    var errorWeight = 0.0;
    
    let offsets = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, 0.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.0, -1.0),
        vec2<f32>(0.0, 1.0)
    );
    
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let neighborUV = uv + offsets[i] * texelSize;
        let neighborColor = textureSampleLevel(readTex, u_sampler, neighborUV, 0.0).rgb;
        let neighborHash = hash21(neighborUV * 500.0 + time);
        let isCorrupted = step(neighborHash, propagationAmount * 0.3);
        let weight = 0.25 * propagationAmount * isCorrupted;
        corruptedColor = mix(corruptedColor, neighborColor, weight);
        errorWeight = errorWeight + weight;
    }
    
    return corruptedColor;
}

fn applyDigitalDecay(color: vec3<f32>, decayRate: f32, time: f32, uv: vec2<f32>) -> vec3<f32> {
    let baseBits = 8.0;
    let timeDecay = time * decayRate * 0.5;
    let spatialDecay = hash21(floor(uv * 32.0) + time * 0.1) * decayRate * 2.0;
    let targetBits = max(1.0, baseBits - timeDecay - spatialDecay);
    let bits = u32(targetBits);
    
    let r = byteToFloat(reduceBitDepth(floatToByte(color.r), bits));
    let g = byteToFloat(reduceBitDepth(floatToByte(color.g), bits));
    let b = byteToFloat(reduceBitDepth(floatToByte(color.b), bits));
    var decayedColor = vec3<f32>(r, g, b);
    
    let levels = max(2.0, 16.0 - timeDecay * 2.0);
    let posterized = floor(decayedColor * levels) / levels;
    decayedColor = mix(decayedColor, posterized, step(0.5, decayRate));
    
    return decayedColor;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let texelCoord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let corruptionIntensity = clamp(u.zoom_params.x * (1.0 + bass * 0.4), 0.0, 1.0);
    let bitManipulationType = u.zoom_params.y;
    let errorPropagation = u.zoom_params.z;
    let decayRate = u.zoom_params.w;
    
    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);
    let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);
    let effectiveIntensity = clamp(corruptionIntensity + mouseInfluence * 0.3, 0.0, 1.0);
    
    let blockSize = mix(8.0, 64.0, effectiveIntensity);
    let blockCoord = floor(uv * blockSize);
    let blockSeed = hash21(blockCoord + vec2<f32>(time * 0.1, 0.0));
    
    let maxShift = mix(0.0, 0.05, effectiveIntensity);
    let xShift = (blockSeed - 0.5) * maxShift;
    let yShift = (hash21(blockCoord + vec2<f32>(7.0, 3.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;
    
    var displacedUV = uv + vec2<f32>(xShift, yShift);
    
    let row = floor(uv.y * blockSize);
    let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
    let tear = step(0.95, scanSeed);
    displacedUV.x = displacedUV.x + tear * 0.15 * (blockSeed - 0.5) * effectiveIntensity;
    displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));
    
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    var color = baseColor.rgb;
    
    let pixelSeed = hash33(vec3<f32>(uv * 1000.0, time));
    let corruptionMask = getCorruptionMask(uv, time, blockSeed, effectiveIntensity);
    
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
        var byteVal = floatToByte(color[channel]);
        let channelSeed = hash21(uv + vec2<f32>(f32(channel) * 100.0, time));
        let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
        byteVal = randomBitFlip(byteVal, channelSeed, flipProb);
        
        let patternCondition = step(0.7 - effectiveIntensity * 0.4, blockSeed);
        let patternIntensity = (blockSeed - 0.7 + effectiveIntensity * 0.4) / max(0.3 + effectiveIntensity * 0.4, 0.0001);
        let typeVar = bitManipulationType + f32(channel) * 0.1;
        let corrupted = corruptByte(byteVal, typeVar, channelSeed, patternIntensity);
        byteVal = select(byteVal, corrupted, patternCondition > 0.0);
        
        let xorCondition = step(0.5, patternIntensity) * patternCondition;
        byteVal = select(byteVal, xorCorrupt(byteVal, corruptionMask), xorCondition > 0.0);
        
        let temporalSeed = hash21(uv + vec2<f32>(floor(time * 2.0)));
        let temporalCondition = step(temporalSeed, effectiveIntensity * 0.15);
        byteVal = select(byteVal, bitRotateRight(byteVal, u32(temporalSeed * 8.0)), temporalCondition > 0.0);
        
        color[channel] = byteToFloat(byteVal);
    }
    
    color = propagateError(color, displacedUV, readTexture, resolution, errorPropagation, time);
    color = applyDigitalDecay(color, decayRate, time, uv);
    
    let chromaStrength = effectiveIntensity * 0.03;
    let rOffset = vec2<f32>(chromaStrength * (1.0 + sin(time * 2.0) * 0.5), 0.0);
    let bOffset = vec2<f32>(-chromaStrength * (1.0 + cos(time * 1.5) * 0.5), 0.0);
    
    let rSample = textureSampleLevel(readTexture, u_sampler, displacedUV + rOffset, 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, displacedUV + bOffset, 0.0).b;
    
    color.r = mix(color.r, rSample, 0.5 + effectiveIntensity * 0.3);
    color.b = mix(color.b, bSample, 0.5 + effectiveIntensity * 0.3);
    
    let invertSeed = hash21(blockCoord + vec2<f32>(time * 0.5, 100.0));
    let invertCondition = step(0.9 - effectiveIntensity * 0.4, invertSeed);
    let invertStrength = (invertSeed - 0.9 + effectiveIntensity * 0.4) / max(0.1 + effectiveIntensity * 0.4, 0.0001);
    color = mix(color, 1.0 - color, invertStrength * 0.7 * invertCondition);
    
    let scanlineY = floor(uv.y * resolution.y);
    let scanlinePattern = step(0.5, fract(scanlineY * 0.5));
    color = mix(color, color * 0.9, scanlinePattern * effectiveIntensity * 0.3);
    
    let dist = length(uv - 0.5);
    color = color * (1.0 - smoothstep(0.7, 1.0, dist) * 0.5);
    
    let glitchLuma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + glitchLuma * 0.3 + effectiveIntensity * 0.3 + mouseInfluence * 0.15, 0.0, 1.0);
    
    textureStore(writeTexture, texelCoord, vec4<f32>(color, alpha));
    textureStore(dataTextureA, texelCoord, vec4<f32>(color, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
