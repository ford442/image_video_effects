// ═══════════════════════════════════════════════════════════════════
//  Parallax Glow Compositor (Pass 2 of 2, after volumetric-depth-zoom)
//  Category: interactive-mouse
//  Features: multi-pass, volumetric, depth, composite, audio-reactive, mouse-driven
//  Upgraded: 2026-11-08
//  Ideas: energy-conserving bloom (§12.2F); Cauchy dispersion about the zoom centre (§12.2F); depth-guarded fringe taps
//  A packing: display RGBA on writeTexture only (pass stage — A/B not written, as before)
//  Rescue: sliders now match their saved names (HEAD read x,y as layer speeds of a discarded loop, w as fog, z never); bounds guard; bass-as-uv-offset; flat-depth edge glow.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Idea 2: Cauchy dispersion n(lambda) = A + B / lambda^2 (lambda in um, relative to green).
// Returns per-channel radial scale (<1, 1, >1): blue bends ~1.75x further than red.
fn cauchyScale(B: f32) -> vec3<f32> {
    let lam = vec3<f32>(0.650, 0.550, 0.450);
    let n = vec3<f32>(1.0) + B / (lam * lam);
    return n / n.y;
}

fn luma3(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Hue-preserving soft-knee bright extract: keeps the highlight's tint, drops the sub-threshold part.
fn brightExtract(c: vec3<f32>, thr: f32) -> vec3<f32> {
    let l = luma3(c);
    return c * (max(l - thr, 0.0) / max(l, 0.0001));
}

fn reconstruct_normal(uv_1: vec2<f32>, depth: f32) -> vec3<f32> {
    var resolution_1: vec2<f32>;

    let _e5 = u.config.z;
    let _e9 = u.config.w;
    resolution_1 = vec2<f32>(_e5, _e9);
    let _e14 = resolution_1.x;
    let _e18 = resolution_1.y;
    let offset = vec2<f32>((1.0 / _e14), (1.0 / _e18));
    let _e28 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(offset.x, 0.0)), 0.0);
    let _e37 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(offset.x, 0.0)), 0.0);
    let dx = (_e28.x - _e37.x);
    let _e47 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(0.0, offset.y)), 0.0);
    let _e56 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(0.0, offset.y)), 0.0);
    let dy = (_e47.x - _e56.x);
    let n = vec3<f32>(-(dx), -(dy), 1.0);
    return normalize(n);
}

fn schlickFresnel(cosTheta: f32, F0_: f32) -> f32 {
    return (F0_ + ((1.0 - F0_) * pow((1.0 - cosTheta), 5.0)));
}

