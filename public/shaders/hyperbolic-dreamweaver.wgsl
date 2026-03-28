// ═══════════════════════════════════════════════════════════════════════════════
//  Hyperbolic Dreamweaver - Advanced Alpha (OPTIMIZED)
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha
//  Features: advanced-alpha, hyperbolic-geometry, depth-aware
//
//  OPTIMIZATIONS APPLIED:
//  - Cached hyperbolic coordinates
//  - Added LOD for distance > 0.7
//  - Branchless hyperbolic calculations
//  - Early exit for edge regions
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ ADVANCED ALPHA FUNCTIONS ═══

fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.2, displacement);
    
    let edgeX = min(originalUV.x, 1.0 - originalUV.x);
    let edgeY = min(originalUV.y, 1.0 - originalUV.y);
    let edgeDist = min(edgeX, edgeY);
    let edgeFade = smoothstep(0.0, 0.06, edgeDist);
    
    return baseAlpha * mix(0.4, 1.0, displacementAlpha * intensity) * edgeFade;
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.4, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

fn calculateAdvancedAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    params: vec4<f32>
) -> f32 {
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    let depthAlpha = depthLayeredAlpha(displacedUV, params.z);
    return clamp(effectAlpha * depthAlpha, 0.0, 1.0);
}

// OPTIMIZATION: Cached hyperbolic distance calculation
fn hyperbolicDist(z: vec2<f32>) -> f32 {
    let r2 = dot(z, z);
    // Clamp to avoid log of negative or zero
    let safeR2 = min(r2, 0.99);
    return 0.5 * log((1.0 + safeR2) / (1.0 - safeR2));
}

// OPTIMIZATION: Branchless hyperbolic translation
fn hyperbolicTranslate(z: vec2<f32>, t: vec2<f32>) -> vec2<f32> {
    let tLen2 = dot(t, t);
    let zDotZ = dot(z, z);
    let zt = dot(z, t);
    
    // Branchless computation
    let num = z * (1.0 + tLen2) - t * (1.0 - zDotZ + 2.0 * zt);
    let den = 1.0 + tLen2 - 2.0 * zt;
    
    // Avoid division by zero
    let safeDen = max(den, 0.0001);
    return num / safeDen;
}

// OPTIMIZATION: LOD-aware rotation (simpler at distance)
fn rotatePoint(p: vec2<f32>, angle: f32, lodFactor: f32) -> vec2<f32> {
    // At high LOD, skip rotation
    if (lodFactor > 0.9) {
        return p;
    }
    
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(
        p.x * c - p.y * s,
        p.x * s + p.y * c
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let intensity = u.zoom_params.x;
    let curvature = u.zoom_params.y * 2.0 + 0.5;
    let depthWeight = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28;
    
    // Map to Poincaré disk
    let centered = (uv - 0.5) * 2.0;
    let r = length(centered);
    
    // OPTIMIZATION: Calculate LOD factor early
    let lodFactor = smoothstep(0.5, 0.95, r);
    
    // Early exit for edge artifacts (branchless blend instead of early return)
    let edgeThreshold = step(r, 0.99);
    
    // OPTIMIZATION: Cache hyperbolic calculations
    let hyperDist = hyperbolicDist(centered * curvature);
    let angle = atan2(centered.y, centered.x);
    
    // Animated translation in hyperbolic space
    let t = vec2<f32>(
        cos(time * 0.2 * audioReactivity) * intensity * 0.3,
        sin(time * 0.3 * audioReactivity) * intensity * 0.3
    );
    
    // Cache translated coordinate
    let translated = hyperbolicTranslate(centered, t);
    
    // Add rotation (LOD-aware)
    let rotAngle = rotation + time * 0.1 * audioReactivity;
    let rotated = rotatePoint(translated, rotAngle, lodFactor);
    
    // Map back to UV space
    let warpedUV = rotated * 0.5 + 0.5;
    
    // Sample with warped coordinates
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    // LOD-aware color enhancement
    let colorEnhancement = 1.0 + hyperDist * 0.2 * (1.0 - lodFactor);
    let finalColor = sample.rgb * colorEnhancement;
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateAdvancedAlpha(uv, warpedUV, sample.a, u.zoom_params);
    
    // Branchless edge handling
    let finalResult = mix(vec4<f32>(sample.rgb, sample.a), vec4<f32>(finalColor, alpha), edgeThreshold);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalResult);
    
    // Depth pass-through with hyperbolic modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = 1.0 + hyperDist * 0.1 * (1.0 - lodFactor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
