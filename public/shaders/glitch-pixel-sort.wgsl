// ═══════════════════════════════════════════════════════════════
//  Glitch Pixel Sort - Advanced pixel sorting with threshold masking
//  Category: retro-glitch
//  Features: threshold masking, multi-mode sorting, glitch noise
//  
//  Parameters (zoom_params):
//    x: Threshold (0-1) - brightness threshold for sorting
//    y: Sorting mode (0=horizontal, 1=vertical, 2=angular)
//    z: Glitch amount (0-1) - random sorting breaks
//    w: Iterations (1-8) - smoothing passes
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic
  zoom_params: vec4<f32>,  // x=Threshold, y=Mode, z=Glitch, w=Iterations
  ripples: array<vec4<f32>, 50>,
};

// Hash function for pseudo-random numbers
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(5.3983, 5.4427));
    p2 = p2 + dot(p2.yx, p2.xy + vec2<f32>(21.5351, 14.3137));
    return fract(p2.x * p2.y * 95.4337);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p2 = fract(p * vec3<f32>(5.3983, 5.4427, 5.3987));
    p2 = p2 + dot(p2.yzx, p2.xyz + vec3<f32>(21.5351, 14.3137, 23.5123));
    return fract(p2.x * p2.y * p2.z * 95.4337);
}

// Simplex-like noise for smoother glitch patterns
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// Calculate luminance (perceptual brightness)
fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

// Calculate edge direction using Sobel operator
fn getEdgeDirection(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<f32> {
    let texel = 1.0 / resolution;
    
    // Sample neighboring pixels
    let tl = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb);
    let tm = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb);
    let tr = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, -texel.y), 0.0).rgb);
    let ml = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb);
    let mr = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let bl = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, texel.y), 0.0).rgb);
    let bm = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb);
    let br = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, texel.y), 0.0).rgb);
    
    // Sobel operators
    let gx = tl + 2.0 * ml + bl - tr - 2.0 * mr - br;
    let gy = tl + 2.0 * tm + tr - bl - 2.0 * bm - br;
    
    let dir = vec2<f32>(gx, gy);
    let len = length(dir);
    if (len > 0.0) {
        return dir / len;
    }
    return vec2<f32>(1.0, 0.0);
}

