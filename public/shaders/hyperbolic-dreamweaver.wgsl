// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Dreamweaver
//  Category: geometric (distortion)
//  Features: hyperbolic-geometry, depth-aware, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-11
//  Ideas: angular tiling from tile_count; curved-space chroma + geodesic glow
//  A packing: ACES display RGBA
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let audioReactivity = 1.0 + bass * 0.4;

    let tileCount = mix(3.0, 9.0, u.zoom_params.x);
    let curvature = u.zoom_params.y * 2.0 + 0.5;
    let aberration = u.zoom_params.z;
    let glowIntensity = u.zoom_params.w;

    let centered = (uv - 0.5) * 2.0;
    let r = length(centered);
    let lodFactor = smoothstep(0.5, 0.95, r);
    let edgeThreshold = step(r, 0.99);
    let hyperDist = hyperbolicDist(centered * curvature);
    let t = vec2<f32>(
        cos(time * 0.2 * audioReactivity) * 0.15,
        sin(time * 0.3 * audioReactivity) * 0.15
    );
    let translated = hyperbolicTranslate(centered, t);
    let rotAngle = time * 0.1 * audioReactivity;
    let rotated = rotatePoint(translated, rotAngle, lodFactor);

    let ang = atan2(rotated.y, rotated.x);
    let wrapped = fract(ang / 6.28318 * tileCount) / tileCount * 6.28318;
    let tiled = vec2<f32>(cos(wrapped), sin(wrapped)) * length(rotated);
    let warpedUV = clamp(tiled * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));

    let radial = select(vec2<f32>(0.0), centered / max(r, 0.001), r > 0.001);
    let split = radial * aberration * 0.04 * (1.0 + hyperDist);
    let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), lodFactor * 3.0);
    let sampleG = textureSampleLevel(readTexture, u_sampler, warpedUV, lodFactor * 3.0);
    let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), lodFactor * 3.0);
    let chroma = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);

    let geoRing = abs(sin(hyperDist * 8.0 - time * 1.4));
    let glow = vec3<f32>(0.35, 0.65, 1.0) * geoRing * glowIntensity * 0.22 * (1.0 - lodFactor);

    let peak = max(max(chroma.r, chroma.g), max(chroma.b, 0.001));
    let enhanced = chroma * (1.0 + hyperDist * 0.2 * (1.0 - lodFactor));
    let mapped = aces(enhanced * select(1.0, 1.0 / peak, peak > 1.0) + glow);
    let alpha = calculateAdvancedAlpha(uv, warpedUV, sampleG.a, u.zoom_params);
    let display = mix(vec4<f32>(aces(sampleG.rgb), sampleG.a), vec4<f32>(mapped, alpha), edgeThreshold);

    textureStore(writeTexture, vec2<i32>(global_id.xy), display);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = 1.0 + hyperDist * 0.1 * (1.0 - lodFactor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(clamp(depth * depthMod, 0.0, 1.0), 0.0, 0.0, 0.0));
}
