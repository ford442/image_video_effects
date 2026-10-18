// ═══════════════════════════════════════════════════════════════════
//  Aurora Rift – Pass 2: Atmospheric Scattering & Grading
//  Category: lighting-effects (multi-pass)
//  Features: multi-pass-2, post-processing, ACES, chromatic-dispersion, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-10-18
//  Ideas: airglow limb; Rayleigh reddening
//  A packing: A echoes volumetric (aurora color, density). Display ACES is writeTexture only.
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

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
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let gradeAmt = 1.0;

    let bass = plasmaBuffer[0].x;
    let mid  = plasmaBuffer[0].y;

    let scale = u.zoom_params.x;
    let flow = u.zoom_params.y;
    let octaves = u.zoom_params.w;
    let chromaSpread = octaves * 0.5 * (1.0 + bass * 0.4);
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let rotSpeed = 0.15 + mid * 0.35;

    let srcCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let volumetric = textureLoad(dataTextureC, coord, 0);
    let auroraColor = volumetric.rgb;
    let density = volumetric.a;
    let cover = clamp(density, 0.0, 1.0);

    let warp = vec2<f32>(
        sin(uv.y * 10.0 + time) * 0.01,
        cos(uv.x * 10.0 + time) * 0.01
    ) * density;

    let curl = vec2<f32>(
        sin(uv.x * 8.0 + time * 0.5),
        cos(uv.y * 8.0 + time * 0.5)
    ) * 0.01 * density;

    let dispersed = applyChromaticDispersion(uv, warp, curl, density * chromaSpread, texel, readTexture, u_sampler);

    let axis = normalize(srcCol + vec3<f32>(0.12, 0.07, 0.04));
    let angle = time * rotSpeed + density * 3.2;
    let quatCol = quaternionRotate(auroraColor, angle, axis);

    let blended = mix(dispersed, quatCol, clamp(density * 0.7, 0.0, 1.0));

    let historyUV = clamp(uv + warp * 0.28, vec2<f32>(0.0), vec2<f32>(1.0));
    let historyPx = clamp(vec2<i32>(historyUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyPx, 0).rgb;
    let flowDir = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.28;
    let diffused = mix(blended, history, diffusionRate * anisotropy);

    let spectral = spectralPower(diffused, cover);
    let withAtmosphere = atmosphericScattering(spectral, uv, depth, time);
    let graded = colorGrade(withAtmosphere, gradeAmt);
    var withVignette = applyVignette(graded, uv, gradeAmt);

    // Idea: airglow limb — thin green band, thickness from Scale, drift from Flow Speed.
    let limbY = 0.8 + sin(time * (0.08 + flow * 0.22)) * 0.02;
    let limbW = 0.008 + scale * 0.018;
    let limb = exp(-pow((uv.y - limbY) / max(limbW, 0.004), 2.0));
    withVignette += vec3<f32>(0.12, 0.82, 0.32) * limb * (0.45 + bass * 0.35);

    // Idea: Rayleigh reddening — the long path strips blue; FBM Octaves sets the fine haze.
    let path = smoothstep(0.4, 0.95, uv.y);
    let extinct = vec3<f32>(0.12, 0.4, 0.85) * path * (0.2 + octaves * 0.45);
    withVignette = withVignette * (vec3<f32>(1.0) - extinct);
    let fine = 0.5 + 0.5 * sin(uv.y * (6.0 + octaves * 28.0) + time * 0.15);
    withVignette += vec3<f32>(0.5, 0.22, 0.1) * path * fine * octaves * 0.1;

    let toneMapped = acesToneMapping(max(withVignette, vec3<f32>(0.0)));
    let ign = fract(52.9829189 * fract(dot(vec2<f32>(gid.xy), vec2<f32>(0.06711056, 0.00583715))));
    let dithered = toneMapped + (ign - 0.5) * (1.0 / 255.0);
    let finalCol = mix(srcCol, clamp(dithered, vec3<f32>(0.0), vec3<f32>(1.0)), 0.35 + cover * 0.65);
    let finalAlpha = clamp(0.22 + cover * 0.58 + limb * 0.28, 0.0, 1.0);

    // Volumetric handoff, not the graded picture — pass 1 reads this next frame.
    textureStore(dataTextureA, coord, vec4<f32>(auroraColor, density));
    textureStore(writeTexture, coord, vec4<f32>(finalCol, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
