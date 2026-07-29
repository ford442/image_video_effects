// ═══════════════════════════════════════════════════════════════════
//  Pixel Focus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, filter, pixelation, chromatic-aberration, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-28
//  Optimized: 2026-07-30 (Batch 17 — depth-aware focus, click pulses, spectral shimmer)
//  By: Agent 1a - Alpha Channel Specialist
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
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
    let pixelUV = floor(uv * density) / density;

    // Sample Clear and preserve input alpha
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let colClear = baseColor.rgb;

    // Sample Pixelated — branchless chromatic aberration
    let useChromatic = step(0.05, chromatic);
    let offset = chromatic * 0.01;
    let plainSample = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0);
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(pixelUV + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(pixelUV - vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let colPixel = vec3<f32>(
        mix(plainSample.r, rSample.r, useChromatic),
        plainSample.g,
        mix(plainSample.b, bSample.b, useChromatic)
    );

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
