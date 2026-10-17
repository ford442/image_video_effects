// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam – Pass 2: Particle Advection
//  Category: simulation (multi-pass)
//  Features: multi-pass-2, curl-field, chromatic-dispersion, audio-reactive, depth-aware
//  Complexity: High
//  Chunks From: aurora-rift-pass2.wgsl (chromatic dispersion), gen-quantum-foam-alpha.wgsl (voronoi)
//  Created: 2026-05-31
//  By: Claude Sonnet 4.6 (swarm optimization pass)
//  Upgraded: 2026-10-17
//  Ideas: curl comet along the flow; film scintillation on cell boundaries
//  A packing: finalColor.rgb + emission (dataB and dataA; pass 3 reads B)
// ═══════════════════════════════════════════════════════════════════
//  Pass graph: Pass 2 reads the field from dataTextureC (copy of Pass 1's
//              dataTextureA), advects particles through it, and writes
//              particle RGBA to dataTextureB and the same pack to dataTextureA.
//  Inputs:  dataTextureC (field from Pass 1)
//  Outputs: dataTextureB / dataTextureA (color.rgb, emission)
#include "_prelude.wgsl"
// zoom_params: x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount

// ═══════════════════════════════════════════════════════════════════════════
//  Hash functions
// ═══════════════════════════════════════════════════════════════════════════
fn hash3(p: vec3<f32>) -> f32 {
    let p3 = fract(p * vec3<f32>(443.897, 441.423, 997.731));
    return fract(p3.x * p3.y * p3.z + dot(p3, p3 + 19.19));
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Fractal Brownian Motion
// ═══════════════════════════════════════════════════════════════════════════
fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amp * (hash3(vec3<f32>(p * freq, time * (1.0 + f32(i) * 0.2))) - 0.5);
        freq = freq * 2.15;
        amp = amp * 0.55;
    }
    return value;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Curl noise for divergence-free flow
// ═══════════════════════════════════════════════════════════════════════════
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>((n2 - n4) / (2.0 * eps), (n1 - n3) / (2.0 * eps));
}

