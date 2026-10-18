// ═══════════════════════════════════════════════════════════════════
//  aurora-rift-2-pass2 - Aurora Rift 2 Pass 2: Atmospheric Scattering
//  Category: lighting-effects
//  Features: upgraded-rgba, depth-aware, multi-pass-2, atmospheric
//  Upgraded: 2026-10-18
//  Ideas: STEVE mauve arc; nitrogen pink lower border
//  A packing: A echoes volumetric (aurora color, density). Display ACES is writeTexture only.
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
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    let scale = u.zoom_params.x;
    let flow = u.zoom_params.y;
    let octaves = u.zoom_params.w;
    let chromaSpread = octaves * 0.4 + 0.1;
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let rotSpeed = 0.2 + mids * 0.35;

    let srcCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let volumetric = textureLoad(dataTextureC, coord, 0);
    let auroraColor = volumetric.rgb;
    let density = volumetric.a;
    let cover = clamp(density, 0.0, 1.0);

    let warp = vec2<f32>(
        sin(uv.y * 10.0 + time * (0.6 + flow)) * 0.01,
        cos(uv.x * 10.0 + time * (0.6 + flow)) * 0.01
    ) * density;

    let curl = vec2<f32>(
        sin(uv.x * 8.0 + time * 0.5),
        cos(uv.y * 8.0 + time * 0.5)
    ) * 0.01 * density;

    let dispersed = applyChromaticDispersion(uv, warp, curl, density * chromaSpread, texel, readTexture, u_sampler);

    let axis = normalize(srcCol + vec3<f32>(0.15, 0.08, 0.12));
    let angle = time * rotSpeed + density * 3.5;
    let quatCol = quaternionRotate(auroraColor, angle, axis);
    let blended = mix(dispersed, quatCol, clamp(density * 0.75, 0.0, 1.0));

    let historyUV = clamp(uv + warp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let historyPx = clamp(vec2<i32>(historyUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyPx, 0).rgb;
    let flowDir = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let diffused = mix(blended, history, diffusionRate * anisotropy);

    let spectral = spectralPower(diffused, cover);
    let withAtmosphere = atmosphericScattering(spectral, uv, depth, time);
    let graded = colorGrade(withAtmosphere, 1.0);
    var withVignette = applyVignette(graded, uv, 1.0);

    // Idea: STEVE arc — narrow mauve east-west ribbon. Scale sets the width, Flow Speed the drift.
    let steveY = 0.36 + sin(time * (0.06 + flow * 0.18)) * 0.035;
    let steveW = 0.006 + scale * 0.012;
    let steve = exp(-pow((uv.y - steveY) / max(steveW, 0.003), 2.0));
    withVignette += vec3<f32>(0.72, 0.25, 0.58) * steve * (0.42 + mids * 0.35);

    // Idea: nitrogen pink border — 427.8 nm fringe where density meets the lower sky.
    let pink = smoothstep(0.5, 0.82, uv.y) * smoothstep(0.05, 0.28, cover);
    withVignette += vec3<f32>(0.95, 0.28, 0.48) * pink * (0.28 + bass * 0.2);

    let toneMapped = acesToneMapping(max(withVignette, vec3<f32>(0.0)));
    let finalCol = mix(srcCol, toneMapped, 0.3 + cover * 0.7);
    let finalLuma = dot(finalCol, vec3<f32>(0.299, 0.587, 0.114));
    let finalAlpha = clamp(mix(0.5, 0.92, finalLuma) * (0.72 + cover * 0.28) + steve * 0.22 + pink * 0.12, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(auroraColor, density));
    textureStore(writeTexture, coord, vec4<f32>(finalCol, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
