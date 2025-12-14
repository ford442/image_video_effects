// ────────────────────────────────────────────────────────────────────────────────
//  Chromatic Crawler - Color Swapping Shader
//  Chaotic color-swapping regions that crawl across the screen, rapidly
//  exchanging colors between different areas with Voronoi-based patterns.
// ────────────────────────────────────────────────────────────────────────────────
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
// ────────────────────────────────────────────────────────────────────────────────

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=regionSize, y=glowAmount, z=colorModSpeed, w=depthInf
  zoom_params: vec4<f32>,       // x=crawlSpeed, y=swapIntensity, z=feedbackMix, w=flashRate
  ripples:     array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────────────────────
//  Hash function for deterministic randomness
// ───────────────────────────────────────────────────────────────────────────────
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.9))
    );
    p3 = fract(sin(p3) * 43758.5453);
    return p3;
}

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Create animated Voronoi regions for color swapping
// ───────────────────────────────────────────────────────────────────────────────
fn voronoiRegions(uv: vec2<f32>, time: f32, regionSize: f32) -> vec2<f32> {
    let grid = vec2<f32>(10.0 + regionSize * 20.0, 8.0 + regionSize * 15.0);
    let id = floor(uv * grid);
    let fuv = fract(uv * grid);
    
    var minDist = 100.0;
    var minPoint = vec2<f32>(0.0);
    
    // Check neighboring cells for closest point
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let pointId = id + neighbor;
            let hashInput = vec3<f32>(pointId.x, pointId.y, time * 0.5);
            let rp = hash3(hashInput);
            let point = neighbor + rp.xy * 0.9;
            let dist = length(point - fuv);
            if (dist < minDist) {
                minDist = dist;
                minPoint = pointId + point / grid;
            }
        }
    }
    
    return minPoint;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Create crawling color swap regions
// ───────────────────────────────────────────────────────────────────────────────
fn createCrawlingRegions(uv: vec2<f32>, time: f32, crawlSpeed: f32) -> vec2<f32> {
    let t = time * crawlSpeed;
    
    // Multiple crawling centers that move around the screen
    let center1 = vec2<f32>(0.5 + sin(t * 0.3) * 0.4, 0.5 + cos(t * 0.2) * 0.4);
    let center2 = vec2<f32>(0.5 + cos(t * 0.4) * 0.3, 0.5 + sin(t * 0.5) * 0.3);
    let center3 = vec2<f32>(0.5 + sin(t * 0.6) * 0.35, 0.5 + cos(t * 0.7) * 0.35);
    
    // Calculate distances to crawling centers
    let d1 = length(uv - center1);
    let d2 = length(uv - center2);
    let d3 = length(uv - center3);
    
    // Create influence zones that crawl across screen
    let influence1 = smoothstep(0.3, 0.1, d1) * sin(t * 10.0 + uv.x * 20.0) * 0.5 + 0.5;
    let influence2 = smoothstep(0.25, 0.05, d2) * cos(t * 8.0 + uv.y * 15.0) * 0.5 + 0.5;
    let influence3 = smoothstep(0.2, 0.08, d3) * sin(t * 12.0 + (uv.x + uv.y) * 10.0) * 0.5 + 0.5;
    
    // Combine influences to create crawling pattern
    let totalInfluence = influence1 + influence2 + influence3;
    
    // Modulate UV based on influences
    let crawlOffset = vec2<f32>(
        sin(totalInfluence * 20.0 + t * 5.0) * 0.08,
        cos(totalInfluence * 15.0 + t * 3.0) * 0.08
    );
    
    return uv + crawlOffset;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Color swapping function with 6 patterns
// ───────────────────────────────────────────────────────────────────────────────
fn swapColors(color: vec3<f32>, region: vec2<f32>, time: f32, intensity: f32) -> vec3<f32> {
    let hash = hash3(vec3<f32>(region.x * 100.0, region.y * 100.0, time * 2.0));
    let swapPattern = u32(hash.x * 6.0);
    
    var result = color;
    
    // Apply different color swaps based on pattern
    if (swapPattern == 0u) { // RGB -> BRG
        result = vec3<f32>(color.b, color.r, color.g);
    } else if (swapPattern == 1u) { // RGB -> GBR
        result = vec3<f32>(color.g, color.b, color.r);
    } else if (swapPattern == 2u) { // Invert RGB
        result = vec3<f32>(1.0) - color;
    } else if (swapPattern == 3u) { // Swap RG, keep B
        result = vec3<f32>(color.g, color.r, color.b);
    } else if (swapPattern == 4u) { // Boost channel
        let channel = u32(hash.y * 3.0);
        if (channel == 0u) {
            result = vec3<f32>(color.r * 2.0, color.g, color.b);
        } else if (channel == 1u) {
            result = vec3<f32>(color.r, color.g * 2.0, color.b);
        } else {
            result = vec3<f32>(color.r, color.g, color.b * 2.0);
        }
    } else { // Desaturate
        let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));
        result = vec3<f32>(gray, gray, gray);
    }
    
    // Blend with original based on intensity
    return mix(color, result, intensity);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Create temporal color modulation
