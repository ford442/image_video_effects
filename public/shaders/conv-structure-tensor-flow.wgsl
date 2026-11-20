// ═══════════════════════════════════════════════════════════════════
//  Structure Tensor Flow
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: structure-tensor + LIC
//  Complexity: Very High
//  Upgraded: 2026-09-08, 2026-11-20
//  Ideas: minor-eigenvector LIC; source-luma tint; coherence-adaptive LIC length (§12.2A structure-tensor orientation); curved streamlines via midpoint re-orientation (§12.2A structure-tensor orientation)
//  Floor: pi-periodic orientation hue (no seam on horizontal structure); robust eigenvector; one shared 5x5 luma window for the tensor
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    R channel: Dominant eigenvector X component (full f32 for smooth flow)
//    G channel: Dominant eigenvector Y component
//    B channel: Coherency (eigenvalue ratio — how strongly oriented)
//    Alpha channel: LIC texture intensity (accumulated along streamline)
//
//  Computes the structure tensor (2x2 covariance of gradients), extracts
//  eigenvectors, and uses Line Integral Convolution to visualize texture flow.
//
//  MOUSE INTERACTIVITY:
//    Mouse position seeds additional streamline origin points, creating
//    vortices that disturb the natural flow. Ripples inject turbulence.
//
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Per-invocation constants shared by the tangent field evaluator (set once in main()).
var<private> g_pix: vec2<f32>;
var<private> g_mouse: vec2<f32>;
var<private> g_mouseInf: f32;
var<private> g_time: f32;
var<private> g_cos: f32;
var<private> g_sin: f32;

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    return dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// Sobel gradients of one 3x3 luma neighbourhood -> (gx^2, gy^2, gx*gy)
fn sobelTensor(tl: f32, t: f32, tr: f32, l: f32, r: f32, bl: f32, b: f32, br: f32) -> vec3<f32> {
    let gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    let gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    return vec3<f32>(gx * gx, gy * gy, gx * gy);
}

// Same tensor as before (3x3 box average of per-pixel Sobel tensors), built from ONE shared
// 5x5 luma window: 25 taps instead of 9 x 12. This is what pays for Ideas 1-2. (Named scalars,
// not an indexed array: constant indexing everywhere, nothing for a compiler to spill.)
fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec3<f32> {
    let a00 = sampleLuma(uv, pixelSize, -2, -2);
    let a01 = sampleLuma(uv, pixelSize, -1, -2);
    let a02 = sampleLuma(uv, pixelSize, 0, -2);
    let a03 = sampleLuma(uv, pixelSize, 1, -2);
    let a04 = sampleLuma(uv, pixelSize, 2, -2);
    let a10 = sampleLuma(uv, pixelSize, -2, -1);
    let a11 = sampleLuma(uv, pixelSize, -1, -1);
    let a12 = sampleLuma(uv, pixelSize, 0, -1);
    let a13 = sampleLuma(uv, pixelSize, 1, -1);
    let a14 = sampleLuma(uv, pixelSize, 2, -1);
    let a20 = sampleLuma(uv, pixelSize, -2, 0);
    let a21 = sampleLuma(uv, pixelSize, -1, 0);
    let a22 = sampleLuma(uv, pixelSize, 0, 0);
    let a23 = sampleLuma(uv, pixelSize, 1, 0);
    let a24 = sampleLuma(uv, pixelSize, 2, 0);
    let a30 = sampleLuma(uv, pixelSize, -2, 1);
    let a31 = sampleLuma(uv, pixelSize, -1, 1);
    let a32 = sampleLuma(uv, pixelSize, 0, 1);
    let a33 = sampleLuma(uv, pixelSize, 1, 1);
    let a34 = sampleLuma(uv, pixelSize, 2, 1);
    let a40 = sampleLuma(uv, pixelSize, -2, 2);
    let a41 = sampleLuma(uv, pixelSize, -1, 2);
    let a42 = sampleLuma(uv, pixelSize, 0, 2);
    let a43 = sampleLuma(uv, pixelSize, 1, 2);
    let a44 = sampleLuma(uv, pixelSize, 2, 2);
    var sum = vec3<f32>(0.0);
    sum += sobelTensor(a00, a01, a02, a10, a12, a20, a21, a22);
    sum += sobelTensor(a01, a02, a03, a11, a13, a21, a22, a23);
    sum += sobelTensor(a02, a03, a04, a12, a14, a22, a23, a24);
    sum += sobelTensor(a10, a11, a12, a20, a22, a30, a31, a32);
    sum += sobelTensor(a11, a12, a13, a21, a23, a31, a32, a33);
    sum += sobelTensor(a12, a13, a14, a22, a24, a32, a33, a34);
    sum += sobelTensor(a20, a21, a22, a30, a32, a40, a41, a42);
    sum += sobelTensor(a21, a22, a23, a31, a33, a41, a42, a43);
    sum += sobelTensor(a22, a23, a24, a32, a34, a42, a43, a44);
    return sum / 9.0;
}

