// ═══════════════════════════════════════════════════════════════
//  VHS Tracking - Full VHS Signal Chain Physics
//  Category: retro-glitch
//  Features: chroma noise modulation, control track dropouts, 
//           azimuth error, tape creases, timebase jitter
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Pseudo-random hash functions
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Simple noise function
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// RGB to YUV conversion (BT.601)
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
    let y = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let u = dot(rgb, vec3<f32>(-0.14713, -0.28886, 0.436));
    let v = dot(rgb, vec3<f32>(0.615, -0.51499, -0.10001));
    return vec3<f32>(y, u, v);
}

// YUV to RGB conversion (BT.601)
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
    let y = yuv.x;
    let u = yuv.y;
    let v = yuv.z;
    let r = y + 1.13983 * v;
    let g = y - 0.39465 * u - 0.58060 * v;
    let b = y + 2.03211 * u;
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters from zoom_params
    let trackingError = u.zoom_params.x;        // Tracking error intensity
    let chromaNoiseAmt = u.zoom_params.y;       // Chroma noise amount
    let dropoutFreq = u.zoom_params.z;          // Dropout frequency
    let azimuthAmt = u.zoom_params.w;           // Azimuth error amount
    
    // Sample original color
    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // ═══════════════════════════════════════════════════════════════
    // 1. TIMEBASE JITTER - Horizontal sync error per scanline
    // ═══════════════════════════════════════════════════════════════
    let scanlineIndex = floor(uv.y * resolution.y);
    let jitterSeed = scanlineIndex * 0.1 + time * 10.0;
    let jitterNoise = hash2(vec2<f32>(jitterSeed, time));
    let timebaseJitter = (jitterNoise - 0.5) * trackingError * 0.02;
    
    // Apply jitter to X coordinate
    let jitteredUV = vec2<f32>(uv.x + timebaseJitter, uv.y);
    
    // ═══════════════════════════════════════════════════════════════
    // 2. YUV COLOR SPACE CONVERSION & CHROMA NOISE
    // VHS has more noise in U/V channels than Y
    // ═══════════════════════════════════════════════════════════════
    let sampledColor = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).rgb;
    var yuv = rgbToYuv(sampledColor);
    
    // Chroma noise modulation - higher frequency for chroma channels
    let chromaNoiseU = noise(uv * 300.0 + vec2<f32>(time * 50.0, 0.0)) - 0.5;
    let chromaNoiseV = noise(uv * 320.0 + vec2<f32>(0.0, time * 45.0)) - 0.5;
    
    // Chroma drift - slow wandering of color channels (like bad tracking)
    let driftFreq = 2.0 + trackingError * 5.0;
    let chromaDrift = sin(uv.y * 100.0 + time * driftFreq) * chromaNoiseAmt * 0.1;
    
    // Apply chroma noise (more to U/V than Y)
    // VHS: Y has ~3-4MHz bandwidth, chroma has ~0.5MHz -> more chroma noise
    let yNoiseAmt = chromaNoiseAmt * 0.1;
    let uvNoiseAmt = chromaNoiseAmt * 0.4;
    
    yuv.x += (noise(uv * 200.0 + time * 60.0) - 0.5) * yNoiseAmt;
    yuv.y += chromaNoiseU * uvNoiseAmt + chromaDrift;
    yuv.z += chromaNoiseV * uvNoiseAmt + chromaDrift * 0.7;
    
    // Convert back to RGB
    var color = yuvToRgb(yuv);
    
    // ═══════════════════════════════════════════════════════════════
    // 3. CONTROL TRACK DROPOUTS - Periodic horizontal band noise
    // From head switching and control track errors
    // ═══════════════════════════════════════════════════════════════
    let dropoutBase = uv.y * 20.0 - time * 2.0;
    let dropoutPhase = fract(dropoutBase);
    let dropoutEnvelope = exp(-dropoutPhase * 10.0); // Sharp attack, exponential decay
    
    // Random dropout positions
    let dropoutRand = hash2(vec2<f32>(floor(dropoutBase), time * 0.5));
    let dropoutActive = step(1.0 - dropoutFreq * 0.3, dropoutRand);
    
    // Create dropout noise band
    let dropoutNoise = (noise(uv * 500.0 + time * 100.0) - 0.5) * dropoutEnvelope * dropoutActive;
    color += dropoutNoise * 0.5;
    
    // Head switching noise (bottom of frame in VHS)
    let headSwitchY = 0.95 + sin(time * 2.0) * 0.02;
    let headSwitchDist = abs(uv.y - headSwitchY);
    let headSwitchBand = smoothstep(0.03, 0.0, headSwitchDist);
    let headSwitchNoise = (hash2(vec2<f32>(uv.x * 100.0, time * 30.0)) - 0.5) * headSwitchBand;
    color += headSwitchNoise * trackingError * 0.3;
    
    // ═══════════════════════════════════════════════════════════════
    // 4. AZIMUTH ERROR - Diagonal noise bars from head misalignment
    // ═══════════════════════════════════════════════════════════════
    let azimuthAngle = 0.15; // Typical VHS azimuth angle
    let diagonalCoord = uv.x * cos(azimuthAngle) + uv.y * sin(azimuthAngle);
    let azimuthPattern = sin(diagonalCoord * 200.0 + time * 10.0);
    
    // Azimuth noise varies by frequency - higher frequencies affected more
    let azimuthNoise = noise(uv * 400.0 + vec2<f32>(diagonalCoord * 10.0, time * 20.0));
    let azimuthMask = smoothstep(0.3, 0.7, azimuthNoise) * azimuthPattern;
    
    // Apply azimuth error with color shift
    let azimuthColorShift = vec3<f32>(
        azimuthMask * azimuthAmt * 0.1,
        azimuthMask * azimuthAmt * 0.05,
        -azimuthMask * azimuthAmt * 0.08
    );
    color += azimuthColorShift;
    
    // ═══════════════════════════════════════════════════════════════
    // 5. TAPE CREASES - Random horizontal line glitches
    // Physical damage causing bright/dark horizontal lines
    // ═══════════════════════════════════════════════════════════════
    let creaseSeed = time * 0.5;
    let creaseRand = hash2(vec2<f32>(floor(creaseSeed), 0.0));
    let creaseY = creaseRand;
    let creaseDist = abs(uv.y - creaseY);
    let creaseWidth = 0.001 + hash2(vec2<f32>(floor(creaseSeed), 1.0)) * 0.003;
    let creaseIntensity = step(0.97, hash2(vec2<f32>(floor(creaseSeed), 2.0))) * trackingError;
    
    let creaseMask = smoothstep(creaseWidth, 0.0, creaseDist);
    let creaseType = step(0.5, hash2(vec2<f32>(floor(creaseSeed), 3.0)));
    let creaseColor = mix(vec3<f32>(-0.3), vec3<f32>(0.3), creaseType);
    color += creaseMask * creaseIntensity * creaseColor;
    
    // Additional micro-creases (tape wear)
    let microCreaseNoise = noise(vec2<f32>(uv.x * 50.0, uv.y * 500.0));
    let microCrease = step(0.97, microCreaseNoise) * trackingError * 0.15;
    color += microCrease;
    
    // ═══════════════════════════════════════════════════════════════
    // 6. VHS COLOR BLEED & EDGE ENHANCEMENT
    // ═══════════════════════════════════════════════════════════════
    // Horizontal smearing (limited chroma bandwidth)
    let smearUV = jitteredUV - vec2<f32>(0.003 + chromaNoiseAmt * 0.005, 0.0);
    let smearColor = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0).rgb;
    let smearYuv = rgbToYuv(smearColor);
    
    // Blend only chroma channels with smeared version
    yuv.y = mix(yuv.y, smearYuv.y, 0.3 + chromaNoiseAmt * 0.4);
    yuv.z = mix(yuv.z, smearYuv.z, 0.3 + chromaNoiseAmt * 0.4);
    color = yuvToRgb(yuv);
    
    // ═══════════════════════════════════════════════════════════════
    // 7. SCANLINES & CRT EFFECTS
    // ═══════════════════════════════════════════════════════════════
    let scanlineFreq = resolution.y * 0.5;
    let scanlinePhase = uv.y * scanlineFreq;
    let scanline = sin(scanlinePhase * 3.14159) * 0.5 + 0.5;
    
    // Scanline intensity varies with brightness (phosphor response)
    let luma = rgbToYuv(color).x;
    let scanlineMod = mix(0.7, 1.0, luma);
    color *= mix(1.0, scanline * scanlineMod, 0.15);
    
    // ═══════════════════════════════════════════════════════════════
    // 8. SYNC PULSE INSTABILITY (vertical hold wobble)
    // ═══════════════════════════════════════════════════════════════
    let syncWobble = sin(time * 3.0) * trackingError * 0.005;
    let syncPoint = 0.1; // Where sync pulse would be
    let inSyncRegion = step(uv.y, syncPoint);
    color *= (1.0 - inSyncRegion * abs(sin(time * 10.0)) * trackingError * 0.5);
    
    // ═══════════════════════════════════════════════════════════════
    // 9. QUANTIZATION & BANDING (VHS has ~240 lines effective)
    // ═══════════════════════════════════════════════════════════════
    let quantizationSteps = 32.0 + (1.0 - chromaNoiseAmt) * 64.0;
    color = floor(color * quantizationSteps) / quantizationSteps;
    
    // ═══════════════════════════════════════════════════════════════
    // 10. FINAL COLOR GRADING - VHS "LOOK"
    // ═══════════════════════════════════════════════════════════════
    // Lift blacks slightly (tape noise floor)
    color = color * 0.92 + 0.05;
    
    // Slight desaturation (generational loss)
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(gray), color, 0.85);
    
    // Clamp to valid range
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
    
    // Output final color
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    
    // Pass through depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
