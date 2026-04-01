// ═══════════════════════════════════════════════════════════════════
//  aurora-rift-2-pass2 - Aurora Rift 2 Pass 2: Atmospheric Scattering
//  Category: lighting-effects
//  Features: upgraded-rgba, depth-aware, multi-pass-2, atmospheric
//  Upgraded: 2026-03-22
// ═══════════════════════════════════════════════════════════════════
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
//  Enhanced atmospheric scattering
// ═══════════════════════════════════════════════════════════════════════════
fn atmosphericScattering(color: vec3<f32>, uv: vec2<f32>, depth: f32, time: f32) -> vec3<f32> {
    // Enhanced sky gradient with purple/pink tones
    let horizonColor = vec3<f32>(0.08, 0.06, 0.15);
    let zenithColor = vec3<f32>(0.02, 0.01, 0.1);
    let skyGradient = mix(horizonColor, zenithColor, uv.y);
    
    // Atmospheric haze based on depth
    let haze = (1.0 - depth) * 0.2;
    
    // Enhanced aurora glow
    let glowPos = vec2<f32>(0.5 + sin(time * 0.12) * 0.35, 0.25 + cos(time * 0.08) * 0.1);
    let glowDist = length(uv - glowPos);
    let glow = exp(-glowDist * 2.5) * 0.15;
    let glowColor = vec3<f32>(0.3, 0.9, 0.5) * glow;
    
    // Secondary glow
    let glowPos2 = vec2<f32>(0.3 + cos(time * 0.1) * 0.2, 0.4);
    let glowDist2 = length(uv - glowPos2);
    let glow2 = exp(-glowDist2 * 3.0) * 0.08;
    let glowColor2 = vec3<f32>(0.9, 0.3, 0.7) * glow2;
    
    return mix(color, skyGradient + glowColor + glowColor2, haze);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Enhanced color grading
// ═══════════════════════════════════════════════════════════════════════════
fn colorGrade(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    // Lift shadows with slight color tint
    let lifted = color + vec3<f32>(0.015, 0.01, 0.025) * intensity;
    
    // Enhance contrast
    let contrasted = (lifted - 0.5) * (1.0 + 0.15 * intensity) + 0.5;
    
    // Saturation boost with vibrance
    let luminance = dot(contrasted, vec3<f32>(0.2126, 0.7152, 0.0722));
    let saturation = 1.0 + 0.2 * intensity;
    let saturated = mix(vec3<f32>(luminance), contrasted, saturation);
    
    return clamp(saturated, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Vignette effect
// ═══════════════════════════════════════════════════════════════════════════
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, intensity: f32) -> vec3<f32> {
    let dist = length(uv - 0.5);
    let vignette = 1.0 - dist * dist * 0.6 * intensity;
    return color * vignette;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 2: Enhanced Atmospheric Scattering & Grading
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let globalIntensity = 1.0;
    
    // Enhanced parameters for version 2
    let chromaSpread = u.zoom_config.w * 0.4 + 0.1;
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let rotSpeed = u.zoom_config.x * 2.0 + 0.1;
    
    // Sample source color & depth
    let srcCol = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Read volumetric data from Pass 1 (via dataTextureC)
    let volumetric = textureLoad(dataTextureC, gid.xy, 0);
    let auroraColor = volumetric.rgb;
    let density = volumetric.a;
    
    // Early exit for minimal effect areas
    if (density < 0.001) {
        let luma = dot(srcCol, vec3<f32>(0.299, 0.587, 0.114));
        let alpha = mix(0.7, 1.0, luma);
        let depthAlpha = mix(0.6, 1.0, depth);
        let finalAlpha = (alpha + depthAlpha) * 0.5;
        textureStore(writeTexture, gid.xy, vec4<f32>(srcCol, finalAlpha));
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }
    
    // Calculate warp from density gradient
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
    let axis = normalize(srcCol + vec3<f32>(0.15, 0.08, 0.12));
    let angle = time * rotSpeed + density * 3.5;
    let quatCol = quaternionRotate(auroraColor, angle, axis);
    
    // Enhanced blend with more aurora contribution
    let blended = mix(dispersed, quatCol, density * 0.75);
    
    // Anisotropic diffusion (temporal blur)
    let historyUV = clamp(uv + warp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(dataTextureC, videoSampler, historyUV, 0.0).rgb;
    let flowDir = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let diffused = mix(blended, history, diffusionRate * anisotropy);
    
    // Spectral power distribution
    let spectral = spectralPower(diffused, density);
    
    // Enhanced atmospheric scattering
    let withAtmosphere = atmosphericScattering(spectral, uv, depth, time);
    
    // Enhanced color grading
    let graded = colorGrade(withAtmosphere, globalIntensity);
    
    // Apply vignette
    let withVignette = applyVignette(graded, uv, globalIntensity);
    
    // Tone mapping
    let toneMapped = acesToneMapping(withVignette);
    
    // Final intensity blend
    let finalCol = mix(srcCol, toneMapped, globalIntensity);
    
    // Update history buffer (via dataTextureA)
    textureStore(dataTextureA, gid.xy, vec4<f32>(diffused, 1.0));
    
    // Output final color with luminance-based alpha
    let finalLuma = dot(finalCol, vec3<f32>(0.299, 0.587, 0.114));
    let finalAlpha = mix(0.7, 1.0, finalLuma * (1.0 + density * 0.3));
    let depthAlpha = mix(0.6, 1.0, depth);
    let finalCompositeAlpha = (finalAlpha + depthAlpha) * 0.5;
    
    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol, finalCompositeAlpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
