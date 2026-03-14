// ═══════════════════════════════════════════════════════════════
//  Digital Glitch with Bitwise Corruption
//  Category: artistic
//  Features: bit-flipping, XOR corruption, error propagation, digital decay
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=MouseClickCount, y=MouseX, z=MouseY, w=Param
  zoom_params: vec4<f32>,  // x=CorruptionIntensity, y=BitManipulationType, z=ErrorPropagation, w=DecayRate
  ripples: array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────
// Hash Functions
// ───────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    var n = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(n) * 43758.5453123);
}

fn hash33(p: vec3<f32>) -> f32 {
    var n = dot(p, vec3<f32>(127.1, 311.7, 74.7));
    return fract(sin(n) * 43758.5453123);
}

// ───────────────────────────────────────────────────────────────
// Bit Manipulation Functions
// ───────────────────────────────────────────────────────────────

// Convert float color (0-1) to 8-bit integer representation
fn floatToByte(v: f32) -> u32 {
    return u32(clamp(v, 0.0, 1.0) * 255.0);
}

// Convert 8-bit integer back to float
fn byteToFloat(b: u32) -> f32 {
    return f32(b & 0xFFu) / 255.0;
}

// Bit rotate right - rotate bits within byte
fn bitRotateRight(b: u32, n: u32) -> u32 {
    let shift = n % 8u;
    return ((b >> shift) | (b << (8u - shift))) & 0xFFu;
}

// Bit rotate left
fn bitRotateLeft(b: u32, n: u32) -> u32 {
    let shift = n % 8u;
    return ((b << shift) | (b >> (8u - shift))) & 0xFFu;
}

// XOR corruption with mask
fn xorCorrupt(b: u32, mask: u32) -> u32 {
    return (b ^ mask) & 0xFFu;
}

// Bit flip at specific position
fn bitFlip(b: u32, pos: u32) -> u32 {
    return b ^ (1u << (pos % 8u));
}

// Random bit flip based on probability
fn randomBitFlip(b: u32, seed: f32, probability: f32) -> u32 {
    if (seed < probability) {
        let bitPos = u32(seed * 1000.0) % 8u;
        return bitFlip(b, bitPos);
    }
    return b;
}

// Byte swap - swap high and low nibbles
fn nibbleSwap(b: u32) -> u32 {
    return ((b & 0x0Fu) << 4u) | ((b & 0xF0u) >> 4u);
}

// Bit reversal within byte
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

// Digital decay - reduce bit depth over time
fn reduceBitDepth(b: u32, bits: u32) -> u32 {
    let shift = clamp(8u - bits, 0u, 8u);
    return (b >> shift) << shift;
}

// ───────────────────────────────────────────────────────────────
// Corruption Patterns
// ───────────────────────────────────────────────────────────────

// Generate structured corruption mask
fn getCorruptionMask(uv: vec2<f32>, time: f32, patternType: f32, intensity: f32) -> u32 {
    var mask = 0u;
    let t = time * 0.5;
    
    // Striped corruption pattern
    let stripe = floor(uv.x * 32.0 + sin(t * 2.0) * 4.0);
    let stripeMask = u32(stripe) % 255u;
    
    // Block corruption pattern
    let blockCoord = floor(uv * vec2<f32>(16.0));
    let blockSeed = hash21(blockCoord + vec2<f32>(floor(t), 0.0));
    let blockMask = u32(blockSeed * 255.0);
    
    // Scanning corruption line
    let scanLine = abs(uv.y - fract(t * 0.2));
    let scanActive = step(scanLine, 0.02);
    let scanMask = select(0u, 0xAAu, scanActive > 0.5);
    
    // Random noise mask
    let noiseVal = hash21(uv * 1000.0 + t);
    let noiseMask = u32(noiseVal * 255.0);
    
    // Select pattern based on type and time
    let patternSelect = fract(patternType * 4.0 + t * 0.1);
    
    if (patternSelect < 0.25) {
        mask = stripeMask;
    } else if (patternSelect < 0.5) {
        mask = blockMask;
    } else if (patternSelect < 0.75) {
        mask = scanMask;
    } else {
        mask = noiseMask;
    }
    
    // Apply intensity
    if (intensity < 0.5) {
        mask = mask & 0x0Fu; // Limit to low bits
    }
    
    return mask;
}

// Apply bitwise corruption to color component
fn corruptByte(b: u32, corruptionType: f32, seed: f32, intensity: f32) -> u32 {
    var result = b;
    let typeIdx = u32(corruptionType * 5.0) % 6u;
    
    switch(typeIdx) {
        case 0u: { // Bit rotation
            let rotAmt = u32(seed * 8.0);
            result = bitRotateRight(b, rotAmt);
        }
        case 1u: { // XOR corruption
            let xorMask = u32(seed * 255.0);
            result = xorCorrupt(b, xorMask);
        }
        case 2u: { // Bit flipping
            let flipProb = intensity * 0.3;
            result = randomBitFlip(b, seed, flipProb);
        }
        case 3u: { // Nibble swap
            result = nibbleSwap(b);
        }
        case 4u: { // Bit reversal
            result = bitReverse(b);
        }
        case 5u: { // Multiple operations
            result = bitRotateLeft(b, 2u);
            result = xorCorrupt(result, u32(seed * 128.0));
        }
        default: {}
    }
    
    return result & 0xFFu;
}