// ───────────────────────────────────────────────────────────────────────────────
fn temporalColorMod(color: vec3<f32>, uv: vec2<f32>, time: f32, speed: f32) -> vec3<f32> {
    let modVec = vec3<f32>(
        sin(time * speed * 2.0 + uv.x * 10.0) * 0.1 + 1.0,
        cos(time * speed * 1.7 + uv.y * 8.0) * 0.1 + 1.0,
        sin(time * speed * 2.3 + (uv.x + uv.y) * 6.0) * 0.1 + 1.0
    );
    return color * modVec;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ───────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;

    // ──────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ──────────────────────────────────────────────────────────────────────────
    let crawlSpeed = u.zoom_params.x * 2.0 + 0.5;           // 0.5 - 2.5
    let swapIntensity = u.zoom_params.y;                     // 0 - 1
    let feedbackMix = u.zoom_params.z * 0.4 + 0.2;          // 0.2 - 0.6
    let flashRate = u.zoom_params.w * 20.0 + 5.0;           // 5 - 25
    let regionSize = u.zoom_config.x;                        // 0 - 1
    let glowAmount = u.zoom_config.y * 0.3;                 // 0 - 0.3
    let colorModSpeed = u.zoom_config.z * 2.0 + 0.5;        // 0.5 - 2.5
    let depthInf = u.zoom_config.w;                          // 0 - 1

    // Sample inputs
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let inputColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;

    // ──────────────────────────────────────────────────────────────────────────
    //  Create crawling regions
    // ──────────────────────────────────────────────────────────────────────────
    let crawledUV = createCrawlingRegions(uv, time, crawlSpeed);
    
    // Get region identifier for color swapping
    let region = voronoiRegions(crawledUV, time, regionSize);
    
    // Depth modulates swap intensity
    let depthModIntensity = swapIntensity * (1.0 - depth * depthInf * 0.5);
    
    // Apply color swapping based on region
    var swappedColor = swapColors(inputColor, region, time, depthModIntensity);

    // ──────────────────────────────────────────────────────────────────────────
    //  Feedback from previous frame
    // ──────────────────────────────────────────────────────────────────────────
    let prevUV = createCrawlingRegions(uv, time - 0.016, crawlSpeed);
    let prevColor = textureSampleLevel(feedbackTex, videoSampler, clamp(prevUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    
    // Animated feedback mixing
    let animatedMix = feedbackMix + sin(time * 3.0 + uv.x * 5.0) * 0.1;
    swappedColor = mix(swappedColor, prevColor, animatedMix);

    // ──────────────────────────────────────────────────────────────────────────
    //  Temporal color modulation
    // ──────────────────────────────────────────────────────────────────────────
    let modulatedColor = temporalColorMod(swappedColor, uv, time, colorModSpeed);

    // ──────────────────────────────────────────────────────────────────────────
    //  Rapid color flashing effect (intensity controlled by glowAmount)
    // ──────────────────────────────────────────────────────────────────────────
    let flash = step(0.95, fract(time * flashRate + region.x * 10.0 + region.y * 7.0));
    let flashColor = vec3<f32>(flash, flash * 0.5, flash * 0.8);
    let flashIntensity = glowAmount * 1.5; // Use glow param for flash too
    var finalColor = mix(modulatedColor, flashColor, flash * flashIntensity);

    // ──────────────────────────────────────────────────────────────────────────
    //  Crawling glow effect
    // ──────────────────────────────────────────────────────────────────────────
    let crawlGlow = length(crawledUV - uv) * 5.0 * glowAmount;
    let glowColor = vec3<f32>(0.8, 0.4, 1.0) * crawlGlow;
    finalColor = finalColor + glowColor;

    // ──────────────────────────────────────────────────────────────────────────
    //  Output
    // ──────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(feedbackOut, gid.xy, vec4<f32>(finalColor, 1.0));
}
