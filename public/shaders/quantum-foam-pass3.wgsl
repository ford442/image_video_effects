// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam – Pass 3: Volumetric Rendering & Compositing
//  Category: simulation (multi-pass)
//  Features: multi-pass-3, volumetric, glow, tone-mapping, depth-aware
//  Complexity: High
//  Chunks From: aurora-rift-pass2.wgsl (ACES tone mapping), gen-quantum-foam-alpha.wgsl (glow)
//  Created: 2026-05-31
//  By: Claude Sonnet 4.6 (swarm optimization pass)
//  Upgraded: 2026-10-17
//  Ideas: flow-smear glow along the emission gradient; Beer thickness veil
//  A packing: color only — pass 2 owns the particle pack in A/B
// ═══════════════════════════════════════════════════════════════════
//  Pass graph: Pass 3 reads the particle data from dataTextureC (copy of
//              Pass 2's dataTextureB), applies glow, tone mapping, and
//              color grading, and writes the final image to writeTexture.
//  Inputs:  dataTextureC (particles from Pass 2)
//  Outputs: writeTexture (final color), writeDepthTexture
#include "_prelude.wgsl"
// zoom_params: x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount

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
fn sampleGlow(coord: vec2<i32>, resI: vec2<i32>, emission: f32, flow: vec2<f32>) -> vec3<f32> {
    let rad = max(1, i32(1.0 + emission * 2.0));
    var glowAccum = vec3<f32>(0.0);
    var weightSum = 0.0;

    // 3x3 kernel, shifted along the emission gradient (idea 1).
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let smear = vec2<i32>(
                i32(flow.x * f32(x + 1) * 2.0),
                i32(flow.y * f32(y + 1) * 2.0)
            );
            let samplePx = clamp(coord + vec2<i32>(x, y) * rad + smear, vec2<i32>(0), resI - vec2<i32>(1));
            let weight = 1.0 / (1.0 + length(vec2<f32>(f32(x), f32(y))));
            let sampleData = textureLoad(dataTextureC, samplePx, 0);
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
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
    let uv = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let resI = vec2<i32>(dims);
    let globalIntensity = u.config.y;

    // Particles from Pass 2 (graph copies dataB into C before this dispatch).
    let particleData = textureLoad(dataTextureC, coord, 0);
    let particleColor = particleData.rgb;
    let emission = particleData.a;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let flowSpeed = clamp(u.zoom_params.y, 0.0, 1.0);
    let diffusion = clamp(u.zoom_params.z, 0.0, 1.0);

    if (globalIntensity < 0.01) {
        textureStore(writeTexture, coord, src);
        textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    let pxR = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), resI - vec2<i32>(1)), 0);
    let pxL = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), resI - vec2<i32>(1)), 0);
    let pxU = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), resI - vec2<i32>(1)), 0);
    let pxD = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), resI - vec2<i32>(1)), 0);
    let flow = vec2<f32>(pxR.a - pxL.a, pxU.a - pxD.a);
    let flowDir = flow / max(length(flow), 0.001);
    let glowColor = sampleGlow(coord, resI, emission, flowDir * (0.6 + flowSpeed * 1.8));

    // Idea 2 — Beer veil: transmitted color thins where the surrounding glow is dense.
    let thick = saturate(length(glowColor) * (0.8 + diffusion));
    let transmitted = particleColor * exp(-thick * (0.45 + diffusion * 0.9));
    let withGlow = transmitted + glowColor * (0.45 + flowSpeed * 0.35) * emission;

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
    textureStore(writeTexture, coord, vec4<f32>(finalColor, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