// Pseudo-pixel-sort by sampling along sort direction based on brightness
fn pixelSortSample(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    sortDir: vec2<f32>,
    luma: f32,
    threshold: f32,
    glitchAmount: f32,
    time: f32,
    iteration: f32
) -> vec4<f32> {
    let texel = 1.0 / resolution;
    
    // Calculate sort strength based on how much we exceed threshold
    // Smooth transition at threshold boundary
    let thresholdDelta = luma - threshold;
    let smoothThreshold = smoothstep(0.0, 0.15, thresholdDelta);
    
    // Glitch noise - creates random breaks in sorting
    let noiseScale = 50.0 + glitchAmount * 200.0;
    let timeScale = time * (0.5 + glitchAmount * 2.0);
    let glitchNoise = noise(uv * noiseScale + iteration * 10.0 + timeScale);
    let glitchBreak = step(glitchAmount * 0.7, glitchNoise);
    
    // Adjust effective threshold with glitch variation
    let glitchThreshold = threshold + (glitchNoise - 0.5) * glitchAmount * 0.3;
    let effectiveStrength = smoothstep(0.0, 0.15, luma - glitchThreshold) * glitchBreak;
    
    // Sort distance increases with brightness above threshold
    let maxSortDist = 0.15 + iteration * 0.02;
    let sortDist = effectiveStrength * maxSortDist;
    
    // Sample along sort direction
    // Brighter pixels get pulled further in the sort direction
    let pullFactor = pow(luma, 2.0) * sortDist;
    
var sampleUV = uv - sortDir * pullFactor;
    
    // Add some perpendicular jitter for organic feel
    let perpDir = vec2<f32>(-sortDir.y, sortDir.x);
    let jitter = (glitchNoise - 0.5) * glitchAmount * 0.02 * effectiveStrength;
    sampleUV = sampleUV + perpDir * jitter;
    
    return textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let coord = vec2<i32>(global_id.xy);
    
    // Parameters
    let threshold = clamp(u.zoom_params.x, 0.0, 1.0);
    let sortMode = u.zoom_params.y;           // 0=horizontal, 1=vertical, 2=angular
    let glitchAmount = clamp(u.zoom_params.z, 0.0, 1.0);
    let iterations = max(1.0, min(8.0, u.zoom_params.w));
    
    // Mouse influence (optional - adds directional bias)
    var mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    if (mousePos.x == 0.0 && mousePos.y == 0.0) {
        mousePos = vec2<f32>(0.5, 0.5);
    }
    let mouseDir = normalize(mousePos - vec2<f32>(0.5, 0.5));
    
    // Get base color and luminance
    var baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseLuma = getLuminance(baseColor.rgb);
    
    // Determine sort direction based on mode
    var sortDir: vec2<f32>;
    if (sortMode < 0.5) {
        // Horizontal sorting (left to right, influenced by mouse x)
        sortDir = vec2<f32>(1.0, 0.0);
        if (length(mouseDir) > 0.01) {
            sortDir = normalize(vec2<f32>(sign(mouseDir.x), 0.0));
        }
    } else if (sortMode < 1.5) {
        // Vertical sorting (top to bottom)
        sortDir = vec2<f32>(0.0, 1.0);
        if (length(mouseDir) > 0.01) {
            sortDir = normalize(vec2<f32>(0.0, sign(mouseDir.y)));
        }
    } else {
        // Angular sorting - follow edge direction
        sortDir = getEdgeDirection(uv, resolution);
        // Add time-based rotation for dynamic effect
        let angle = time * 0.1 + noise(uv * 20.0 + time * 0.2) * 3.14159;
        let rot = mat2x2<f32>(cos(angle), -sin(angle), sin(angle), cos(angle));
        sortDir = rot * sortDir;
    }
    
    // Multi-iteration accumulation for smoother flow
    var accumulatedColor = vec4<f32>(0.0);
    var totalWeight = 0.0;
    
    let iterCount = i32(iterations);
    for (var i: i32 = 0; i < iterCount; i = i + 1) {
        let iterF = f32(i);
        
        // Each iteration samples slightly differently
        let iterThreshold = threshold - iterF * 0.02;
        let iterGlitch = glitchAmount * (1.0 + iterF * 0.1);
        
        let sortedColor = pixelSortSample(
            uv, resolution, sortDir,
            baseLuma, iterThreshold, iterGlitch,
            time, iterF
        );
        
        // Weight decreases with iteration for blending
        let weight = 1.0 / (1.0 + iterF * 0.5);
        accumulatedColor = accumulatedColor + sortedColor * weight;
        totalWeight = totalWeight + weight;
    }
    
    var finalColor = accumulatedColor / totalWeight;
    
    // Additional glitch effects
    if (glitchAmount > 0.1) {
        // Random block glitch
        let blockSize = 32.0 + glitchAmount * 64.0;
        let blockUV = floor(uv * resolution / blockSize) * blockSize / resolution;
        let blockNoise = hash3(vec3<f32>(blockUV, floor(time * 10.0)));
        
        if (blockNoise < glitchAmount * 0.15) {
            // Shift block horizontally
            let shiftAmount = (blockNoise - 0.5) * glitchAmount * 0.1;
            finalColor = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(shiftAmount, 0.0), 0.0);
        }
        
        // Scanline glitch
        let scanlineNoise = noise(vec2<f32>(uv.y * 200.0, time * 5.0));
        if (scanlineNoise > 1.0 - glitchAmount * 0.3) {
            let scanShift = (scanlineNoise - 0.5) * glitchAmount * 0.05;
            finalColor = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(scanShift, 0.0), 0.0);
        }
    }
    
    // Chromatic aberration at high glitch/sort areas
    let displacement = abs(baseLuma - threshold);
    if (displacement > 0.2 || glitchAmount > 0.5) {
        let aberrationStrength = 0.003 * (glitchAmount + 0.5);
        let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(aberrationStrength, 0.0), 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(aberrationStrength, 0.0), 0.0).b;
        finalColor = vec4<f32>(r, finalColor.g, b, finalColor.a);
    }
    
    // Threshold-based blending - preserve original in dark areas
    let thresholdMask = smoothstep(threshold - 0.1, threshold + 0.1, baseLuma);
    finalColor = mix(baseColor, finalColor, thresholdMask);
    
    // Output
    textureStore(writeTexture, coord, finalColor);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
