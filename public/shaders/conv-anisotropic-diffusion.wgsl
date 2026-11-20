// ═══════════════════════════════════════════════════════════════════
//  Anisotropic Diffusion
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, temporal, depth-aware, upgraded-rgba
//  Convolution Type: perona-malik-anisotropic-diffusion
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-19
//  Ideas: Tukey biweight conductivity; 4-neighbor coherence boost; Catte-Lions regularised conductivity (diagonal-tap pre-smoothing); heat-melted edge threshold (kappa rises at the cursor and ripple fronts); nine-point stencil (diagonal fluxes at half weight)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Diffused image (iterative smoothing along edges)
//    Alpha: Diffusion coefficient per pixel (how much smoothing was applied).
//           This creates a "process map" useful for stacking effects —
//           downstream shaders can read alpha to know which regions were simplified.
//
//  Perona-Malik anisotropic diffusion: smooths along edges but not across them.
//  Creates an oil-painting effect that progressively simplifies into flat regions.
//
//  MOUSE INTERACTIVITY:
//    Mouse position acts as a "heat source" where diffusion is accelerated AND the
//    edge threshold kappa rises (hot paint softens its own edge barriers),
//    creating melting/oil-paint drips emanating from the cursor.
//    Ripples inject transient diffusion fronts.
//
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
    return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

fn tukeyConductivity(gradientMag: f32, kappa: f32) -> f32 {
    let x = gradientMag / max(kappa, 0.0001);
    let inside = x < 1.0;
    let t = 1.0 - x * x;
    return select(0.0, t * t, inside);
}

