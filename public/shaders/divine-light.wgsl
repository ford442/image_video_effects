// ═══════════════════════════════════════════════════════════════════════════════
//  Divine Light - Advanced Alpha with Luminance Key
//  Category: glow/light-effects
//  Alpha Mode: Luminance Key Alpha + Physical Transmittance
//  Features: advanced-alpha, god-rays, volumetric-light
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

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Mode 4: Physical Transmittance (for god ray density)
fn physicalTransmittance(
    baseColor: vec3<f32>,
    opticalDepth: f32,
    absorptionCoeff: vec3<f32>
) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

// Combined alpha for divine light
fn calculateDivineAlpha(
    color: vec3<f32>,
    rayIntensity: f32,
    params: vec4<f32>
) -> f32 {
    // params.y = luminance threshold
    // params.z = softness
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z);
    return clamp(lumaAlpha * rayIntensity, 0.0, 1.0);
}

// Noise function
fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let rayIntensity = u.zoom_params.x * 2.0;
    let lumaThreshold = u.zoom_params.y * 0.3;
    let softness = u.zoom_params.z * 0.25;
    let rayCount = u.zoom_params.w * 20.0 + 5.0;
    
    let lightPos = u.zoom_config.yz;
    
    // Sample base
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Calculate god rays
    let toLight = lightPos - uv;
    let lightAngle = atan2(toLight.y, toLight.x);
    let lightDist = length(toLight);
    
    var rayAccum = 0.0;
    
    // Multiple light rays
    for (var i: i32 = 0; i < i32(rayCount); i++) {
        let fi = f32(i);
        let rayAngle = lightAngle + fi * 0.3 + sin(time * 0.5 + fi) * 0.1;
        let rayDir = vec2<f32>(cos(rayAngle), sin(rayAngle));
        
        // Ray marching
        var pos = uv;
        var rayIntensity = 0.0;
        for (var j: i32 = 0; j < 10; j++) {
            pos += rayDir * 0.02;
            if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) {
                break;
            }
            let n = noise(pos * 5.0 + time * 0.1);
            rayIntensity += n * 0.1 / (1.0 + f32(j) * 0.1);
        }
        
        rayAccum += rayIntensity;
    }
    
    // Divine color (golden-white)
    let divineColor = vec3<f32>(1.0, 0.9, 0.7) * rayAccum * rayIntensity;
    
    // Composite
    let finalColor = baseSample.rgb + divineColor;
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateDivineAlpha(divineColor, rayAccum * rayIntensity, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, max(baseSample.a, alpha)));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