// (dominant eigenvector xy = gradient direction, coherency) of the smoothed tensor at p.
fn orientAt(p: vec2<f32>) -> vec3<f32> {
    let t = smoothTensor(p, g_pix);
    let Jxx = t.x;
    let Jyy = t.y;
    let Jxy = t.z;

    let trace = Jxx + Jyy;
    let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
    let lambda1 = (trace + diff) * 0.5;
    let lambda2 = (trace - diff) * 0.5;

    // Dominant eigenvector. Both algebraic forms are the same line; (lambda1-Jyy, Jxy) is
    // normalize(0) when Jxy == 0 and Jxx < Jyy (a pure vertical ramp), so take whichever is longer,
    // carrying the first form's sign so every other pixel is bit-for-bit what it was.
    let c1 = vec2<f32>(lambda1 - Jyy, Jxy);
    let c2 = vec2<f32>(Jxy, lambda1 - Jxx) * select(1.0, -1.0, Jxy < 0.0);
    let v = select(c1, c2, dot(c2, c2) > dot(c1, c1));
    let usable = (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) && dot(v, v) > 1e-20;
    let eigenvec = select(vec2<f32>(1.0, 0.0), v * inverseSqrt(max(dot(v, v), 1e-20)), usable);

    // Coherency: how strongly oriented
    let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);
    return vec3<f32>(eigenvec, coherency);
}

// Mouse vortex + ripple turbulence acting on an orientation vector at p.
fn disturb(e0: vec2<f32>, p: vec2<f32>) -> vec2<f32> {
    var e = e0;
    // Mouse vortex disturbance
    let mouseDist = length(p - g_mouse);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * g_mouseInf;
    let mouseAngle = atan2(p.y - g_mouse.y, p.x - g_mouse.x);
    let vortex = vec2<f32>(-sin(mouseAngle), cos(mouseAngle)) * mouseFactor;
    e = normalize(mix(e, vortex, mouseFactor));

    // Ripple turbulence
    var rippleTurb = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = g_time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(p - rPos);
            let ring = (rDist - rElapsed * 0.3) * 8.0;          // negative inside the ring: square it, don't pow() it
            let wave = exp(-(ring * ring));
            let turbAngle = atan2(p.y - rPos.y, p.x - rPos.x) + rElapsed * 3.0;
            rippleTurb += vec2<f32>(cos(turbAngle), sin(turbAngle)) * wave * (1.0 - rElapsed / 3.0);
        }
    }
    return normalize(e + rippleTurb * 2.0);
}

// Animated LIC tangent at p (xy) and the tensor coherency there (z).
fn tangentAt(p: vec2<f32>) -> vec3<f32> {
    let o = orientAt(p);
    let e = disturb(o.xy, p);
    let fd = vec2<f32>(-e.y, e.x);
    return vec3<f32>(fd.x * g_cos - fd.y * g_sin, fd.x * g_sin + fd.y * g_cos, o.z);
}