// HEAD's conductivity: exp (Perona-Malik) blended 0.45 toward Tukey's biweight
fn conductance(g: f32, kappa: f32) -> f32 {
    return mix(diffusionCoefficient(g, kappa), tukeyConductivity(g, kappa), 0.45);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let pixel = vec2<i32>(global_id.xy);
    
    // Parameters
    let kappa = mix(0.01, 0.2, u.zoom_params.x);
    let dt = mix(0.05, 0.25, u.zoom_params.y);
    let iterations = i32(mix(1.0, 5.0, u.zoom_params.z));
    let mouseInfluence = u.zoom_params.w;
    
    // Depth awareness: preserve edges more in foreground
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthKappa = kappa * (1.0 - depth * 0.4);
    
    // Audio reactivity: bass drives diffusion strength
    let bass = plasmaBuffer[0].x;
    let audioDt = dt * (1.0 + bass * 0.8);
    
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var current = center;
    var avgCoeff = 0.0;

    // The 3x3 neighbourhood never changes between iterations: fetch it once (HEAD re-fetched
    // the same four taps on every iteration). The diagonals feed Ideas 3 and 5.
    let n = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 1.0) * pixelSize, 0.0).rgb;
    let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -1.0) * pixelSize, 0.0).rgb;
    let e = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 0.0) * pixelSize, 0.0).rgb;
    let w = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 0.0) * pixelSize, 0.0).rgb;
    let ne = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, 1.0) * pixelSize, 0.0).rgb;
    let nw = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, 1.0) * pixelSize, 0.0).rgb;
    let se = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(1.0, -1.0) * pixelSize, 0.0).rgb;
    let sw = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-1.0, -1.0) * pixelSize, 0.0).rgb;

    // Heat source and ripple fronts are loop-invariant too (HEAD recomputed the 50-ripple loop per iteration).
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * mouseInfluence;
    let mouseBoost = 1.0 + mouseFactor * 5.0;

    var rippleFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let rq = (rDist - rElapsed * 0.25) * 15.0;
            let wave = exp(-rq * rq);
            rippleFront = rippleFront + wave * (1.0 - rElapsed / 3.0);
        }
    }
    let rippleBoost = 1.0 + rippleFront * 3.0;

    // ── Idea 4: heat-melted edge threshold. Mouse Heat already speeds diffusion up, but an
    // edge barrier stays a barrier at any speed; hot paint also softens its own edges, so kappa
    // rises under the cursor and on a ripple front and the melt really crosses edges.
    let meltKappa = depthKappa * (1.0 + 4.0 * mouseFactor + 2.0 * min(rippleFront, 1.0));

    // Idea 5 renormalisation: 4 cardinal + 4 half-weight diagonals = 6 vs HEAD's 4, so the
    // default melt rate is kept (x4/6 ~ 0.7).
    let effectiveDt = audioDt * mouseBoost * rippleBoost * 0.7;

    for (var iter = 0; iter < iterations; iter++) {
        let gradN = length(n - current);
        let gradS = length(s - current);
        let gradE = length(e - current);
        let gradW = length(w - current);

        // ── Idea 3: Catte-Lions regularised conductivity. A single noisy pixel looks like an
        // edge to the raw gradient, so classic Perona-Malik *keeps* speckle. Pre-smooth along
        // the edge direction with the diagonal taps (3-tap row/column mean vs centre row/column)
        // and blend that into the gradient fed to the SAME exp/Tukey conductivity: noise below
        // the edge scale conducts, a full-height step edge is unchanged.
        let rowC = (w + current + e) * 0.33333;
        let colC = (n + current + s) * 0.33333;
        let regN = length((nw + n + ne) * 0.33333 - rowC);
        let regS = length((sw + s + se) * 0.33333 - rowC);
        let regE = length((ne + e + se) * 0.33333 - colC);
        let regW = length((nw + w + sw) * 0.33333 - colC);

        let cN = conductance(mix(gradN, regN, 0.65), meltKappa);
        let cS = conductance(mix(gradS, regS, 0.65), meltKappa);
        let cE = conductance(mix(gradE, regE, 0.65), meltKappa);
        let cW = conductance(mix(gradW, regW, 0.65), meltKappa);

        let horiz = gradE + gradW;
        let vert = gradN + gradS;
        let followH = 1.0 + 0.35 * step(horiz, vert);
        let followV = 1.0 + 0.35 * step(vert, horiz);

        // ── Idea 5: nine-point stencil. Diagonal fluxes at half weight (1/|d|^2) with the
        // gradient taken per unit length (/sqrt2) remove the 4-neighbour axis bias.
        let cNE = conductance(length(ne - current) * 0.70711, meltKappa);
        let cNW = conductance(length(nw - current) * 0.70711, meltKappa);
        let cSE = conductance(length(se - current) * 0.70711, meltKappa);
        let cSW = conductance(length(sw - current) * 0.70711, meltKappa);

        let wSum = (cN + cS) * followV + (cE + cW) * followH + 0.5 * (cNE + cNW + cSE + cSW);
        let flux = cN * (n - current) * followV
                 + cS * (s - current) * followV
                 + cE * (e - current) * followH
                 + cW * (w - current) * followH
                 + 0.5 * (cNE * (ne - current) + cNW * (nw - current) + cSE * (se - current) + cSW * (sw - current));

        // Stability: keep the step a convex combination (HEAD's mouse x ripple x audio boosts
        // could push dt * sum(c) past 1 and overshoot the neighbour mean).
        let stepK = min(effectiveDt, 0.95 / max(wSum, 0.0001));
        current = current + stepK * flux;

        avgCoeff = (cN + cS + cE + cW) * 0.25;
    }

    let paintBoost = 1.0 + mouseInfluence * 0.3;
    var finalColor = mix(center, current, paintBoost);
    
    // Temporal accumulation
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalColor = mix(finalColor, prev, 0.15);
    
    // Chromatic aberration on edges
    let edgeMag = length(center - current);
    let caOffset = edgeMag * 0.025;
    let rSample = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(caOffset, 0.0), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(caOffset, 0.0), 0.0).b;
    // HEAD wrote vec3(rSample, finalColor.g, bSample): R and B were raw source, so only green
    // was ever diffused. Carry the source's shifted detail on top of the diffused channels
    // instead, but only across a genuine edge: caOffset follows how much paint melted, which is
    // largest on removed noise, and un-gated the shifted source would put that noise back.
    let rowM = (w + center + e) * 0.33333;
    let colM = (n + center + s) * 0.33333;
    let edgeReg = max(max(length((nw + n + ne) * 0.33333 - rowM), length((sw + s + se) * 0.33333 - rowM)),
                      max(length((ne + e + se) * 0.33333 - colM), length((nw + w + sw) * 0.33333 - colM)));
    let edgeGate = smoothstep(2.0 * depthKappa, 5.0 * depthKappa, edgeReg);
    finalColor = vec3<f32>(finalColor.r + edgeGate * (rSample - center.r), finalColor.g, finalColor.b + edgeGate * (bSample - center.b));
    finalColor = max(finalColor, vec3<f32>(0.0));
    
    // ACES tone mapping
    finalColor = acesToneMap(finalColor);
    
    // Semantic alpha: diffusion coefficient modulated by depth (foreground = sharper = lower alpha)
    let alpha = clamp(avgCoeff * (1.0 - depth * 0.4), 0.0, 1.0);
    let packed = vec4<f32>(finalColor, alpha);
    
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
