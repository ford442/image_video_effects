// ═══════════════════════════════════════════════════════════════════
//  Pixel Focus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, filter, pixelation, chromatic-aberration, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-28, 2026-11-21
//  Optimized: 2026-07-30 (Batch 17 — depth-aware focus, click pulses, spectral shimmer)
//  By: Agent 1a - Alpha Channel Specialist
//  Ideas: Cauchy dispersion about the lens axis (§12.2F) — the Aberration slider becomes radial, wavelength-ordered lateral CA centred on the pointer; CFA zipper (§12.2A) — each mosaic cell keeps its own luma while chroma is shared across its 2×2 Bayer quad
//  A packing: display RGBA pass-through (no ACES: the in-focus pool must return the source pixel)
//  Rescues: texel-centre uv + mosaic sampled at cell centres (HEAD sampled texel/cell corners → half-cell shift and a half-pixel blur in the "clear" pool)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// n(λ) = 1 + B/λ² at 650/550/450 nm, relative to green → (<1, 1, >1).
fn cauchyScale(B: f32) -> vec3<f32> {
    let lam2 = vec3<f32>(0.650, 0.550, 0.450) * vec3<f32>(0.650, 0.550, 0.450);
    let n = vec3<f32>(1.0) + vec3<f32>(B) / lam2;
    return n / n.y;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    var uv = (vec2<f32>(global_id.xy) + 0.5) / resolution; // texel centre (rescue)
    let aspect = resolution.x / max(resolution.y, 0.001);
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let time = u.config.x;

    // Global audio bands
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Spectral shimmer bins (per-bin energy for the mosaic "breathing")
    let bin1 = plasmaBuffer[1].x;
    let bin2 = plasmaBuffer[2].x;
    let bin3 = plasmaBuffer[3].x;
    let bin4 = plasmaBuffer[4].x;

    // Params — Block Size / Focus Radius / Edge Hardness / Aberration
    let mosaicSize = clamp(u.zoom_params.x, 0.0, 1.0);
    let focusRadiusBase = mix(0.01, 0.5, clamp(u.zoom_params.y, 0.0, 1.0));
    let hardness = clamp(u.zoom_params.z, 0.0, 1.0);
    let chromatic = clamp(u.zoom_params.w + treble * 0.1, 0.0, 1.0);

    // ── Depth-aware focus ───────────────────────────────────────────
    // Sample scene depth at the focus point (mouse) and at this pixel.
    // The lens tunes its radius to the subject's depth: near content
    // gets a tighter, more intimate focus pool; far content a wider one.
    let mouseClamped = clamp(mouse, vec2<f32>(0.0), vec2<f32>(1.0));
    let depthAtMouse = textureSampleLevel(readDepthTexture, non_filtering_sampler, mouseClamped, 0.0).r;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Holding the mouse button gently pulls focus wider (rack-focus feel).
    let focusRadius = focusRadiusBase * mix(0.7, 1.3, depthAtMouse) * (1.0 + mouseDown * 0.15);

    // Calculate distance to mouse
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    // Mixing factor: 0.0 = Pixelated, 1.0 = Clear
    var focus = clamp(
        1.0 - smoothstep(focusRadius, focusRadius + (1.0 - hardness) * 0.2, dist),
        0.0, 1.0
    );

    // ── Click focus pulses ──────────────────────────────────────────
    // Each live ripple emits an expanding SHARP ring of clarity that
    // snaps a band of the mosaic into full focus as it sweeps outward,
    // decaying over ~1.5 seconds.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let timeSinceClick = time - ripple.z;
        if (timeSinceClick > 0.0 && timeSinceClick < 1.5) {
            let rippleCorrected = vec2<f32>(ripple.x * aspect, ripple.y);
            let rippleDist = distance(uvCorrected, rippleCorrected);
            let ringRadius = timeSinceClick * 0.55;              // expansion speed
            let ringWidth = 0.035 + timeSinceClick * 0.02;       // softens as it grows
            let ringBand = 1.0 - smoothstep(ringWidth * 0.5, ringWidth, abs(rippleDist - ringRadius));
            let ringDecay = 1.0 - timeSinceClick / 1.5;          // linear fade over 1.5s
            focus = max(focus, ringBand * ringDecay);
        }
    }
    focus = clamp(focus, 0.0, 1.0);

    // ── Pixelation with spectral mosaic shimmer ─────────────────────
    // Per-bin energy makes the density breathe with the music beyond
    // the global bass/mids term; depth adds a gentle parallax coarsening.
    var density = (50.0 + (1.0 - mosaicSize) * 450.0) * (1.0 + bass * 0.1 + mids * 0.05);
    let spectralShimmer = bin1 * 0.04 + bin2 * 0.03 + bin3 * 0.02 + bin4 * 0.02;
    density = density * (1.0 + spectralShimmer);
    density = density * mix(1.0, 0.85, depth * (1.0 - focus)); // far mosaic slightly coarser
    density = max(density, 1.0);
    let cellUV = (floor(uv * density) + 0.5) / density; // cell centre (rescue: HEAD sampled the corner)

    // Sample Clear and preserve input alpha
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let colClear = baseColor.rgb;

    // ── Idea 2: CFA zipper (§12.2A) ─────────────────────────────────
    // A mosaic cell is a sensor pixel. Like a Bayer sensor it keeps its own
    // luma but shares chroma with its 2×2 quad, so fine edges alias into
    // cell-scale colour fringes. Luma still comes from the cell (HEAD's
    // detail); only chroma coarsens.
    let lw = vec3<f32>(0.299, 0.587, 0.114);
    let groupUV = (floor(uv * density * 0.5) * 2.0 + 1.0) / density;
    let cellRGB = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0).rgb;
    var quadRGB = textureSampleLevel(readTexture, u_sampler, groupUV, 0.0).rgb;

    // ── Idea 1: Cauchy dispersion about the lens axis (§12.2F) ──────
    // The Aberration slider keeps its role and its 0.05 gate, but a lens'
    // lateral CA is radial from the optical axis (the pointer = the focus
    // pool's centre): zero on-axis, growing with field radius, and spaced by
    // n(λ) = 1 + B/λ² so blue bends further than red. B = 0.0127 at slider
    // max ≈ HEAD's ±0.01 uv shift at field radius ≈ 0.5.
    let useChromatic = step(0.05, chromatic);
    if (useChromatic > 0.5) {
        let sc = cauchyScale(chromatic * 0.0127);
        let rUV = clamp(mouseClamped + (groupUV - mouseClamped) * sc.x, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(mouseClamped + (groupUV - mouseClamped) * sc.z, vec2<f32>(0.0), vec2<f32>(1.0));
        quadRGB = vec3<f32>(
            textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
            quadRGB.g,
            textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
        );
    }
    // luma from the cell, chroma from the (dispersed) quad
    let colPixel = max(quadRGB + vec3<f32>(dot(cellRGB, lw) - dot(quadRGB, lw)), vec3<f32>(0.0));

    var finalRGB = mix(colPixel, colClear, focus);

    // ── Lens rim highlight ──────────────────────────────────────────
    // A faint bright ring hugs the focus boundary so the lens edge
    // reads as glass; it breathes slightly with the treble.
    let rimOuter = smoothstep(focusRadius - 0.015, focusRadius, dist);
    let rimInner = 1.0 - smoothstep(focusRadius, focusRadius + 0.03 + treble * 0.01, dist);
    let rim = rimOuter * rimInner * (0.05 + treble * 0.03);
    finalRGB = finalRGB + vec3<f32>(rim);

    // Alpha: preserve input alpha, modulated by focus region and luma
    let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(baseColor.a * (focus * 0.6 + luma * 0.3 + 0.1), 0.0, 1.0);
    let finalColor = vec4<f32>(finalRGB, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
