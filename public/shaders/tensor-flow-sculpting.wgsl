// ─────────────────────────────────────────────────────────────────────────────
//  Tensor Flow Sculpting
//  Category: EFFECT
//  Complexity: VERY HIGH
//  Visual concept: Depth is treated as a 4-D tensor field that warps and
//    sculpts the image like clay — bulk regions bend dramatically while
//    high-frequency edge details stay crisp, like 3-D topology projected onto 2-D.
//  Mathematical approach: Depth gradient forms a 2×2 Jacobian "strain tensor";
//    eigenvectors give principal stretch directions; image is advected along
//    eigenvectors with eigenvalue-modulated amplitude; high-pass detail is
//    added back after warp to preserve sharpness.
// ─────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>, // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=unused, y=MouseX, z=MouseY, w=unused
    zoom_params: vec4<f32>, // x=StrainScale, y=DetailPreserve, z=FlowSpeed, w=TensorMode
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Sample depth with border clamping
// ─────────────────────────────────────────────────────────────────────────────
fn sampleDepth(uv: vec2<f32>) -> f32 {
    return textureSampleLevel(readDepthTexture, non_filtering_sampler,
                              clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Symmetric 2×2 tensor eigendecomposition (analytic)
//  T = [[a, b], [b, d]]  →  eigenvalues λ±, eigenvectors v±
// ─────────────────────────────────────────────────────────────────────────────
struct Eigen2 {
    lam_pos: f32,
    lam_neg: f32,
    vec_pos: vec2<f32>,
    vec_neg: vec2<f32>,
};

fn tensorEigen(a: f32, b: f32, d: f32) -> Eigen2 {
    let tr   = a + d;
    let det  = a * d - b * b;
    let disc = max(tr * tr * 0.25 - det, 0.0);
    let sq   = sqrt(disc);
    let lp   = tr * 0.5 + sq;
    let ln   = tr * 0.5 - sq;
    // Eigenvector for lp: (T - lp I) v = 0
    var vp: vec2<f32>;
    if (abs(b) > 1e-6) {
        vp = normalize(vec2<f32>(lp - d, b));
    } else {
        vp = vec2<f32>(1.0, 0.0);
    }
    let vn = vec2<f32>(-vp.y, vp.x);
    var e: Eigen2;
    e.lam_pos = lp; e.lam_neg = ln;
    e.vec_pos = vp; e.vec_neg = vn;
    return e;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth noise
// ─────────────────────────────────────────────────────────────────────────────
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ripple accumulation
// ─────────────────────────────────────────────────────────────────────────────
fn rippleDisp(uv: vec2<f32>, t: f32, cnt: u32) -> vec2<f32> {
    var d = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < cnt; i++) {
        let r   = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let dist = distance(uv, r.xy);
        let wave = sin(dist * 28.0 - age * 6.0) * exp(-dist * 5.0) * exp(-age * 1.1);
        if (dist > 0.001) {
            d += normalize(uv - r.xy) * wave * (1.0 - age / 4.0) * 0.015;
        }
    }
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  FBM noise (4 octaves) using vnoise
// ─────────────────────────────────────────────────────────────────────────────
fn fbm_tfs(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * vnoise(pp);
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Depth-aware edge detection (cross-bilateral)
// ─────────────────────────────────────────────────────────────────────────────
fn depthEdge(uv: vec2<f32>, tx: vec2<f32>, d: f32) -> f32 {
    let dR = sampleDepth(uv + vec2<f32>(tx.x, 0.0));
    let dL = sampleDepth(uv - vec2<f32>(tx.x, 0.0));
    let dU = sampleDepth(uv + vec2<f32>(0.0, tx.y));
    let dD = sampleDepth(uv - vec2<f32>(0.0, tx.y));
    return length(vec4<f32>(dR - dL, dU - dD, dR - d, dU - d)) * 5.0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Anisotropic bilateral weight for sharpening
// ─────────────────────────────────────────────────────────────────────────────
fn bilatWeight(uv: vec2<f32>, off: vec2<f32>, sigmaS: f32, sigmaC: f32) -> f32 {
    let spatW = exp(-dot(off, off) / (2.0 * sigmaS * sigmaS));
    let d0 = sampleDepth(uv);
    let d1 = sampleDepth(uv + off);
    let colorW = exp(-(d0 - d1) * (d0 - d1) / (2.0 * sigmaC * sigmaC));
    return spatW * colorW;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tensor visualization: map principal stress directions to color
// ─────────────────────────────────────────────────────────────────────────────
fn stressColor(lam_pos: f32, lam_neg: f32, t: f32) -> vec3<f32> {
    let tensile = max(lam_pos, 0.0);
    let compress = max(-lam_neg, 0.0);
    let shear   = abs(lam_pos - lam_neg) * 0.5;
    return vec3<f32>(
        clamp(tensile * 3.0 + sin(t) * 0.1, 0.0, 1.0),
        clamp(shear   * 2.0, 0.0, 1.0),
        clamp(compress * 3.0 + cos(t * 1.3) * 0.1, 0.0, 1.0)
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Normal estimation from depth map (for shading)
// ─────────────────────────────────────────────────────────────────────────────
fn depthNormal(uv: vec2<f32>, tx: vec2<f32>) -> vec3<f32> {
    let dR = sampleDepth(uv + vec2<f32>(tx.x, 0.0));
    let dL = sampleDepth(uv - vec2<f32>(tx.x, 0.0));
    let dU = sampleDepth(uv + vec2<f32>(0.0, tx.y));
    let dD = sampleDepth(uv - vec2<f32>(0.0, tx.y));
    return normalize(vec3<f32>(dL - dR, dD - dU, 0.1));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res  = u.config.zw;
    let uv   = vec2<f32>(gid.xy) / res;
    let t    = u.config.x;
    let tx   = 1.0 / res;

    // Parameters
    let strainScale    = u.zoom_params.x * 0.08 + 0.005; // 0.005 – 0.085
    let detailPreserve = u.zoom_params.y;                  // 0 – 1
    let flowSpeed      = u.zoom_params.z * 0.3 + 0.05;    // 0.05 – 0.35
    let tensorMode     = u.zoom_params.w;                  // 0=stretch, 1=shear

    // ── Depth Jacobian: first and second-order partial derivatives ────────
    let h   = sampleDepth(uv);
    let hR  = sampleDepth(uv + vec2<f32>(tx.x, 0.0));
    let hL  = sampleDepth(uv - vec2<f32>(tx.x, 0.0));
    let hU  = sampleDepth(uv + vec2<f32>(0.0, tx.y));
    let hD  = sampleDepth(uv - vec2<f32>(0.0, tx.y));
    let hRU = sampleDepth(uv + vec2<f32>(tx.x, tx.y));
    let hLD = sampleDepth(uv - vec2<f32>(tx.x, tx.y));

    let dX  = (hR - hL) * 0.5;
    let dY  = (hU - hD) * 0.5;
    let dXX = hR - 2.0 * h + hL;
    let dYY = hU - 2.0 * h + hD;
    let dXY = (hRU - hR - hU + h) * 0.5; // mixed partial

    // ── Build strain tensor (symmetric) ───────────────────────────────────
    // Mode 0: stretch tensor (Hessian of depth)
    // Mode 1: blend toward shear-dominant tensor
    let tA = mix(dXX, dXY, tensorMode);
    let tB = dXY;
    let tD = mix(dYY, dXX, tensorMode);

    let eigen = tensorEigen(tA, tB, tD);

    // ── Time-varying flow amplitude ───────────────────────────────────────
    let noiseFlow = vnoise(uv * 4.0 + vec2<f32>(t * flowSpeed, t * flowSpeed * 0.7)) - 0.5;
    let flowAmp   = strainScale * (1.0 + noiseFlow * 0.5);

    // ── Tensor warp: stretch along principal eigenvectors ─────────────────
    let warp1 = eigen.vec_pos * eigen.lam_pos * flowAmp;
    let warp2 = eigen.vec_neg * eigen.lam_neg * flowAmp;
    let tensorWarp = clamp(warp1 + warp2, vec2<f32>(-0.1), vec2<f32>(0.1));

    // ── Depth gradient warp (direct normal flow) ──────────────────────────
    let normalFlow = vec2<f32>(dX, dY) * strainScale * 3.0 * sin(t * 0.2);

    // ── Ripple ────────────────────────────────────────────────────────────
    let rDisp = rippleDisp(uv, t, u32(u.config.y));

    let totalWarp = tensorWarp + normalFlow + rDisp;
    let warpedUV  = clamp(uv + totalWarp, vec2<f32>(0.0), vec2<f32>(1.0));

    // ── Sample warped image ───────────────────────────────────────────────
    let colWarped = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

    // ── High-pass detail recovery (preserve sharp edges) ──────────────────
    let colCenter = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // Approximate Laplacian (detail)
    let lap = colCenter.rgb
        - ( textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(tx.x, 0.0), 0.0).rgb
          + textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(tx.x, 0.0), 0.0).rgb
          + textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, tx.y), 0.0).rgb
          + textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, tx.y), 0.0).rgb
        ) * 0.25;

    // Add sharpening detail back onto warped image
    let result = clamp(colWarped.rgb + lap * detailPreserve * 2.5, vec3<f32>(0.0), vec3<f32>(1.0));

    // ── FBM-based secondary deformation layer ─────────────────────────────
    let fbmWarp = (fbm_tfs(uv * 5.0 + vec2<f32>(t * flowSpeed * 0.5)) - 0.5) * strainScale;
    let fbmUV   = clamp(warpedUV + fbmWarp, vec2<f32>(0.0), vec2<f32>(1.0));
    let colFBM  = textureSampleLevel(readTexture, u_sampler, fbmUV, 0.0);
    let fbmBlend = (1.0 - detailPreserve) * 0.25;

    // ── Depth-aware edge detection for edge-preserving sharpen ────────────
    let edge     = depthEdge(uv, tx, h);
    let edgeMask = smoothstep(0.05, 0.4, edge);

    // ── Depth normal for subtle shading ───────────────────────────────────
    let N      = depthNormal(uv, tx);
    let light  = normalize(vec3<f32>(cos(t * 0.2), sin(t * 0.15), 0.8));
    let NdotL  = max(dot(N, light), 0.0) * 0.3 + 0.7;

    // ── Stress color overlay ──────────────────────────────────────────────
    let sColor = stressColor(eigen.lam_pos, eigen.lam_neg, t);
    let sBlend = length(tensorWarp) * 4.0 * (1.0 - detailPreserve) * 0.5;

    // ── Final composite ───────────────────────────────────────────────────
    var finalResult = mix(result, colFBM.rgb, fbmBlend);
    finalResult = mix(finalResult, finalResult + lap * 1.5, edgeMask * detailPreserve * 0.5);
    finalResult = finalResult * NdotL + sColor * clamp(sBlend, 0.0, 0.15);
    finalResult = clamp(finalResult, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, gid.xy, vec4<f32>(finalResult, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(h, 0.0, 0.0, 1.0));
}
