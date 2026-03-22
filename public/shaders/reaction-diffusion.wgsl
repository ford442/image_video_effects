// ═══════════════════════════════════════════════════════════════════════════════
//  Reaction Diffusion - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Physical Transmittance
//  Features: advanced-alpha, reaction-diffusion, pattern-formation
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

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
}

// Mode 4: Volumetric Alpha for pattern density
fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    
    // Parameters
    let diffusionRate = u.zoom_params.x * 0.1;
    let feedRate = u.zoom_params.y * 0.1;
    let killRate = u.zoom_params.z * 0.1;
    let accumulationRate = u.zoom_params.w;
    
    // Sample current state from dataTextureC
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Sample neighbors for laplacian
    let pixelSize = 1.0 / u.config.zw;
    let left = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0);
    
    // Laplacian
    let laplacian = (left + right + up + down - 4.0 * prev) * 0.25;
    
    // Gray-Scott reaction diffusion
    let a = prev.r;
    let b = prev.g;
    
    let reaction = a * b * b;
    let newA = a + diffusionRate * laplacian.r - reaction + feedRate * (1.0 - a);
    let newB = b + diffusionRate * laplacian.g * 0.5 + reaction - (killRate + feedRate) * b;
    
    let diffused = vec4<f32>(clamp(newA, 0.0, 1.0), clamp(newB, 0.0, 1.0), 0.0, 1.0);
    
    // Color mapping
    let pattern = diffused.r - diffused.g;
    let color = vec3<f32>(
        smoothstep(0.0, 0.5, pattern),
        smoothstep(0.2, 0.6, pattern),
        smoothstep(0.4, 0.8, pattern)
    );
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let density = abs(pattern) * 2.0;
    let newAlpha = volumetricAlpha(density, 1.0);
    
    let accumulated = accumulativeAlpha(
        color,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    textureStore(dataTextureA, coord, vec4<f32>(diffused.rgb, accumulated.a));
    textureStore(writeTexture, global_id.xy, accumulated);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
