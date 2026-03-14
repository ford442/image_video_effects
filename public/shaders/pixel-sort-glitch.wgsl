// ═══════════════════════════════════════════════════════════════════════════════
//  Pixel Sort Glitch - Edge-Aware Threshold Sorting
//  Category: glitch/artistic
//  Features: edge detection, threshold masking, directional sorting (H/V/angular)
//  
//  Creates melting pixel flows along detected edges with threshold-based masking.
//  Pixels above brightness threshold are sorted within a local window along
//  the chosen direction, creating organic glitch patterns.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=Frame/Pass, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Generic
  zoom_params: vec4<f32>,  // x=Threshold, y=Direction, z=WindowSize, w=EdgeInfluence
  ripples: array<vec4<f32>, 50>,
};

// Calculate luminance from RGB
fn luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

// Sobel edge detection
fn detectEdge(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<f32> {
    let texel = 1.0 / resolution;
    
    // Sample 3x3 neighborhood
    let c00 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0);
    let c10 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,     -texel.y), 0.0);
    let c20 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0);
    let c01 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x,  0.0),     0.0);
    let c21 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x,  0.0),     0.0);
    let c02 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0);
    let c12 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,      texel.y), 0.0);
    let c22 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0);
    
    // Sobel kernels for X and Y gradients
    let gx = -1.0 * luminance(c00.rgb) + 1.0 * luminance(c20.rgb) +
             -2.0 * luminance(c01.rgb) + 2.0 * luminance(c21.rgb) +
             -1.0 * luminance(c02.rgb) + 1.0 * luminance(c22.rgb);
    
    let gy = -1.0 * luminance(c00.rgb) + -1.0 * luminance(c20.rgb) +
             -0.0 * luminance(c01.rgb) +  0.0 * luminance(c21.rgb) +
              1.0 * luminance(c02.rgb) +  1.0 * luminance(c22.rgb);
    
    return vec2<f32>(gx, gy);
}

// Get edge magnitude
fn edgeMagnitude(grad: vec2<f32>) -> f32 {
    return length(grad);
}

// Get edge direction (normalized)
fn edgeDirection(grad: vec2<f32>) -> vec2<f32> {
    let mag = length(grad);
    if (mag < 0.001) {
        return vec2<f32>(1.0, 0.0);
    }
    return grad / mag;
}

// Sample with directional offset
fn sampleDirectional(uv: vec2<f32>, direction: vec2<f32>, offset: f32, resolution: vec2<f32>) -> vec3<f32> {
    let sampleUV = uv + direction * offset / resolution;
    return textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).rgb;
}

// Partial sort in a window - returns the "sorted" value based on position in sorted order
fn sortWindow(uv: vec2<f32>, resolution: vec2<f32>, 
              sortDir: vec2<f32>, windowSize: i32,
              currentLuma: f32, currentColor: vec3<f32>) -> vec3<f32> {
    
    // Collect samples along the sort direction
    var samples: array<vec4<f32>, 32>; // xyz=color, w=luma
    var count: i32 = 0;
    
    // Calculate our position in the window
    let halfWindow = windowSize / 2;
    
    // Collect samples
    for (var i: i32 = -halfWindow; i <= halfWindow; i = i + 1) {
        if (count >= 32) { break; }
        
        let offset = f32(i);
        let sampleUV = uv + sortDir * offset / resolution;
        let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).rgb;
        let lum = luminance(col);
        
        samples[count] = vec4<f32>(col, lum);
        count = count + 1;
    }
    
    // Simple bubble sort pass (partial - one pass for performance)
    // In a real sort we'd do multiple passes, but for visual effect one is often enough
    for (var i: i32 = 0; i < count - 1; i = i + 1) {
        if (samples[i].w > samples[i + 1].w) {
            let temp = samples[i];
            samples[i] = samples[i + 1];
            samples[i + 1] = temp;
        }
    }
    
    // Find where our current luminance would fit and interpolate
    var result = currentColor;
    var minDiff: f32 = 1000.0;
    
    for (var i: i32 = 0; i < count; i = i + 1) {
        let diff = abs(samples[i].w - currentLuma);
        if (diff < minDiff) {
            minDiff = diff;
            result = samples[i].rgb;
        }
    }
    
    return result;
}

