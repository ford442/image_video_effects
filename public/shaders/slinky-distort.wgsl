// ═══════════════════════════════════════════════════════════════════════════════
//  Slinky Distort - Advanced Alpha
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha
//  Features: advanced-alpha, spiral-distortion, spring-physics
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
    let displacementAlpha = smoothstep(0.0, 0.08, displacement);
    
    let edgeDist = min(min(originalUV.x, 1.0 - originalUV.x),
                       min(originalUV.y, 1.0 - originalUV.y));
    let edgeFade = smoothstep(0.0, 0.04, edgeDist);
    
    return baseAlpha * mix(0.5, 1.0, displacementAlpha * intensity) * edgeFade;
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.4, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined advanced alpha
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let coils = u.zoom_params.x * 10.0 + 3.0;        // Number of spring coils
    let amplitude = u.zoom_params.y * 0.1;           // Displacement amplitude
    let depthWeight = u.zoom_params.z;               // Depth influence
    let tightness = u.zoom_params.w * 2.0 + 0.5;     // Coil tightness
    
    let mousePos = u.zoom_config.yz;
    
    // Distance from mouse
    let aspect = resolution.x / resolution.y;
    let d = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(d);
    let angle = atan2(d.y, d.x);
    
    // Slinky spiral effect
    let spiralPhase = dist * coils * tightness - time * 2.0;
    let spiralOffset = sin(spiralPhase) * amplitude;
    
    // Create spiral displacement
    let normal = vec2<f32>(cos(angle), sin(angle));
    let tangent = vec2<f32>(-sin(angle), cos(angle));
    
    // Displace along spiral path
    let displacement = normal * spiralOffset * (1.0 - smoothstep(0.0, 0.5, dist));
    
    let warpedUV = clamp(uv + displacement / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Sample with warped coordinates
    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    
    // Apply slinky coloring based on spiral phase
    let colorShift = vec3<f32>(
        0.5 + 0.5 * sin(spiralPhase),
        0.5 + 0.5 * sin(spiralPhase + 2.09),
        0.5 + 0.5 * sin(spiralPhase + 4.18)
    );
    
    let finalColor = mix(sample.rgb, sample.rgb * colorShift, abs(spiralOffset) * 5.0);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateAdvancedAlpha(uv, warpedUV, sample.a, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Depth pass-through with spiral modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
    let depthMod = 1.0 + abs(spiralOffset) * 0.5;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