fn calculateVolumetricAlpha(layerDepth: f32, fogDensity: f32, viewDotNormal: f32, accumulatedWeight: f32) -> f32 {
    let _e7 = schlickFresnel(max(0.0, viewDotNormal), 0.03);
    let fogAmount = exp(((-(layerDepth) * fogDensity) * 3.0));
    let depthAlpha = mix(0.95, 0.4, fogAmount);
    let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
    let alpha = ((depthAlpha * weightAlpha) * (1.0 - (_e7 * 0.2)));
    return clamp(alpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let center = u.zoom_config.yz; // optical axis = pointer / zoom centre (idle 0.5, 0.5)
    let bass = plasmaBuffer[0].x;

    // Saved slider names (JSON): x glowRadius, y glowIntensity, z aberration, w bloomThreshold.
    let glowRadius = u.zoom_params.x;
    let glowIntensity = u.zoom_params.y;
    let aberration = u.zoom_params.z * (1.0 + bass * 0.5);
    let bloomThreshold = u.zoom_params.w;

    let ps = 1.0 / resolution;
    let lo = vec2<f32>(0.0);
    let hi = vec2<f32>(1.0);
    let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).x;

    // ── Idea 2: Cauchy dispersion (§12.2F) ──────────────────────────────
    // HEAD split R/B symmetrically by +-chroma*depth along x. A lens disperses radially from its
    // axis with a non-linear n(lambda); B scales with the Aberration slider (0.02 -> HEAD's strength
    // at the frame edge). 0.5 floor on the depth scale so a missing depth map keeps the fringe.
    let cs = cauchyScale(aberration * 2.5) - vec3<f32>(1.0);
    let depthScale = 0.5 + baseDepth;
    let v = uv - center;
    let uvR = clamp(center + v * (1.0 + cs.x * depthScale), lo, hi);
    let uvB = clamp(center + v * (1.0 + cs.z * depthScale), lo, hi);
    let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let tapR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let tapB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // ── Idea 3: depth-guarded fringe ────────────────────────────────────
    // A shifted R/B tap that lands on a different depth plane is foreground leaking onto the far
    // plane (or vice versa): fall back to the centre tap there instead of smearing across the edge.
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvR, 0.0).x;
    let dB = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvB, 0.0).x;
    let guardR = 1.0 - smoothstep(0.08, 0.16, abs(dR - baseDepth));
    let guardB = 1.0 - smoothstep(0.08, 0.16, abs(dB - baseDepth));
    let chromaticColor = vec3<f32>(mix(c0.r, tapR, guardR), c0.g, mix(c0.b, tapB, guardB));

    // ── Idea 1: energy-conserving bloom (§12.2F) ────────────────────────
    // Soft-knee extract above Bloom Threshold, 8 golden-angle taps over Glow Radius (px). What the
    // spread carries is taken out of the highlight core by the same fraction, so the glow moves
    // light instead of inventing it; Glow Intensity beyond ~1.8 is deliberate overdrive. Distant
    // pixels scatter a little more (haze).
    let radiusPx = 2.0 + glowRadius * 3.0;
    // Per-pixel rotation (interleaved gradient noise): 8 taps stamp visible discs at a large radius;
    // rotating the pattern per pixel turns that into fine grain. No effect on the mean.
    let jitter = 6.2831853 * fract(52.9829189 * fract(dot(vec2<f32>(gid.xy), vec2<f32>(0.06711056, 0.00583715))));
    var spread = brightExtract(c0.rgb, bloomThreshold);
    let core = spread;
    var wSum = 1.0;
    for (var k: i32 = 0; k < 8; k = k + 1) {
        let fk = f32(k);
        let ang = fk * 2.39996323 + jitter;
        let rr = sqrt((fk + 0.5) / 8.0) * radiusPx;
        let tuv = clamp(uv + vec2<f32>(cos(ang), sin(ang)) * rr * ps, lo, hi);
        let w = 1.0 - 0.6 * (rr / max(radiusPx, 0.0001));
        spread += brightExtract(textureSampleLevel(readTexture, u_sampler, tuv, 0.0).rgb, bloomThreshold) * w;
        wSum += w;
    }
    spread = spread / wSum;
    let scatterGain = glowIntensity * mix(0.8, 1.2, clamp(baseDepth, 0.0, 1.0)) * (1.0 + bass * 0.3);
    let moved = clamp(0.5 * scatterGain, 0.0, 0.9);
    let glowed = max(chromaticColor - core * moved + spread * moved
                     + spread * max(scatterGain - 1.8, 0.0) * 0.5, vec3<f32>(0.0));

    // (HEAD) depth-edge glow, polarity fixed (HEAD's exp(-k*grad) lit FLAT depth, not edges).
    let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).x;
    let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).x;
    let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
    let edgeGlow = (1.0 - exp(-depthGrad * 30.0)) * (0.15 + 0.35 * baseDepth);
    let finalColor = glowed + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

    // (HEAD) depth haze. Density is HEAD's 0.3 (what the old fog slot read at the saved default of
    // the slider that now means Bloom Threshold).
    let fogDensity = 0.3;
    let fog = exp(-baseDepth * fogDensity * 3.0);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outColor = mix(finalColor, fogColor, 1.0 - fog);

    // Alpha is semantic: the incoming pass' coverage carried through the volumetric alpha, lifted
    // where the bloom adds emissive light.
    let viewDotNormal_1 = dot(vec3<f32>(0.0, 0.0, 1.0), reconstruct_normal(uv, baseDepth));
    let volAlpha = calculateVolumetricAlpha(baseDepth, fogDensity, viewDotNormal_1, clamp(c0.a, 0.0, 1.0));
    let alpha = clamp(max(volAlpha, luma3(spread * moved) * 2.0), 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(outColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