// One LIC tap: luma at pos with the tent weight of tap i out of n; steps pos along d.
fn licTap(pos: ptr<function, vec2<f32>>, d: vec2<f32>, i: i32, n: i32, stepSize: f32) -> vec2<f32> {
    let lum = dot(textureSampleLevel(readTexture, u_sampler, *pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let w = 1.0 - f32(i) / f32(n);
    *pos = clamp(*pos + d * stepSize * g_pix, vec2<f32>(0.0), vec2<f32>(1.0));
    return vec2<f32>(lum * w, w);
}

// One arm of the LIC (tent-weighted, `n` taps). Returns (accum, weight).
fn licArm(uv: vec2<f32>, dir0: vec2<f32>, n: i32, stepSize: f32) -> vec2<f32> {
    var pos = uv;
    var d = dir0;
    var acc = vec2<f32>(0.0);
    let nMid = n / 2;

    for (var i = 0; i < nMid; i++) {
        acc += licTap(&pos, d, i, n, stepSize);
    }

    // ── Idea 2: curved streamlines (§12.2A structure-tensor orientation) ──
    // A real LIC integrates along the field; the old chord used the start pixel's direction for
    // every tap. At the arm midpoint re-read the tangent there (orientation is headless, so align
    // its sign with the incoming direction) and fade it in by the coherence found there, so
    // streaks bend with curved contours and fall back to straight where the tensor is isotropic.
    // (Outside the loops: the tensor is evaluated once per arm, not once per divergent tap.)
    let tm = tangentAt(pos);
    let aligned = select(tm.xy, -tm.xy, dot(tm.xy, d) < 0.0);
    d = normalize(mix(d, aligned, smoothstep(0.05, 0.35, tm.z)));

    for (var i = nMid; i < n; i++) {
        acc += licTap(&pos, d, i, n, stepSize);
    }
    return acc;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let pixel = vec2<i32>(global_id.xy);
    
    // Parameters
    let licSteps = i32(mix(8.0, 32.0, u.zoom_params.x));
    let coherencyBoost = mix(0.5, 4.0, u.zoom_params.y);
    let flowSpeed = mix(0.3, 2.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;

    // Animate flow direction over time (rotation shared by every tangent evaluation)
    let rotAngle = time * 0.2 * flowSpeed;
    g_pix = pixelSize;
    g_mouse = mousePos;
    g_mouseInf = mouseInfluence;
    g_time = time;
    g_cos = cos(rotAngle);
    g_sin = sin(rotAngle);

    // Smoothed structure tensor -> dominant eigenvector + coherency
    let o = orientAt(uv);
    let coherency = o.z;
    let boostedCoherency = pow(coherency, 1.0 / coherencyBoost);

    // Mouse vortex + ripple turbulence disturb the eigenvector
    let eigenvec = disturb(o.xy, uv);

    let flowDir = vec2<f32>(-eigenvec.y, eigenvec.x);
    let animatedDir = vec2<f32>(
        flowDir.x * g_cos - flowDir.y * g_sin,
        flowDir.x * g_sin + flowDir.y * g_cos
    );

    // ── Idea 1: coherence-adaptive LIC length (§12.2A structure-tensor orientation) ──
    // Coherency was only spent on colour and alpha. Where the tensor is isotropic the "direction" is
    // noise, so a long streak just smears speckle; clean edges keep the full `licSteps` streak.
    let arm = max(i32(f32(licSteps) * mix(0.3, 1.0, boostedCoherency)), 2);

    // LIC along the flow (Idea 2 lives in licArm)
    let fwd = licArm(uv, animatedDir, arm, 1.5);
    let bwd = licArm(uv, -animatedDir, arm, 1.5);
    let licValue = (fwd.x + bwd.x) / max(fwd.y + bwd.y, 0.001);
    
    // Color by orientation and coherency. Orientation is headless (theta == theta + pi), so the hue
    // follows the DOUBLED angle: it is continuous across horizontal structure (the old atan2 of the
    // eigenvector flipped hue on the sign of rounding noise there). theta = 0 keeps t = 0.5.
    let flowAngle = atan2(2.0 * eigenvec.x * eigenvec.y, eigenvec.x * eigenvec.x - eigenvec.y * eigenvec.y) * 0.15915 + 0.5;
    let color = palette(flowAngle, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let srcLuma = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));
    var finalColor = color * (0.3 + 0.7 * boostedCoherency) * (0.5 + 0.5 * licValue);
    finalColor = mix(finalColor, src.rgb * (0.45 + licValue * 0.8), 0.32 * (0.5 + srcLuma));
    finalColor = acesToneMap(finalColor * (1.0 + mids * 0.2));

    let alpha = clamp(licValue * (0.5 + boostedCoherency * 0.5) * (0.6 + treble * 0.3), 0.0, 1.0);
    let packed = vec4<f32>(finalColor, alpha);
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
