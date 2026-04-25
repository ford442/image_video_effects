// ═══════════════════════════════════════════════════════════════
//  RGB Glitch Displacement - Digital glitch effect with RGB channel displacement
//  Category: retro-glitch
//  Features: mouse-driven, yuv-chroma-subsampling, wavelength-alpha, audio-reactive
//  Author: Kimi
//
//  FEATURES:
//  - YUV Chroma Subsampling (4:2:0, 4:2:2, 4:1:1 artifacts)
//  - RGB channel displacement with mouse interaction
//  - Block/scanline glitch patterns
//  - Datamoshing-like temporal glitches
//  - DCT block boundary artifacts
//  - Wavelength-dependent alpha physics (Beer-Lambert law)
//  - Audio-reactive glitch intensity and beat flashes
//
//  SCIENTIFIC MODEL:
//  - Dispersion affects both color position AND alpha per channel
//  - alpha = exp(-thickness * absorption_coefficient)
//  - Red (650nm): lowest absorption, highest transmission
//  - Blue (450nm): highest absorption, lowest transmission
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

// ═══════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;
const WAVELENGTH_GREEN:  f32 = 550.0;
const WAVELENGTH_BLUE:   f32 = 450.0;

const ABSORPTION_RED:    f32 = 0.3;
const ABSORPTION_GREEN:  f32 = 0.5;
const ABSORPTION_BLUE:   f32 = 0.8;

// ═══════════════════════════════════════════════════════════════
//  UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════

fn hash1(p: f32) -> f32 {
    return fract(sin(p * 127.1) * 43758.5453);
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn noise1d(p: f32) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let f_smooth = f * f * (3.0 - 2.0 * f);
    return mix(hash1(i), hash1(i + 1.0), f_smooth);
}

// ═══════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA CALCULATION
// ═══════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

// ═══════════════════════════════════════════════════════════════
//  RGB <-> YUV CONVERSION
// ═══════════════════════════════════════════════════════════════

fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
    let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    let u = -0.169 * rgb.r - 0.331 * rgb.g + 0.5 * rgb.b + 0.5;
    let v = 0.5 * rgb.r - 0.419 * rgb.g - 0.081 * rgb.b + 0.5;
    return vec3<f32>(y, u, v);
}

fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
    let y = yuv.x;
    let u = yuv.y - 0.5;
    let v = yuv.z - 0.5;
    let r = y + 1.402 * v;
    let g = y - 0.344 * u - 0.714 * v;
    let b = y + 1.772 * u;
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════
//  CHROMA SUBSAMPLING
// ═══════════════════════════════════════════════════════════════

