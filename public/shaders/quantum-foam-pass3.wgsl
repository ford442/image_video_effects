// ===============================================================
// Quantum Foam – Pass 3: Volumetric Rendering & Compositing
// Final compositing with glow, tone mapping, and depth integration
// Inputs: dataTextureB (particles from Pass 2)
// Outputs: writeTexture (final color), writeDepthTexture
// ===============================================================
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,       // x=time, y=globalIntensity, z=resX, w=resY
    zoom_params: vec4<f32>,       // x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount
    zoom_config: vec4<f32>,       // x=rotationSpeed, y=depthParallax, z=emissionThreshold, w=chromaticSpread
    ripples:     array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Tone mapping helpers
// ═══════════════════════════════════════════════════════════════════════════
fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn gammaCorrect(color: vec3<f32>, gamma: f32) -> vec3<f32> {
    return pow(color, vec3<f32>(1.0 / gamma));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Glow/bloom approximation (fast box blur)
// ═══════════════════════════════════════════════════════════════════════════
fn sampleGlow(uv: vec2<f32>, emission: f32, dims: vec2<f32>) -> vec3<f32> {
    let texel = 1.0 / dims;
    let glowRadius = 3.0 * emission;
    
    var glowAccum = vec3<f32>(0.0);
    var weightSum = 0.0;
    
    // Simple 3x3 kernel for glow
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel * glowRadius;
            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let weight = 1.0 / (1.0 + length(vec2<f32>(f32(x), f32(y))));
            
            let sampleData = textureSampleLevel(dataTextureC, videoSampler, sampleUV, 0.0);
            glowAccum = glowAccum + sampleData.rgb * sampleData.a * weight;
            weightSum = weightSum + weight;
        }
    }
    
    return glowAccum / max(weightSum, 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Vignette effect
// ═══════════════════════════════════════════════════════════════════════════
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, intensity: f32) -> vec3<f32> {
    let dist = length(uv - 0.5);
    let vignette = 1.0 - dist * dist * intensity;
    return color * max(vignette, 0.0);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Color grading
// ═══════════════════════════════════════════════════════════════════════════
fn colorGrade(color: vec3<f32>, saturation: f32, contrast: f32) -> vec3<f32> {
    let luminance = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    let saturated = mix(vec3<f32>(luminance), color, saturation);
    let contrasted = (saturated - 0.5) * contrast + 0.5;
    return clamp(contrasted, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 3: Final Compositing
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let globalIntensity = u.config.y;
    
    // Read particle data from Pass 2 (via dataTextureC)
    let particleData = textureLoad(dataTextureC, gid.xy, 0);
    let particleColor = particleData.rgb;
    let emission = particleData.a;
    
    // Sample depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Source color for mixing
    let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    
    // Early exit optimization - if minimal effect, pass through source
    if (globalIntensity < 0.01) {
        textureStore(writeTexture, gid.xy, vec4<f32>(srcColor, 1.0));
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }
    
    // Add glow for emissive regions
    let glowColor = sampleGlow(uv, emission, dims);
    let glowIntensity = 0.5;
    let withGlow = particleColor + glowColor * glowIntensity * emission;
    
    // Depth-based atmospheric haze
    let haze = (1.0 - depth) * 0.1;
    let hazeColor = vec3<f32>(0.05, 0.02, 0.08); // Purple-tinted haze
    let withHaze = mix(withGlow, hazeColor, haze * globalIntensity);
    
    // Apply vignette
    let vignetteIntensity = 0.5 * globalIntensity;
    let withVignette = applyVignette(withHaze, uv, vignetteIntensity);
    
    // Color grading
    let saturation = 1.0 + 0.2 * globalIntensity;
    let contrast = 1.0 + 0.1 * globalIntensity;
    let graded = colorGrade(withVignette, saturation, contrast);
    
    // Tone mapping for HDR-like effect
    let toneMapped = acesToneMapping(graded);
    
    // Gamma correction
    let finalColor = gammaCorrect(toneMapped, 2.2);
    
    // Preserve alpha for compositing
    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
