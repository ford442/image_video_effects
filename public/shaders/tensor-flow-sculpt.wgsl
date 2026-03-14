// ═══════════════════════════════════════════════════════════════════════════════
//  Tensor Flow Sculpting
//  Category: EFFECT | Complexity: VERY_HIGH
//  Uses depth as a 4D tensor field to warp and sculpt the image like clay.
//  High-frequency details remain sharp while bulk geometry bends dramatically.
//  3D topology wrapped onto 2D—depth ridges become mountain ranges, valleys
//  become rivers of displaced color.
//  Mathematical approach: Structure tensor (Hessian of depth), eigenvalue-
//  driven anisotropic warping, bilateral frequency separation, geodesic
//  flow along principal curvature directions.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=FlowStrength, y=MouseX, z=MouseY, w=Persistence
    zoom_params: vec4<f32>,  // x=SculptDepth, y=FreqSeparation, z=CurvatureScale, w=AnimSpeed
    ripples: array<vec4<f32>, 50>,
};

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
    return textureSampleLevel(readDepthTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
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

    let steps = 3;
    let step = radius * texel;

    for (var dy = -steps; dy <= steps; dy++) {
        for (var dx = -steps; dx <= steps; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * step;
            let pos = uv + offset;

            // Central differences for gradient
            let gx = sampleDepth(pos + vec2<f32>(texel.x, 0.0)) - sampleDepth(pos - vec2<f32>(texel.x, 0.0));
            let gy = sampleDepth(pos + vec2<f32>(0.0, texel.y)) - sampleDepth(pos - vec2<f32>(0.0, texel.y));

            // Gaussian weight
            let w = exp(-dot(offset, offset) / (radius * radius * 0.5));

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

// ─────────────────────────────────────────────────────────────────────────────
//  Gaussian blur approximation for frequency separation
// ─────────────────────────────────────────────────────────────────────────────
fn blurSample(uv: vec2<f32>, texel: vec2<f32>, radius: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var total = 0.0;
    for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * texel * radius;
            let w = exp(-f32(dx * dx + dy * dy) / (radius * 0.5 + 0.1));
            col += textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * w;
            total += w;
        }
    }
    return col / total;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = fragCoord / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let sculptDepth = u.zoom_params.x * 0.08 + 0.005;      // 0.005 – 0.085
    let freqSep = u.zoom_params.y * 8.0 + 1.0;             // 1 – 9
    let curvatureScale = u.zoom_params.z * 5.0 + 0.5;      // 0.5 – 5.5
    let animSpeed = u.zoom_params.w * 2.0 + 0.2;           // 0.2 – 2.2
    let flowStr = u.zoom_config.x * 2.0 + 0.3;             // 0.3 – 2.3
    let persistence = u.zoom_config.w * 0.3 + 0.6;         // 0.6 – 0.9

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
    let rippleCount = u32(u.config.y);
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
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let highFreq = srcColor - lowFreqOriginal;

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

    // ─────────────────────────────────────────────────────────────────────────
    //  Temporal persistence via feedback
    // ─────────────────────────────────────────────────────────────────────────
    let history = textureSampleLevel(dataTextureC, u_sampler, warpedUV, 0.0).rgb;
    let finalColor = mix(sculptedColor, history, persistence);

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