// ───────────────────────────────────────────────────────────────
// Error Propagation
// ───────────────────────────────────────────────────────────────

// Propagate corruption to neighboring pixels
fn propagateError(color: vec3<f32>, uv: vec2<f32>, readTex: texture_2d<f32>, 
                  resolution: vec2<f32>, propagationAmount: f32, time: f32) -> vec3<f32> {
    if (propagationAmount < 0.01) {
        return color;
    }
    
    let texelSize = 1.0 / resolution;
    var corruptedColor = color;
    var errorWeight = 0.0;
    
    // Sample neighbors
    let offsets = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, 0.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.0, -1.0),
        vec2<f32>(0.0, 1.0)
    );
    
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let neighborUV = uv + offsets[i] * texelSize;
        let neighborColor = textureSampleLevel(readTex, u_sampler, neighborUV, 0.0).rgb;
        
        // Check if neighbor is corrupted (deviation from expected)
        let neighborHash = hash21(neighborUV * 500.0 + time);
        if (neighborHash < propagationAmount * 0.3) {
            let weight = 0.25 * propagationAmount;
            corruptedColor = mix(corruptedColor, neighborColor, weight);
            errorWeight = errorWeight + weight;
        }
    }
    
    return corruptedColor;
}

// ───────────────────────────────────────────────────────────────
// Digital Decay
// ───────────────────────────────────────────────────────────────

// Apply bit-depth reduction and decay
fn applyDigitalDecay(color: vec3<f32>, decayRate: f32, time: f32, uv: vec2<f32>) -> vec3<f32> {
    if (decayRate < 0.01) {
        return color;
    }
    
    var decayedColor = color;
    
    // Calculate effective bit depth based on decay rate and position
    let baseBits = 8.0;
    let timeDecay = time * decayRate * 0.5;
    let spatialDecay = hash21(floor(uv * 32.0) + time * 0.1) * decayRate * 2.0;
    let targetBits = max(1.0, baseBits - timeDecay - spatialDecay);
    
    // Apply bit depth reduction to each channel
    for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
        let byteVal = floatToByte(decayedColor[channel]);
        let reduced = reduceBitDepth(byteVal, u32(targetBits));
        decayedColor[channel] = byteToFloat(reduced);
    }
    
    // Posterization artifacts - quantize to fewer levels
    if (decayRate > 0.5) {
        let levels = max(2.0, 16.0 - timeDecay * 2.0);
        decayedColor = floor(decayedColor * levels) / levels;
    }
    
    return decayedColor;
}

