// ═══════════════════════════════════════════════════════════════════════════════
//  Scan Distort - MPEG Compression Artifact Edition
//  CRT-style scanlines + DCT blocking, motion vectors, quantization errors
//  Parameters:
//    x: Block size (4,8,16)
//    y: Quantization level
//    z: Motion vector visibility
//    w: Glitch frequency
// ═══════════════════════════════════════════════════════════════════════════════
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Hash function for noise generation
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

// Quantization - reduce bit depth
fn quantize(color: vec3<f32>, levels: f32) -> vec3<f32> {
    return floor(color * levels) / levels;
}

// DCT block boundary detection
fn blockEdgeFactor(uv: vec2<f32>, blockSize: f32) -> f32 {
    let blockUV = uv * blockSize;
    let fracUV = fract(blockUV);
    // Edge is when we're close to 0 or 1 in block coordinates
    let edgeDist = min(min(fracUV.x, 1.0 - fracUV.x), min(fracUV.y, 1.0 - fracUV.y));
    return smoothstep(0.05, 0.0, edgeDist);
}

// Simulate motion vectors with sine waves
fn getMotionVector(blockIdx: vec2<f32>, time: f32) -> vec2<f32> {
    // Create pseudo-random but coherent motion field
    let freq = 3.0;
    let angle = sin(blockIdx.x * 0.5 + time * 0.5) * cos(blockIdx.y * 0.3 + time * 0.3) * 6.28318;
    let magnitude = 0.5 + 0.5 * sin(blockIdx.x * 0.7 + blockIdx.y * 0.4 + time * 0.8);
    return vec2<f32>(cos(angle), sin(angle)) * magnitude * 0.02;
}

// Color for motion vector visualization
fn motionVectorColor(mv: vec2<f32>, visibility: f32) -> vec3<f32> {
    let angle = atan2(mv.y, mv.x);
    let mag = length(mv);
    
    // Hue based on angle, intensity based on magnitude
    let hue = (angle / 6.28318) + 0.5;
    let sat = mag * 5.0;
    let val = 0.5 + mag * 2.0;
    
    // HSV to RGB
    let c = val * sat * visibility;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = val - c;
    
    var rgb: vec3<f32>;
    if (hue < 0.16667) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (hue < 0.33333) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (hue < 0.5) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (hue < 0.66667) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (hue < 0.83333) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }
    
    return rgb + vec3<f32>(m);
}

// Macroblock error - occasional corrupted blocks
fn macroblockError(uv: vec2<f32>, blockIdx: vec2<f32>, time: f32, glitchFreq: f32) -> vec3<f32> {
    let blockHash = hash2(blockIdx * 0.1);
    let timeHash = hash2(vec2<f32>(floor(time * glitchFreq), 0.0));
    
    if (blockHash < 0.02 && timeHash < 0.3) {
        // Corrupted block - show garbage
        let garble = hash3(vec3<f32>(uv * 50.0, time));
        return vec3<f32>(garble, fract(garble * 1.5), fract(garble * 2.3));
    }
    return vec3<f32>(-1.0); // No error
}