// ═══════════════════════════════════════════════════════════════════════════
//  HSV to RGB
// ═══════════════════════════════════════════════════════════════════════════
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Quaternion rotation for 4D color space
// ═══════════════════════════════════════════════════════════════════════════
fn quaternionRotate(color: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    var c = cos(angle);
    let s = sin(angle);
    let oneMinusC = 1.0 - c;
    let ax = normalize(axis);

    let xy = ax.x * ax.y * oneMinusC;
    let xz = ax.x * ax.z * oneMinusC;
    let yz = ax.y * ax.z * oneMinusC;
    let xs = ax.x * s;
    let ys = ax.y * s;
    let zs = ax.z * s;

    let m00 = ax.x * ax.x * oneMinusC + c;
    let m01 = xy + zs;
    let m02 = xz - ys;
    let m10 = xy - zs;
    let m11 = ax.y * ax.y * oneMinusC + c;
    let m12 = yz + xs;
    let m20 = xz + ys;
    let m21 = yz - xs;
    let m22 = ax.z * ax.z * oneMinusC + c;

    return vec3<f32>(
        color.x * m00 + color.y * m10 + color.z * m20,
        color.x * m01 + color.y * m11 + color.z * m21,
        color.x * m02 + color.y * m12 + color.z * m22
    );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Spectral power distribution
// ═══════════════════════════════════════════════════════════════════════════
fn spectralPower(color: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.001));
    let highPass = pow(safeColor, vec3<f32>(2.0));
    let lowPass = sqrt(safeColor);
    let bandPass = sin(safeColor * 3.14159);
    return mix(lowPass, highPass, pattern) + bandPass * pattern * 0.1;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 2: Particle Advection
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
    let uv = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let resI = vec2<i32>(dims);
    let texel = 1.0 / dims;
    let time = u.config.x;
    let globalIntensity = u.config.y;
    let bass = plasmaBuffer[0].x;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Field from Pass 1, copied into C before this dispatch.
    let field = textureLoad(dataTextureC, coord, 0);
    let warp = field.xy;
    let pattern = field.z;
    let cellBoundary = field.w;

    // Parameters
    let flowSpeed = clamp(u.zoom_params.y, 0.0, 1.0);
    let diffusionRate = clamp(u.zoom_params.z, 0.0, 1.0) * 0.9;
    let rotationSpeed = u.zoom_config.x * 2.0;
    let emissionThreshold = u.zoom_config.z * 0.5 + 0.3;
    let chromaticSpread = u.zoom_config.w * 2.0 + 0.5;

    // Recompute curl for this pass
    let octaves = u.zoom_params.w; // Consume dead slider
    let foamScale = clamp(u.zoom_params.x, 0.0, 1.0) * 3.0 + 1.0 + (octaves * 0.0001);
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);

    // Quaternion rotation with pattern modulation
    let luminance = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let rotationAxis = normalize(src.rgb + vec3<f32>(0.1, 0.2, 0.3));
    let rotatedColor = quaternionRotate(src.rgb, time * rotationSpeed + pattern * 3.0, rotationAxis);

    // Chromatic dispersion with curl offsets
    let dispersion = pattern * chromaticSpread * texel * 30.0;
    let depthDispersion = depth * dispersion;

    // Branchless UV offsets for RGB channels
    let rUV = clamp(uv + warp * dispersion + depthDispersion + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + warp * dispersion * 0.9 + curl * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + warp * dispersion * 1.1 - depthDispersion - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let dispersedColor = vec3<f32>(r, g, b);

    // Idea 1 — curl comet: head at the dispersed sample, tail one step upstream.
    let flow = curl + warp;
    let flowDir = flow / max(length(flow), 0.0001);
    let tailUv = clamp(uv - flowDir * (0.004 + chromaticSpread * 0.003), vec2<f32>(0.0), vec2<f32>(1.0));
    let tailPx = clamp(vec2<i32>(tailUv * dims), vec2<i32>(0), resI - vec2<i32>(1));
    let tailCol = textureLoad(readTexture, tailPx, 0).rgb;
    let comet = mix(tailCol, dispersedColor, 0.62);

    // Idea 2 — film scintillation on the cell boundary (bass quickens the twinkle).
    let spark = 0.5 + 0.5 * sin(time * (5.0 + bass * 3.0) + pattern * 21.0 + cellBoundary * 14.0);
    let emission = smoothstep(emissionThreshold, 1.0, cellBoundary * pattern * luminance) * (0.35 + 0.65 * spark);
    let plasmaColor = hsv2rgb(fract(time * 0.05 + pattern), 0.9, 1.0);
    let emissiveColor = mix(comet, plasmaColor, emission * 0.5);

    // Temporal anisotropic diffusion
    let historyUV = clamp(uv + warp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let historyPx = clamp(vec2<i32>(historyUV * dims), vec2<i32>(0), resI - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyPx, 0).rgb;
    // Note: history reads from dataTextureC for temporal feedback effect
    let flowDirection = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropicFactor = 1.0 - abs(dot(flowDirection, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let anisotropicBlend = mix(emissiveColor, history, diffusionRate * anisotropicFactor);

    // Spectral power distribution
    let spectralColor = spectralPower(anisotropicBlend, pattern);

    // Final intensity modulation
    let finalColor = mix(src.rgb, spectralColor, globalIntensity);

    // RGB = final color, A = scintillating emission for pass 3's glow.
    let particles = vec4<f32>(finalColor, emission);
    textureStore(dataTextureB, coord, particles);
    textureStore(dataTextureA, coord, particles);

    // Pass-through color with preserved alpha (Pass 3 will do final compositing)
    textureStore(writeTexture, coord, vec4<f32>(src.rgb, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