// ───────────────────────────────────────────────────────────────
// Main Compute Shader
// ───────────────────────────────────────────────────────────────

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let texelCoord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let corruptionIntensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let bitManipulationType = u.zoom_params.y;
    let errorPropagation = u.zoom_params.z;
    let decayRate = u.zoom_params.w;
    
    // Mouse interaction influence
    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);
    let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);
    let effectiveIntensity = clamp(corruptionIntensity + mouseInfluence * 0.3, 0.0, 1.0);
    
    // ───────────────────────────────────────────────────────────
    // Block Displacement (Original glitch effect)
    // ───────────────────────────────────────────────────────────
    let blockSize = mix(8.0, 64.0, effectiveIntensity);
    let blockCoord = floor(uv * blockSize);
    let blockSeed = hash21(blockCoord + vec2<f32>(time * 0.1, 0.0));
    
    let maxShift = mix(0.0, 0.05, effectiveIntensity);
    let xShift = (blockSeed - 0.5) * maxShift;
    let yShift = (hash21(blockCoord + vec2<f32>(7.0, 3.0) + vec2<f32>(time * 0.07, 0.0)) - 0.5) * maxShift;
    
    var displacedUV = uv + vec2<f32>(xShift, yShift);
    
    // Scanline tearing
    let row = floor(uv.y * blockSize);
    let scanSeed = hash21(vec2<f32>(row, floor(time * 10.0)));
    let tear = step(0.95, scanSeed);
    displacedUV.x += tear * 0.15 * (blockSeed - 0.5) * effectiveIntensity;
    
    // ───────────────────────────────────────────────────────────
    // Sample Base Image
    // ───────────────────────────────────────────────────────────
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    var color = baseColor.rgb;
    
    // ───────────────────────────────────────────────────────────
    // Bitwise Corruption
    // ───────────────────────────────────────────────────────────
    if (effectiveIntensity > 0.01) {
        // Generate per-pixel seed
        let pixelSeed = hash33(vec3<f32>(uv * 1000.0, time));
        let corruptionMask = getCorruptionMask(uv, time, blockSeed, effectiveIntensity);
        
        // Process each color channel
        for (var channel: i32 = 0; channel < 3; channel = channel + 1) {
            var byteVal = floatToByte(color[channel]);
            let channelSeed = hash21(uv + vec2<f32>(f32(channel) * 100.0, time));
            
            // Random bit flips based on intensity
            let flipProb = effectiveIntensity * 0.2 * (1.0 + sin(time * 3.0 + uv.y * 10.0) * 0.3);
            byteVal = randomBitFlip(byteVal, channelSeed, flipProb);
            
            // Structured corruption pattern
            if (blockSeed > (0.7 - effectiveIntensity * 0.4)) {
                let patternIntensity = (blockSeed - 0.7 + effectiveIntensity * 0.4) / (0.3 + effectiveIntensity * 0.4);
                
                // Apply selected corruption type
                let typeVar = bitManipulationType + f32(channel) * 0.1;
                byteVal = corruptByte(byteVal, typeVar, channelSeed, patternIntensity);
                
                // XOR with corruption mask for structured patterns
                if (patternIntensity > 0.5) {
                    byteVal = xorCorrupt(byteVal, corruptionMask);
                }
            }
            
            // Additional temporal corruption (evolving over time)
            let temporalSeed = hash21(uv + vec2<f32>(floor(time * 2.0)));
            if (temporalSeed < effectiveIntensity * 0.15) {
                byteVal = bitRotateRight(byteVal, u32(temporalSeed * 8.0));
            }
            
            color[channel] = byteToFloat(byteVal);
        }
    }
    
    // ───────────────────────────────────────────────────────────
    // Error Propagation
    // ───────────────────────────────────────────────────────────
    color = propagateError(color, displacedUV, readTexture, resolution, errorPropagation, time);
    
    // ───────────────────────────────────────────────────────────
    // Digital Decay
    // ───────────────────────────────────────────────────────────
    color = applyDigitalDecay(color, decayRate, time, uv);
    
    // ───────────────────────────────────────────────────────────
    // Chromatic Aberration (Enhanced)
    // ───────────────────────────────────────────────────────────
    let chromaStrength = effectiveIntensity * 0.03;
    let rOffset = vec2<f32>(chromaStrength * (1.0 + sin(time * 2.0) * 0.5), 0.0);
    let bOffset = vec2<f32>(-chromaStrength * (1.0 + cos(time * 1.5) * 0.5), 0.0);
    
    let rSample = textureSampleLevel(readTexture, u_sampler, displacedUV + rOffset, 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, displacedUV + bOffset, 0.0).b;
    
    color.r = mix(color.r, rSample, 0.5 + effectiveIntensity * 0.3);
    color.b = mix(color.b, bSample, 0.5 + effectiveIntensity * 0.3);
    
    // ───────────────────────────────────────────────────────────
    // Occasional Block Color Inversion (Glitch Effect)
    // ───────────────────────────────────────────────────────────
    let invertSeed = hash21(blockCoord + vec2<f32>(time * 0.5, 100.0));
    if (invertSeed > (0.9 - effectiveIntensity * 0.4)) {
        let invertStrength = (invertSeed - 0.9 + effectiveIntensity * 0.4) / (0.1 + effectiveIntensity * 0.4);
        color = mix(color, 1.0 - color, invertStrength * 0.7);
    }
    
    // ───────────────────────────────────────────────────────────
    // Scanline Artifacts
    // ───────────────────────────────────────────────────────────
    let scanlineY = floor(uv.y * resolution.y);
    let scanlinePattern = step(0.5, fract(scanlineY * 0.5));
    color = mix(color, color * 0.9, scanlinePattern * effectiveIntensity * 0.3);
    
    // ───────────────────────────────────────────────────────────
    // Vignette (to hide edge artifacts)
    // ───────────────────────────────────────────────────────────
    let dist = length(uv - 0.5);
    color *= 1.0 - smoothstep(0.7, 1.0, dist) * 0.5;
    
    // ───────────────────────────────────────────────────────────
    // Output
    // ───────────────────────────────────────────────────────────
    textureStore(writeTexture, texelCoord, vec4<f32>(color, 1.0));
    
    // ───────────────────────────────────────────────────────────
    // Depth Pass-through
    // ───────────────────────────────────────────────────────────
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    
    // ───────────────────────────────────────────────────────────
    // Store Corruption State for Feedback (Temporal Evolution)
    // ───────────────────────────────────────────────────────────
    let corruptionState = vec4<f32>(
        effectiveIntensity,
        blockSeed,
        fract(time * 0.1),
        hash21(uv + time)
    );
    textureStore(dataTextureA, texelCoord, corruptionState);
}
