// ═══════════════════════════════════════════════════════════════════════════════
//  Julia Warp - Advanced Alpha
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha
//  Features: advanced-alpha, fractal-distortion, edge-fade
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

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.15, displacement);
    
    // Edge fade to prevent artifacts
    let edgeDist = min(min(originalUV.x, 1.0 - originalUV.x),
                       min(originalUV.y, 1.0 - originalUV.y));
    let edgeFade = smoothstep(0.0, 0.08, edgeDist);
    
    return baseAlpha * mix(0.4, 1.0, displacementAlpha * intensity) * edgeFade;
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Combined advanced alpha
fn calculateAdvancedAlpha(
    color: vec3<f32>,
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    params: vec4<f32>
) -> f32 {
    // params.x = intensity
    // params.z = depth weight
    
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    let depthAlpha = depthLayeredAlpha(color, displacedUV, params.z);
    
    return clamp(effectAlpha * mix(0.85, 1.0, depthAlpha * params.z), 0.0, 1.0);
}

// Complex number operations for Julia set
fn complexMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn complexSqr(z: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y);
}

// Julia set iteration
fn juliaDist(z: vec2<f32>, c: vec2<f32>, maxIter: i32) -> f32 {
    var p = z;
    for (var i: i32 = 0; i < maxIter; i++) {
        p = complexSqr(p) + c;
        if (dot(p, p) > 4.0) {
            return f32(i) / f32(maxIter);
        }
    }
    return 1.0;
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
    let intensity = u.zoom_params.x;        // Warp intensity
    let juliaScale = u.zoom_params.y * 2.0 + 1.0;  // Julia scale
    let depthWeight = u.zoom_params.z;      // Depth influence
    let maxIter = i32(u.zoom_params.w * 50.0 + 20.0);
    
    // Center UV for Julia calculation
    let centered = (uv - 0.5) * juliaScale;
    
    // Animated Julia constant
    let c = vec2<f32>(
        cos(time * 0.3 * audioReactivity) * 0.7,
        sin(time * 0.5 * audioReactivity) * 0.3
    );
    
    // Calculate Julia distortion
    var p = centered;
    var totalDist = 0.0;
    
    for (var i: i32 = 0; i < maxIter; i++) {
        let dist = dot(p, p);
        if (dist > 4.0) {
            break;
        }
        p = complexSqr(p) + c;
        totalDist += 1.0;
    }
    
    // Calculate displacement based on Julia iteration
    let escapeVal = totalDist / f32(maxIter);
    let distortion = vec2<f32>(
        sin(p.y * 3.0) * intensity * 0.1,
        cos(p.x * 3.0) * intensity * 0.1
    );
    
    let warpedUV = clamp(uv + distortion * escapeVal, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Sample with distortion
    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    
    // Apply Julia coloring effect
    let juliaColor = vec3<f32>(
        escapeVal * (0.5 + 0.5 * sin(time + escapeVal * 6.28)),
        escapeVal * (0.5 + 0.5 * sin(time * 0.7 * audioReactivity + escapeVal * 6.28 + 2.0)),
        escapeVal * (0.5 + 0.5 * sin(time * 0.5 * audioReactivity + escapeVal * 6.28 + 4.0))
    );
    
    let finalColor = mix(sample.rgb, juliaColor, escapeVal * 0.3);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateAdvancedAlpha(finalColor, uv, warpedUV, sample.a, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth with distortion modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
    let depthMod = 1.0 + escapeVal * 0.1;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