// Alternative: Flow-based sorting (melting effect)
fn flowSort(uv: vec2<f32>, resolution: vec2<f32>,
            sortDir: vec2<f32>, flowStrength: f32,
            threshold: f32) -> vec3<f32> {
    
    var accum = vec3<f32>(0.0);
    var weight = 0.0;
    
    // Accumulate samples weighted by brightness
    let steps = 8;
    for (var i: i32 = 0; i < steps; i = i + 1) {
        let t = f32(i) / f32(steps - 1);
        let offset = (t - 0.5) * 2.0 * flowStrength;
        
        let sampleUV = uv + sortDir * offset / resolution;
        let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).rgb;
        let lum = luminance(col);
        
        // Weight by how much above threshold
        let w = max(0.0, lum - threshold);
        accum = accum + col * w;
        weight = weight + w;
    }
    
    if (weight > 0.0) {
        return accum / weight;
    }
    return textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;
    
    // ═════════════════════════════════════════════════════════════════
    // PARAMETERS
    // ═════════════════════════════════════════════════════════════════
    let threshold = u.zoom_params.x;           // Brightness threshold (0-1)
    let directionMode = u.zoom_params.y;       // 0=Horizontal, 1=Vertical, 2=Angular
    let windowSize = u.zoom_params.z * 31.0 + 1.0; // Window size 1-32
    let edgeInfluence = u.zoom_params.w;       // How much edges affect direction (0-1)
    
    // Additional control from mouse Y
    let mouseThreshold = u.zoom_config.z;
    let effectiveThreshold = clamp(threshold * 0.7 + mouseThreshold * 0.3, 0.0, 1.0);
    
    // Sample current pixel
    let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let currentLuma = luminance(currentColor);
    
    // ═════════════════════════════════════════════════════════════════
    // EDGE DETECTION
    // ═════════════════════════════════════════════════════════════════
    let edgeGrad = detectEdge(uv, resolution);
    let edgeMag = edgeMagnitude(edgeGrad);
    let edgeDir = edgeDirection(edgeGrad);
    
    // ═════════════════════════════════════════════════════════════════
    // DIRECTION SELECTION
    // ═════════════════════════════════════════════════════════════════
    var sortDir: vec2<f32>;
    
    if (directionMode < 0.33) {
        // Horizontal
        sortDir = vec2<f32>(1.0, 0.0);
    } else if (directionMode < 0.66) {
        // Vertical
        sortDir = vec2<f32>(0.0, 1.0);
    } else {
        // Angular - follow edges
        sortDir = mix(vec2<f32>(1.0, 0.0), edgeDir, edgeInfluence);
    }
    
    // Normalize sort direction
    sortDir = normalize(sortDir);
    
    // ═════════════════════════════════════════════════════════════════
    // THRESHOLD MASKING
    // ═════════════════════════════════════════════════════════════════
    let mask = currentLuma > effectiveThreshold;
    
    // Optional: Smooth mask edges
    let maskSmooth = smoothstep(effectiveThreshold - 0.1, effectiveThreshold + 0.1, currentLuma);
    
    // ═════════════════════════════════════════════════════════════════
    // PIXEL SORTING
    // ═════════════════════════════════════════════════════════════════
    var outputColor: vec3<f32>;
    
    if (mask) {
        // Apply sorting effect
        let iWindowSize = i32(clamp(windowSize, 1.0, 32.0));
        
        // Choose sorting mode based on luminance
        // Brighter pixels flow more (melting effect)
        let flowStrength = (currentLuma - effectiveThreshold) / (1.0 - effectiveThreshold + 0.001);
        
        if (flowStrength > 0.5 && edgeInfluence > 0.5) {
            // Flow/melt mode for bright areas with edge influence
            outputColor = flowSort(uv, resolution, sortDir, flowStrength * 50.0, effectiveThreshold);
        } else {
            // Standard window sort
            outputColor = sortWindow(uv, resolution, sortDir, iWindowSize, currentLuma, currentColor);
        }
        
        // Blend based on mask and add some noise for glitch effect
        let noise = fract(sin(dot(uv * currentTime, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        let glitchAmount = (currentLuma - effectiveThreshold) * 0.1 * noise;
        
        outputColor = mix(currentColor, outputColor, maskSmooth);
        outputColor = outputColor + vec3<f32>(glitchAmount * 0.2);
        
    } else {
        // Below threshold - keep original (protected darks)
        outputColor = currentColor;
    }
    
    // ═════════════════════════════════════════════════════════════════
    // EDGE HIGHLIGHT (optional visual enhancement)
    // ═════════════════════════════════════════════════════════════════
    let edgeHighlight = edgeMag * edgeInfluence * 0.5;
    outputColor = outputColor + vec3<f32>(edgeHighlight * 0.1);
    
    // ═════════════════════════════════════════════════════════════════
    // OUTPUT
    // ═════════════════════════════════════════════════════════════════
    let finalColor = vec4<f32>(clamp(outputColor, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    
    // Store edge data for potential multi-pass use
    let edgeData = vec4<f32>(edgeDir * 0.5 + 0.5, edgeMag, maskSmooth);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), edgeData);
}
