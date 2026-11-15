// ═══════════════════════════════════════════════════════════════════
//  Spectral Bloom HDR
//  Category: visual-effects
//  Features: crossover, spectral-rendering, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-04-19
//  Upgraded: 2026-11-15
//  Ideas: soft-knee highlight extract; Cauchy-weighted band PSF (§12.2F); energy-conserving core (§12.2F)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Per-channel bloom of a soft-knee extract, plus a Cauchy split of the
//  sharp plate. Crosses spec-prismatic-dispersion and alpha-hdr-bloom-chain.
//  Display is ACES RGBA. The bloom bands are computed, not stored.

#include "_prelude.wgsl"

fn cauchyDispersion(lambda: f32, n0: f32, B: f32) -> f32 {
    return n0 + B / (lambda * lambda);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixel = 1.0 / res;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Mouse acts as a local exposure lamp; bass drives global exposure
    let mousePos = u.zoom_config.yz;
    let mouseGlow = 1.0 - smoothstep(0.0, 0.35, length(uv - mousePos));

    let bloomRadius = mix(2.0, 8.0, u.zoom_params.x);
    let dispersionAmt = mix(0.0, 0.015, u.zoom_params.y) * (1.0 + mids * 0.6);
    let exposure = mix(0.5, 3.0, u.zoom_params.z) * (1.0 + bass * 0.5 + mouseGlow * 0.6);
    let chromaticShift = mix(0.0, 1.0, u.zoom_params.w);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // Spectral wavelengths for RGB (nm). n(λ) is the file's Cauchy.
    let nR = cauchyDispersion(650.0, 1.5, 4000.0);
    let nG = cauchyDispersion(530.0, 1.5, 4000.0);
    let nB = cauchyDispersion(460.0, 1.5, 4000.0);
    // n0 is 1.5, so n(λ) barely moves. The PSF uses that small (n-nG) term,
    // stretched so blue actually spreads wider than red inside this kernel.
    let relR = clamp(1.0 + (nR / max(nG, 1e-4) - 1.0) * 90.0, 0.45, 1.8);
    let relB = clamp(1.0 + (nB / max(nG, 1e-4) - 1.0) * 90.0, 0.45, 1.8);
    
    var bloomR = 0.0;
    var bloomG = 0.0;
    var bloomB = 0.0;
    var bloomL = 0.0;
    var wSumR = 0.0;
    var wSumG = 0.0;
    var wSumB = 0.0;
    var wSumL = 0.0;
    
    let radius = i32(bloomRadius);
    // ── Idea 1: soft-knee extract ──────────────────────────────────
    // Exposure still scales the add. A higher exposure also lowers the
    // knee, so more of the plate is allowed to bloom.
    let knee = mix(0.75, 0.22, u.zoom_params.z);
    let sig = max(bloomRadius * bloomRadius * 0.5, 0.25);
    
    for (var y: i32 = -radius; y <= radius; y = y + 1) {
        for (var x: i32 = -radius; x <= radius; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * pixel;
            let sUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sCol = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
            let sLuma = dot(sCol, vec3<f32>(0.299, 0.587, 0.114));
            
            let dist2 = f32(x * x + y * y);
            // ── Idea 2: Cauchy-weighted band PSF (§12.2F) ──────────
            // Blue (higher n) spreads wider than red. Green is the reference.
            let wR = exp(-dist2 / max(sig * relR, 1e-4));
            let wG = exp(-dist2 / sig);
            let wB = exp(-dist2 / max(sig * relB, 1e-4));
            let eR = max(sCol.r - knee, 0.0);
            let eG = max(sCol.g - knee, 0.0);
            let eB = max(sCol.b - knee, 0.0);
            let eL = max(sLuma - knee, 0.0);
            
            bloomR = bloomR + eR * wR;
            bloomG = bloomG + eG * wG;
            bloomB = bloomB + eB * wB;
            bloomL = bloomL + eL * wG;
            wSumR = wSumR + wR;
            wSumG = wSumG + wG;
            wSumB = wSumB + wB;
            wSumL = wSumL + wG;
        }
    }
    
    bloomR = bloomR / max(wSumR, 1e-4);
    bloomG = bloomG / max(wSumG, 1e-4);
    bloomB = bloomB / max(wSumB, 1e-4);
    bloomL = bloomL / max(wSumL, 1e-4);
    
    let shiftR = (nR - nG) * dispersionAmt * chromaticShift;
    let shiftB = (nB - nG) * dispersionAmt * chromaticShift;
    
    let dispersedR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(shiftR, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let dispersedB = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(shiftB, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let dispersedG = inputColor.g;
    
    let bloomColor = vec3<f32>(bloomR, bloomG, bloomB);
    let dispersedColor = vec3<f32>(dispersedR, dispersedG, dispersedB);
    
    // ── Idea 3: energy-conserving core (§12.2F) ───────────────────
    // The plate gives up light where the extract is strong, then the
    // bloom puts it back. Exposure still scales the returned light.
    let give = clamp(bloomL * 0.85, 0.0, 0.5);
    let hdrBloom = bloomColor * exposure * (1.0 + bloomL * 2.0);
    let finalColor = dispersedColor * (1.0 - give) + hdrBloom * 0.3;
    
    // Bass adds a spectral halo where the source is already hot
    let hot = smoothstep(0.6, 1.0, inputLuma);
    let halo = vec3<f32>(1.0, 0.6, 0.3) * hot * bass * 0.5;
    let outRGB = aces(max(finalColor + halo, vec3<f32>(0.0)));

    // Alpha: bloom energy — the glow layer over the plate
    let alpha = clamp(bloomL * exposure + hot * bass * 0.3, 0.0, 1.0);
    let outColor = vec4<f32>(outRGB, alpha);

    textureStore(writeTexture, global_id.xy, outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