// I-frame glitch - full frame corruption
fn iframeGlitch(uv: vec2<f32>, time: f32, glitchFreq: f32) -> bool {
    let framePeriod = 1.0 / glitchFreq;
    let framePhase = fract(time * glitchFreq);
    let isIframe = framePhase < 0.1; // 10% chance of I-frame "corruption"
    let glitchSeed = hash2(vec2<f32>(floor(time * glitchFreq), 0.0));
    return isIframe && glitchSeed < 0.15;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // ═══════════════════════════════════════════════════════════════════════════
    // Parameters
    // ═══════════════════════════════════════════════════════════════════════════
    let blockSize = 4.0 + u.zoom_params.x * 12.0; // 4 to 16
    let quantLevel = 2.0 + u.zoom_params.y * 62.0; // 2 to 64 levels
    let mvVisibility = u.zoom_params.z;
    let glitchFreq = 0.1 + u.zoom_params.w * 2.0; // 0.1 to 2.1 Hz

    // ═══════════════════════════════════════════════════════════════════════════
    // Original Scan Distort Effect (CRT-style scanlines)
    // ═══════════════════════════════════════════════════════════════════════════
    var mouse = u.zoom_config.yz;
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    let lines = 100.0;
    let bendStr = 0.15;
    let speed = 3.0;

    let push = smoothstep(0.4, 0.0, dist);
    let vOffset = push * bendStr * sin(dist * 20.0 - time * 2.0);
    let scanVal = sin((uv.y + vOffset) * lines - time * speed);
    let scanLine = smoothstep(0.0, 1.0, scanVal);

    let imgUV = uv + vec2<f32>(vOffset * 0.1, vOffset);
    var color = textureSampleLevel(videoTex, videoSampler, imgUV, 0.0).rgb;

    // RGB split on distortion edges
    let r = textureSampleLevel(videoTex, videoSampler, imgUV + vec2<f32>(vOffset * 0.05, 0.0), 0.0).r;
    let b = textureSampleLevel(videoTex, videoSampler, imgUV - vec2<f32>(vOffset * 0.05, 0.0), 0.0).b;
    color = vec3<f32>(r, color.g, b);

    // ═══════════════════════════════════════════════════════════════════════════
    // MPEG Compression Artifacts
    // ═══════════════════════════════════════════════════════════════════════════

    // Block coordinates
    let blockIdx = floor(uv * blockSize);
    let blockCenter = (blockIdx + 0.5) / blockSize;
    
    // ───────────────────────────────────────────────────────────────────────────
    // 1. Quantization - posterize colors
    // ───────────────────────────────────────────────────────────────────────────
    let quantized = quantize(color, quantLevel);
    
    // More aggressive quantization in "high frequency" areas (edges)
    let edgeDetect = abs(color.r - quantized.r) + abs(color.g - quantized.g) + abs(color.b - quantized.b);
    let isEdge = step(0.1, edgeDetect);
    color = mix(quantized, color, isEdge * 0.3);

    // ───────────────────────────────────────────────────────────────────────────
    // 2. DCT Block Boundaries
    // ───────────────────────────────────────────────────────────────────────────
    let edgeFactor = blockEdgeFactor(uv, blockSize);
    
    // Add noise at block edges
    let edgeNoise = hash2(uv * 1000.0 + time) * 0.1;
    color = color * (1.0 - edgeFactor * 0.3) + vec3<f32>(edgeFactor * edgeNoise);
    
    // Highlight block edges with subtle color shift
    let edgeTint = vec3<f32>(1.0, 0.98, 1.02); // Slight purple tint at edges
    color = mix(color, color * edgeTint, edgeFactor * 0.5);

    // ───────────────────────────────────────────────────────────────────────────
    // 3. Motion Vector Visualization
    // ───────────────────────────────────────────────────────────────────────────
    if (mvVisibility > 0.01) {
        let mv = getMotionVector(blockIdx, time);
        let mvColor = motionVectorColor(mv, mvVisibility);
        
        // Arrow pattern within block
        let blockUV = fract(uv * blockSize) - 0.5;
        let arrowDir = normalize(mv + vec2<f32>(0.001));
        let arrowProj = dot(blockUV, arrowDir);
        let arrowPerp = abs(dot(blockUV, vec2<f32>(-arrowDir.y, arrowDir.x)));
        
        // Simple arrow visualization
        let arrowMask = smoothstep(0.3, 0.25, abs(arrowProj - 0.1)) 
                      * smoothstep(0.08, 0.04, arrowPerp + max(0.0, arrowProj * 0.5));
        
        // Arrow head
        let headPos = arrowDir * 0.25;
        let toHead = length(blockUV - headPos);
        let headMask = smoothstep(0.12, 0.08, toHead + arrowPerp * 0.5);
        
        let arrowVis = max(arrowMask, headMask) * mvVisibility;
        color = mix(color, mvColor, arrowVis * 0.7);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // 4. Macroblock Errors
    // ───────────────────────────────────────────────────────────────────────────
    let mbError = macroblockError(uv, blockIdx, time, glitchFreq);
    if (mbError.r >= 0.0) {
        color = mbError;
    }

    // ─────────────────────────────────────────────────────────────────────────══
    // 5. I-Frame Glitch - Full frame corruption
    // ─────────────────────────────────══════════════════════════════════════════
    if (iframeGlitch(uv, time, glitchFreq)) {
        let glitchPattern = hash3(vec3<f32>(uv * 20.0, floor(time * glitchFreq)));
        let shiftUV = uv + vec2<f32>(glitchPattern - 0.5, 0.0) * 0.1;
        let shiftedColor = textureSampleLevel(videoTex, videoSampler, shiftUV, 0.0).rgb;
        color = mix(color, shiftedColor, 0.5) + vec3<f32>(glitchPattern * 0.2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Apply scanline darkening on top
    // ═══════════════════════════════════════════════════════════════════════════
    let finalColor = color * (0.8 + 0.2 * scanLine);

    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
