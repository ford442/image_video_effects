// ═══════════════════════════════════════════════════════════════════
//  Tensor Flow Sculpt
//  Category: distortion
//  Features: depth-aware, tensor-warp, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: 1) tensor streamlines (coherence-weighted LIC grain along depth contours) 2) dome/saddle sheen from sign of Gaussian curvature 3) clay creep (exact-C history drifts along the sculpt + downhill)
//  A packing: ACES display RGBA (C read back as display history, mixed post-ACES)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=SculptDepth, y=FreqSeparation, z=CurvatureScale, w=AnimSpeed

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ─────────────────────────────────────────────────────────────────────────────
//  Hash
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sample depth at offset
// ─────────────────────────────────────────────────────────────────────────────
fn sampleDepth(uv: vec2<f32>) -> f32 {
    return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compute structure tensor (2x2 matrix) from depth gradients
//  The structure tensor captures local orientation and anisotropy
//  T = [[Ix*Ix, Ix*Iy], [Ix*Iy, Iy*Iy]]  averaged over neighborhood
// ─────────────────────────────────────────────────────────────────────────────
fn structureTensor(uv: vec2<f32>, texel: vec2<f32>, radius: f32) -> mat2x2<f32> {
    var Txx = 0.0;
    var Txy = 0.0;
    var Tyy = 0.0;

    // Floor: 5×5 strided taps (was 7×7 = 196 depth reads) over the same ±6 px
    // footprint. HEAD's Gaussian was evaluated in UV units (w ≈ 1 everywhere),
    // so a near-box weight in pixel units keeps the same response.
    let steps = 2;
    let step = radius * 1.5 * texel;
    let gaussDenom = 2.0 * 6.0 * 6.0;

    for (var dy = -steps; dy <= steps; dy++) {
        for (var dx = -steps; dx <= steps; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * step;
            let pos = uv + offset;

            // Central differences for gradient
            let gx = sampleDepth(pos + vec2<f32>(texel.x, 0.0)) - sampleDepth(pos - vec2<f32>(texel.x, 0.0));
            let gy = sampleDepth(pos + vec2<f32>(0.0, texel.y)) - sampleDepth(pos - vec2<f32>(0.0, texel.y));

            // Gaussian weight
            let offPx = vec2<f32>(f32(dx), f32(dy)) * radius * 1.5;
            let w = exp(-dot(offPx, offPx) / gaussDenom);

            Txx += gx * gx * w;
            Txy += gx * gy * w;
            Tyy += gy * gy * w;
        }
    }

    let norm = 1.0 / f32((2 * steps + 1) * (2 * steps + 1));
    return mat2x2<f32>(Txx * norm, Txy * norm, Txy * norm, Tyy * norm);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Extract eigenvalues and eigenvectors from 2x2 symmetric matrix
//  λ1 = principal curvature direction, λ2 = secondary
// ─────────────────────────────────────────────────────────────────────────────
fn eigenDecomp(T: mat2x2<f32>) -> vec4<f32> {
    let a = T[0][0];
    let b = T[0][1];
    let d = T[1][1];

    let trace = a + d;
    let det = a * d - b * b;
    let disc = sqrt(max(trace * trace * 0.25 - det, 0.0));

    let lambda1 = trace * 0.5 + disc;
    let lambda2 = trace * 0.5 - disc;

    // Principal eigenvector
    var ev = vec2<f32>(b, lambda1 - a);
    if (length(ev) < 1e-6) { ev = vec2<f32>(1.0, 0.0); }
    ev = normalize(ev);

    return vec4<f32>(ev.x, ev.y, lambda1, lambda2);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Depth Hessian: second derivatives for curvature
// ─────────────────────────────────────────────────────────────────────────────
fn depthHessian(uv: vec2<f32>, texel: vec2<f32>) -> vec3<f32> {
    let c = sampleDepth(uv);
    let dxx = sampleDepth(uv + vec2<f32>(texel.x * 2.0, 0.0)) + sampleDepth(uv - vec2<f32>(texel.x * 2.0, 0.0)) - 2.0 * c;
    let dyy = sampleDepth(uv + vec2<f32>(0.0, texel.y * 2.0)) + sampleDepth(uv - vec2<f32>(0.0, texel.y * 2.0)) - 2.0 * c;
    let dxy = (sampleDepth(uv + texel) - sampleDepth(uv + vec2<f32>(texel.x, -texel.y))
              - sampleDepth(uv + vec2<f32>(-texel.x, texel.y)) + sampleDepth(uv - texel)) * 0.25;
    return vec3<f32>(dxx, dyy, dxy);
}

// Central depth gradient over ±2 px (for the dome normal and downhill creep).
fn depthGrad(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let gx = sampleDepth(uv + vec2<f32>(texel.x * 2.0, 0.0)) - sampleDepth(uv - vec2<f32>(texel.x * 2.0, 0.0));
    let gy = sampleDepth(uv + vec2<f32>(0.0, texel.y * 2.0)) - sampleDepth(uv - vec2<f32>(0.0, texel.y * 2.0));
    return vec2<f32>(gx, gy) * 0.25;
}

// Exact bilinear history read (4× textureLoad, no sampler on rgba32float C).
fn loadHistoryBilinear(pos: vec2<f32>, dims: vec2<f32>) -> vec3<f32> {
    let maxP = vec2<i32>(dims) - vec2<i32>(1);
    let p0f = floor(pos - 0.5);
    let f = pos - 0.5 - p0f;
    let p0 = clamp(vec2<i32>(p0f), vec2<i32>(0), maxP);
    let p1 = clamp(vec2<i32>(p0f) + vec2<i32>(1), vec2<i32>(0), maxP);
    let a = textureLoad(dataTextureC, vec2<i32>(p0.x, p0.y), 0).rgb;
    let b = textureLoad(dataTextureC, vec2<i32>(p1.x, p0.y), 0).rgb;
    let c = textureLoad(dataTextureC, vec2<i32>(p0.x, p1.y), 0).rgb;
    let d = textureLoad(dataTextureC, vec2<i32>(p1.x, p1.y), 0).rgb;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gaussian blur approximation for frequency separation
// ─────────────────────────────────────────────────────────────────────────────
fn blurSample(uv: vec2<f32>, texel: vec2<f32>, radius: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var total = 0.0;
    let denom = radius * 0.5 + 0.1;
    for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * texel * radius;
            let w = exp(-f32(dx * dx + dy * dy) / denom);
            col += textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * w;
            total += w;
        }
    }
    return col / total;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = (fragCoord + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let sculptDepth = (u.zoom_params.x * 0.08 + 0.005) * (1.0 + bass * 0.4);
    let freqSep = u.zoom_params.y * 8.0 + 1.0;
    let curvatureScale = u.zoom_params.z * 5.0 + 0.5;
    let animSpeed = u.zoom_params.w * 2.0 + 0.2;
    // Floor: HEAD read flowStr from zoom_config.x (= TIME → unbounded growth) and
    // persistence from mouse-down. Both frozen at their t≈0 / mouse-up values.
    let flowStr = 0.3;
    let persistence = 0.6;

    // ─────────────────────────────────────────────────────────────────────────
    //  Compute structure tensor and extract principal directions
    // ─────────────────────────────────────────────────────────────────────────
    let depth = sampleDepth(uv);
    let T = structureTensor(uv, texel, 2.0);
    let eigen = eigenDecomp(T);
    let principalDir = vec2<f32>(eigen.x, eigen.y);
    let perpDir = vec2<f32>(-eigen.y, eigen.x);
    let anisotropy = (eigen.z - eigen.w) / (eigen.z + eigen.w + 1e-6);

    // ─────────────────────────────────────────────────────────────────────────
    //  Depth Hessian → mean curvature for "sculpting" force
    // ─────────────────────────────────────────────────────────────────────────
    let hess = depthHessian(uv, texel);
    let meanCurvature = (hess.x + hess.y) * 0.5 * curvatureScale;
    let gaussCurvature = (hess.x * hess.y - hess.z * hess.z) * curvatureScale;

    // ─────────────────────────────────────────────────────────────────────────
    //  Geodesic flow: displace along principal curvature directions
    //  Animated with time so the "clay" appears to flow
    // ─────────────────────────────────────────────────────────────────────────
    let flowPhase = sin(time * animSpeed + depth * 10.0);
    let geodesicDisp = principalDir * meanCurvature * sculptDepth * flowStr * flowPhase
                     + perpDir * gaussCurvature * sculptDepth * 0.5 * cos(time * animSpeed * 0.7);

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: local sculpting force
    // ─────────────────────────────────────────────────────────────────────────
    var rippleForce = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let dist = distance(uv, r.xy);
        let age = time - r.z;
        if (age > 0.0 && age < 5.0) {
            let wave = sin(dist * 20.0 - age * 3.0) * exp(-dist * 4.0) * exp(-age * 0.5);
            rippleForce += normalize(uv - r.xy + vec2<f32>(0.0001)) * wave * sculptDepth * 2.0;
        }
    }

    let totalDisp = geodesicDisp + rippleForce;

    // ─────────────────────────────────────────────────────────────────────────
    //  Frequency separation: warp low frequencies, preserve high
    // ─────────────────────────────────────────────────────────────────────────
    let warpedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

    // Low frequency (bulk shape) — this gets warped
    let lowFreqWarped = blurSample(warpedUV, texel, freqSep);

    // High frequency (detail) — stays anchored to original position
    let lowFreqOriginal = blurSample(uv, texel, freqSep);
    let srcColorFull = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let srcColor = srcColorFull.rgb;
    var highFreq = srcColor - lowFreqOriginal;

    // Idea 1: tensor streamlines — a short line-integral (LIC) of the source
    // along perpDir (the depth-contour tangent). Where the tensor is coherent,
    // the anchored detail layer is replaced by its streamline average, so the
    // clay's grain is combed along the depth contours. Flat depth → no change.
    let coherence = clamp(anisotropy, 0.0, 1.0) * smoothstep(2e-6, 5e-5, eigen.z);
    if (coherence > 0.01) {
        let licStep = perpDir * texel * (1.0 + freqSep * 0.25);
        var lic = srcColor;
        lic += textureSampleLevel(readTexture, u_sampler, clamp(uv + licStep * 1.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        lic += textureSampleLevel(readTexture, u_sampler, clamp(uv - licStep * 1.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        lic += textureSampleLevel(readTexture, u_sampler, clamp(uv + licStep * 3.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        lic += textureSampleLevel(readTexture, u_sampler, clamp(uv - licStep * 3.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let licHigh = lic * 0.2 - lowFreqOriginal;
        highFreq = mix(highFreq, licHigh, coherence * 0.75);
    }

    // Recombine: warped bulk + original detail
    var sculptedColor = lowFreqWarped + highFreq;

    // ─────────────────────────────────────────────────────────────────────────
    //  Anisotropic color shift along tensor flow lines
    //  Edges of depth contours get slight chromatic shift
    // ─────────────────────────────────────────────────────────────────────────
    let chromaShift = anisotropy * 0.01 * sculptDepth * 10.0;
    let uvR = clamp(uv + principalDir * chromaShift + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv - principalDir * chromaShift + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let rShift = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let bShift = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    sculptedColor.r = mix(sculptedColor.r, rShift, anisotropy * 0.4);
    sculptedColor.b = mix(sculptedColor.b, bShift, anisotropy * 0.4);

    // ─────────────────────────────────────────────────────────────────────────
    //  Curvature-based emission: ridges and valleys glow
    // ─────────────────────────────────────────────────────────────────────────
    let ridgeGlow = smoothstep(0.02, 0.1, abs(meanCurvature)) * 0.15;
    let glowColor = mix(vec3<f32>(0.2, 0.5, 1.0), vec3<f32>(1.0, 0.3, 0.1), step(0.0, meanCurvature));
    sculptedColor += glowColor * ridgeGlow;

    // Idea 2: dome/saddle sheen — sign of Gaussian curvature K. K > 0 (dome or
    // bowl) catches a soft specular from a depth-derived normal; K < 0 (saddle)
    // reads as a darkened crease where the clay pinches.
    let grad = depthGrad(uv, texel);
    let sheen = smoothstep(0.008, 0.05, sqrt(abs(gaussCurvature)));
    let n = normalize(vec3<f32>(-grad * 40.0, 1.0));
    let lightDir = normalize(vec3<f32>(-0.4, -0.5, 0.77));
    let halfV = normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0));
    let specLobe = pow(max(dot(n, halfV), 0.0), 24.0);
    if (gaussCurvature > 0.0) {
        sculptedColor += vec3<f32>(1.0, 0.95, 0.85) * sheen * (0.12 + specLobe * 0.45) * (1.0 + treble * 0.5);
    } else {
        sculptedColor *= 1.0 - sheen * 0.4;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Temporal persistence via feedback (C = last frame's ACES display RGBA)
    // ─────────────────────────────────────────────────────────────────────────
    // Idea 3: clay creep — read history upstream of the sculpt displacement plus
    // a slow downhill drift (toward lower depth), so the material keeps sliding
    // between frames instead of re-sampling in place. Exact bilinear C loads.
    let downhill = -grad / max(length(grad), 1e-5) * smoothstep(0.0005, 0.01, length(grad));
    var creepPx = totalDisp * dims * 0.35 + downhill * (0.35 + mids * 0.3);
    let creepLen = length(creepPx);
    if (creepLen > 2.0) { creepPx = creepPx * (2.0 / creepLen); }
    let history = loadHistoryBilinear(fragCoord + 0.5 - creepPx, dims);
    // Mix post-ACES: history is already tone-mapped display RGB.
    let finalColor = mix(acesToneMap(max(sculptedColor, vec3<f32>(0.0))), history, persistence);

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    let warpDist = length(warpedUV - uv);
    let effectIntensity = clamp(warpDist * 6.0 + persistence * 0.2, 0.0, 1.0);
    let finalAlpha = mix(srcColorFull.a, 1.0, effectIntensity * 0.7);

    // Floor: removed the stamped clockRings / cosine clickFront overlay (and the
    // reserved `__finalRGB` + duplicate `rippleCount` that broke compilation).
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 1.0));
}
