// ===============================================================
// Aurora Rift – Pass 2: Atmospheric Scattering & Grading
// Applies atmospheric scattering, color grading, and tone mapping
// Inputs: dataTextureA (volumetric data from Pass 1), readTexture (Pass 1 color)
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
    zoom_params: vec4<f32>,       // x=scale, y=flowSpeed, z=diffusionRate, w=fbmOctaves
    zoom_config: vec4<f32>,       // x=rotationSpeed, y=depthParallax, z=emitThresh, w=chromaticSpread
    ripples:     array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Tone mapping
// ═══════════════════════════════════════════════════════════════════════════
fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Quaternion rotation of RGB
// ═══════════════════════════════════════════════════════════════════════════
fn quaternionRotate(col: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    let s = sin(angle * 0.5);
    let c = cos(angle * 0.5);
    let q = vec4<f32>(normalize(axis) * s, c);
    let t = 2.0 * cross(q.xyz, col);
    return col + q.w * t + cross(q.xyz, t);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Spectral power distribution
// ═══════════════════════════════════════════════════════════════════════════
fn spectralPower(col: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeCol = max(col, vec3<f32>(0.001));
    let high = pow(safeCol, vec3<f32>(2.0));
    let low = sqrt(safeCol);
    let band = sin(safeCol * 3.14159);
    return mix(low, high, pattern) + band * pattern * 0.12;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Chromatic dispersion
// ═══════════════════════════════════════════════════════════════════════════
fn applyChromaticDispersion(
    uv: vec2<f32>, 
    warp: vec2<f32>, 
    curl: vec2<f32>,
    dispersion: f32,
    texel: vec2<f32>,
    videoTex: texture_2d<f32>,
    videoSampler: sampler
) -> vec3<f32> {
    let disp = dispersion * texel * 28.0;
    
    let rUV = clamp(uv + warp * disp + curl * 0.018, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + warp * disp * 0.93 + curl * 0.012, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + warp * disp * 1.07 - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    
    let r = textureSampleLevel(videoTex, videoSampler, rUV, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, gUV, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, bUV, 0.0).b;
    
    return vec3<f32>(r, g, b);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Atmospheric scattering approximation
// ═══════════════════════════════════════════════════════════════════════════
fn atmosphericScattering(color: vec3<f32>, uv: vec2<f32>, depth: f32, time: f32) -> vec3<f32> {
    // Sky gradient
    let horizonColor = vec3<f32>(0.05, 0.1, 0.2);
    let zenithColor = vec3<f32>(0.0, 0.02, 0.08);
    let skyGradient = mix(horizonColor, zenithColor, uv.y);
    
    // Atmospheric haze based on depth
    let haze = (1.0 - depth) * 0.15;
    
    // Add subtle aurora glow to atmosphere
    let glowPos = vec2<f32>(0.5 + sin(time * 0.1) * 0.3, 0.3);
    let glowDist = length(uv - glowPos);
    let glow = exp(-glowDist * 3.0) * 0.1;
    let glowColor = vec3<f32>(0.2, 0.8, 0.4) * glow;
    
    return mix(color, skyGradient + glowColor, haze);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Color grading
// ═══════════════════════════════════════════════════════════════════════════
fn colorGrade(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    // Lift shadows
    let lifted = color + vec3<f32>(0.02) * intensity;
    
    // Enhance contrast
    let contrasted = (lifted - 0.5) * (1.0 + 0.1 * intensity) + 0.5;
    
    // Saturation boost
    let luminance = dot(contrasted, vec3<f32>(0.2126, 0.7152, 0.0722));
    let saturated = mix(vec3<f32>(luminance), contrasted, 1.0 + 0.15 * intensity);
    
    return clamp(saturated, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Vignette effect
// ═══════════════════════════════════════════════════════════════════════════
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, intensity: f32) -> vec3<f32> {
    let dist = length(uv - 0.5);
    let vignette = 1.0 - dist * dist * 0.5 * intensity;
    return color * vignette;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 2: Atmospheric Scattering & Grading
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let globalIntensity = 1.0;
    
    // Parameters
    let chromaSpread = u.zoom_config.w * 0.5;
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let rotSpeed = u.zoom_config.x * 1.9 + 0.1;
    
    // Sample source color & depth
    let srcCol = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Read volumetric data from Pass 1 (via dataTextureC)
    let volumetric = textureLoad(dataTextureC, gid.xy, 0);
    let auroraColor = volumetric.rgb;
    let density = volumetric.a;
    
    // Early exit for minimal effect areas
    if (density < 0.001) {
        textureStore(writeTexture, gid.xy, vec4<f32>(srcCol, 1.0));
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }
    
    // Calculate warp from density gradient (simplified)
    let warp = vec2<f32>(
        sin(uv.y * 10.0 + time) * 0.01,
        cos(uv.x * 10.0 + time) * 0.01
    ) * density;
    
    // Curl approximation
    let curl = vec2<f32>(
        sin(uv.x * 8.0 + time * 0.5),
        cos(uv.y * 8.0 + time * 0.5)
    ) * 0.01 * density;
    
    // Chromatic dispersion
    let dispersed = applyChromaticDispersion(uv, warp, curl, density * chromaSpread, texel, videoTex, videoSampler);
    
    // Quaternion rotation of aurora color
    let axis = normalize(srcCol + vec3<f32>(0.12, 0.07, 0.04));
    let angle = time * rotSpeed + density * 3.2;
    let quatCol = quaternionRotate(auroraColor, angle, axis);
    
    // Blend aurora with dispersed source
    let blended = mix(dispersed, quatCol, density * 0.7);
    
    // Anisotropic diffusion (temporal blur)
    let historyUV = clamp(uv + warp * 0.28, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(dataTextureC, videoSampler, historyUV, 0.0).rgb;
    let flowDir = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.28;
    let diffused = mix(blended, history, diffusionRate * anisotropy);
    
    // Spectral power distribution
    let spectral = spectralPower(diffused, density);
    
    // Atmospheric scattering
    let withAtmosphere = atmosphericScattering(spectral, uv, depth, time);
    
    // Color grading
    let graded = colorGrade(withAtmosphere, globalIntensity);
    
    // Apply vignette
    let withVignette = applyVignette(graded, uv, globalIntensity);
    
    // Tone mapping
    let toneMapped = acesToneMapping(withVignette);
    
    // Final intensity blend
    let finalCol = mix(srcCol, toneMapped, globalIntensity);
    
    // Update history buffer (via dataTextureA)
    textureStore(dataTextureA, gid.xy, vec4<f32>(diffused, 1.0));
    
    // Output final color
    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