fn sampleChromaSubsample(uv: vec2<f32>, resolution: vec2<f32>, mode: i32, blockSize: f32) -> vec2<f32> {
    var blockUV = uv;
    switch mode {
        case 1: {
            let blockX = floor(uv.x * resolution.x / blockSize) * blockSize / resolution.x;
            blockUV = vec2<f32>(blockX, uv.y);
        }
        case 2: {
            let blockX = floor(uv.x * resolution.x / blockSize) * blockSize / resolution.x;
            let blockY = floor(uv.y * resolution.y / blockSize) * blockSize / resolution.y;
            blockUV = vec2<f32>(blockX, blockY);
        }
        case 3: {
            let blockX = floor(uv.x * resolution.x / (blockSize * 2.0)) * blockSize * 2.0 / resolution.x;
            blockUV = vec2<f32>(blockX, uv.y);
        }
        default: {
            blockUV = uv;
        }
    }
    let color = textureSampleLevel(readTexture, u_sampler, clamp(blockUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let yuv = rgbToYuv(color);
    return yuv.yz;
}

fn applyChromaSubsampling(uv: vec2<f32>, resolution: vec2<f32>, mode: i32, blockSize: f32, luma: f32) -> vec3<f32> {
    let chroma = sampleChromaSubsample(uv, resolution, mode, blockSize);
    return yuvToRgb(vec3<f32>(luma, chroma.x, chroma.y));
}

// ═══════════════════════════════════════════════════════════════
//  DCT BLOCK ARTIFACTS
// ═══════════════════════════════════════════════════════════════

fn dctBlockArtifacts(uv: vec2<f32>, resolution: vec2<f32>, intensity: f32, blockSize: f32) -> f32 {
    let blockSizePixels = blockSize * 4.0;
    let blockPos = fract(uv * resolution / blockSizePixels);
    let edgeDistX = min(blockPos.x, 1.0 - blockPos.x) * blockSizePixels;
    let edgeDistY = min(blockPos.y, 1.0 - blockPos.y) * blockSizePixels;
    let edgeX = smoothstep(0.0, 1.0, edgeDistX);
    let edgeY = smoothstep(0.0, 1.0, edgeDistY);
    return (1.0 - edgeX * edgeY) * intensity;
}

// ═══════════════════════════════════════════════════════════════
//  TEMPORAL GLITCH (DATAMOSHING)
// ═══════════════════════════════════════════════════════════════

fn temporalGlitch(uv: vec2<f32>, time: f32, intensity: f32, resolution: vec2<f32>) -> vec2<f32> {
    let frameNum = floor(time * 30.0);
    let blockSize = 16.0;
    let blockX = floor(uv.x * resolution.x / blockSize);
    let blockY = floor(uv.y * resolution.y / blockSize);
    let h = hash3(vec3<f32>(blockX, blockY, frameNum));
    if (h > 0.96) {
        let offsetX = (hash1(h) - 0.5) * intensity * 0.3;
        let offsetY = (hash1(h + 1.0) - 0.5) * intensity * 0.1;
        return uv + vec2<f32>(offsetX, offsetY);
    }
    return uv;
}

// ═══════════════════════════════════════════════════════════════
//  GLITCH EFFECT FUNCTIONS
// ═══════════════════════════════════════════════════════════════

fn blockGlitch(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let blockSize = 0.02 + intensity * 0.03;
    let blockUV = floor(uv / blockSize) * blockSize;
    let h = hash3(vec3<f32>(blockUV, floor(time * 10.0)));
    var offset = vec2<f32>(0.0);
    if (h > 0.85) {
        offset.x = (hash1(h) - 0.5) * intensity * 0.3;
    }
    if (h > 0.92) {
        offset.y = (hash1(h + 1.0) - 0.5) * intensity * 0.1;
    }
    return offset;
}

fn scanlineGlitch(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let scanlineY = floor(uv.y * 50.0) / 50.0;
    let h = hash2(vec2<f32>(scanlineY, floor(time * 15.0)));
    if (h > 0.95) {
        return (hash1(h) - 0.5) * intensity * 0.5;
    }
    return 0.0;
}

fn digitalNoise(uv: vec2<f32>, time: f32) -> f32 {
    return hash3(vec3<f32>(uv * 200.0, time * 60.0));
}

fn rgbShift(uv: vec2<f32>, mouse: vec2<f32>, amount: f32) -> vec3<f32> {
    let toMouse = uv - mouse;
    let dist = length(toMouse);
    var angle = atan2(toMouse.y, toMouse.x);
    let shiftDir = vec2<f32>(cos(angle + 1.0), sin(angle + 1.0));
    let shiftAmount = amount * smoothstep(0.5, 0.0, dist);
    let rUV = uv + shiftDir * shiftAmount;
    let gUV = uv;
    let bUV = uv - shiftDir * shiftAmount;
    var r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

fn waveDisplace(uv: vec2<f32>, mouse: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    var dist = length(uv - mouse);
    let wave = sin(dist * 30.0 - time * 8.0) * intensity * 0.05;
    var angle = atan2(uv.y - mouse.y, uv.x - mouse.x);
    let displacement = vec2<f32>(cos(angle), sin(angle)) * wave * smoothstep(0.4, 0.0, dist);
    return uv + displacement;
}

fn pixelSort(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let sortThreshold = 0.7 + intensity * 0.25;
    var h = hash2(vec2<f32>(uv.x, floor(time * 5.0)));
    if (h > sortThreshold) {
        let sortAmount = (hash1(h) - 0.5) * intensity * 0.2;
        return uv + vec2<f32>(0.0, sortAmount);
    }
    return uv;
}

fn datamosh(uv: vec2<f32>, mouse: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    var dist = length(uv - mouse);
    let moshStrength = intensity * smoothstep(0.3, 0.0, dist);
    let blockY = floor(uv.y * 30.0) / 30.0;
    var h = hash2(vec2<f32>(blockY, floor(time * 8.0)));
    if (h > 0.9) {
        let offsetX = (hash1(h) - 0.5) * moshStrength * 0.4;
        return uv + vec2<f32>(offsetX, 0.0);
    }
    return uv;
}

fn chromaticAberration(uv: vec2<f32>, intensity: f32, channelOffset: f32) -> vec3<f32> {
    let offsetR = vec2<f32>(channelOffset * intensity, 0.0);
    let offsetG = vec2<f32>(0.0, 0.0);
    let offsetB = vec2<f32>(-channelOffset * intensity, 0.0);
    var r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offsetR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    var g = textureSampleLevel(readTexture, u_sampler, clamp(uv + offsetG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, clamp(uv + offsetB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

// ═══════════════════════════════════════════════════════════════
//  MAIN ENTRY POINT
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;

    // ═══ AUDIO INPUT ═══
    let audioOverall = u.config.y;
    let audioBass = audioOverall * 1.2;
    let audioPulse = 1.0 + audioBass * 0.5;

    let chromaMode = i32(clamp(u.zoom_params.x * 3.0 + 0.5, 0.0, 3.0));
    let glitchIntensity = u.zoom_params.y * audioPulse;
    let blockSize = mix(2.0, 16.0, u.zoom_params.z);
    let temporalIntensity = u.zoom_params.w * (1.0 + audioOverall * 0.4);

    var p = uv;

    // Apply glitch layers
    p = temporalGlitch(p, time, temporalIntensity, resolution);
    p = waveDisplace(p, mouse, time, glitchIntensity);
    let blockOffset = blockGlitch(p, time, glitchIntensity);
    p = p + blockOffset;
    let scanOffset = scanlineGlitch(p, time, glitchIntensity);
    p.x = p.x + scanOffset;
    p = pixelSort(p, time, glitchIntensity);
    p = datamosh(p, mouse, time, glitchIntensity);

    var baseColor = textureSampleLevel(readTexture, u_sampler, clamp(p, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    var color = baseColor;

    if (chromaMode > 0) {
        let yuv = rgbToYuv(baseColor);
        let luma = yuv.x;
        color = applyChromaSubsampling(p, resolution, chromaMode, blockSize, luma);
        let dctIntensity = dctBlockArtifacts(p, resolution, glitchIntensity * 0.5, blockSize);
        color = mix(color, baseColor, dctIntensity * 0.3);
    }

    let colorShiftAmount = glitchIntensity * 0.05;
    let rgbShifted = rgbShift(p, mouse, colorShiftAmount);
    color = mix(color, rgbShifted, 0.7);

    let chromaticColor = chromaticAberration(p, glitchIntensity, 0.02);
    color = mix(color, chromaticColor, glitchIntensity * 0.5);

    let scanlineDensity = 20.0 + glitchIntensity * 100.0;
    let scanline = sin(uv.y * scanlineDensity + time * 2.0 * (1.0 + audioBass * 0.3));
    let scanlinePattern = 0.9 + 0.1 * scanline;
    color = color * scanlinePattern;

    let noise = digitalNoise(uv, time);
    color = mix(color, vec3<f32>(noise), glitchIntensity * 0.1 * (1.0 + audioOverall));

    let bands = 8.0 + (1.0 - glitchIntensity) * 24.0;
    color = floor(color * bands) / bands;

    let flicker = 1.0 + sin(time * 20.0 * (1.0 + audioBass)) * glitchIntensity * 0.1;
    color = color * flicker;

    let edgeDist = abs(uv.x - 0.5) * 2.0;
    let edgeAberration = edgeDist * glitchIntensity * 0.02;

    var r = textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(edgeAberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    var b = textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(edgeAberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color.r = mix(color.r, r, edgeDist * 0.5);
    color.b = mix(color.b, b, edgeDist * 0.5);

    let barHeight = 0.02;
    let barY = fract(time * 0.3);
    let inBar = step(abs(uv.y - barY), barHeight);

    if (inBar > 0.5 && glitchIntensity > 0.3) {
        let barShift = sin(time * 10.0) * glitchIntensity * 0.1;
        let barColor = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(barShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        color = mix(color, barColor.rgb, 0.5);
    }

    if (chromaMode > 1) {
        let bleedAmount = 0.01 * f32(chromaMode);
        let leftColor = textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(bleedAmount, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let rightColor = textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(bleedAmount, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        color.r = mix(color.r, leftColor.r, glitchIntensity * 0.3);
        color.b = mix(color.b, rightColor.b, glitchIntensity * 0.3);
    }

    let mouseDist = length(uv - mouse);
    let mouseGlow = exp(-mouseDist * 5.0) * glitchIntensity * 0.3;
    color = color + vec3<f32>(0.2, 0.4, 0.8) * mouseGlow;

    let vignetteUV = (uv - 0.5) * 1.5;
    let vignette = 1.0 - dot(vignetteUV, vignetteUV) * 0.4;
    color = color * vignette;

    // Beat flash on strong beats
    let isBeat = step(0.7, audioBass);
    color += vec3<f32>(0.15, 0.12, 0.08) * isBeat * glitchIntensity;

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    // ═══════════════════════════════════════════════════════════════
    let dispersionThickness = glitchIntensity * 3.0 + temporalIntensity * 2.0;

    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);

    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);

    let finalColor = vec3<f32>(
        color.r * alphaR,
        color.g * alphaG,
        color.b * alphaB
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
