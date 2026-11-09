// ═══════════════════════════════════════════════════════════════════
//  ASCII Lens
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, click-reactive, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-03-22, 2026-08-02, 2026-11-09
//  Ideas: cursor lens; click glyph scrambles + RGB split; per-cell FFT flicker; bass radius breath;
//         cell-mean luma + Bayer-ordered tier dither (aalib/libcaca cell approximation);
//         edge-directed strokes (structure-tensor orientation, §12.2A)
//  A packing: display RGBA; texel (0,0) = (glide.x, glide.y, 7 marker, fract(time)) cursor state (not display data)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ASCII Lens
// Param 1: Lens Radius (0.0 to 1.0)
// Param 2: Grid Density (High values = smaller chars)
// Param 3: Glyph Line Width
// Param 4: Brightness Threshold Bias
//
// Persistent state: A texel (0,0) only (see Rescue R1). extraBuffer[133..] is
// re-uploaded zeroed every frame, so nothing is stored there.

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// HEAD's critically-damped spring lived in extraBuffer[133..138], which the host
// re-uploads zeroed every frame, so the lens always sat on the raw cursor.
// State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the
// same C texel and integrates the same step, only pixel (0,0) stores it. First-order
// glide (a velocity cannot be stored f16-safely); at rest it snaps exactly onto the
// cursor. Replaces the dead spring (omega 8) by exp(-8 dt): lens trails ~1/8 s.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    // w can round up to exactly 1.0 in f16 (fract(time) > 0.9997): accept it.
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
    return select(raw, snapped, ok);
}

// ── Rescue R2: engine FFT bins (extraBuffer[5 + bin], 0..1) ──────────
// HEAD read plasmaBuffer[1..8].x, which the host never uploads (always 0).
fn fftBin(bin: u32) -> f32 {
    let idx = 5u + min(bin, 127u);
    return select(0.0, extraBuffer[min(idx, arrayLength(&extraBuffer) - 1u)], arrayLength(&extraBuffer) > idx);
}
// The 8 old per-cell voices spread over the bins where the energy is: {0,1,2,4,7,11,19,32}.
fn fftVoice(v: u32) -> f32 {
    let lo = vec4<u32>(0u, 1u, 2u, 4u);
    let hi = vec4<u32>(7u, 11u, 19u, 32u);
    let k = v & 3u;
    return fftBin(select(lo[k], hi[k], v >= 4u));
}

// 4x4 Bayer ordered-dither value in (-0.5, 0.5), from an integer cell index.
fn bayer4(c: vec2<u32>) -> f32 {
    let x = c.x & 3u;
    let y = c.y & 3u;
    let a = x ^ y;
    let idx = ((a & 1u) << 3u) | ((y & 1u) << 2u) | (a & 2u) | ((y & 2u) >> 1u);
    return (f32(idx) + 0.5) / 16.0 - 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // The raw mouse (with the negative-coord center fallback) is the glide target.
    var rawMouse = u.zoom_config.yz;
    if (rawMouse.x < 0.0) { rawMouse = vec2<f32>(0.5, 0.5); }

    // ── Rescue R1: cursor glide (rate 8 = HEAD omega) — see glideStep() ──
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let mouse = glideStep(glideState, rawMouse, time, 8.0);

    // Bass breathes the lens radius. (Rescue R2: was plasmaBuffer[1].x, never uploaded.)
    let bass = plasmaBuffer[0].x;

    let lensRadius = u.zoom_params.x * (1.0 + bass * 0.15); // Default 0.3
    let density = 50.0 + u.zoom_params.y * 150.0; // 50 to 200 grid cells vertical

    // Calculate distance to mouse for lens effect
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Click scrambles: each live ripple jitters glyphs near its click point.
    // Aspect-corrected ~0.2 radius, decays as exp(-age * 2.5) over ~1s.
    var scramble = 0.0;
    var scrambleSeed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.2) {
            let clickDist = distance(
                vec2<f32>(uv.x * aspect, uv.y),
                vec2<f32>(ripple.x * aspect, ripple.y)
            );
            let falloff = 1.0 - smoothstep(0.0, 0.2, clickDist);
            let weight = falloff * exp(-age * 2.5);
            if (weight > scramble) {
                scramble = weight;
                scrambleSeed = f32(ri) * 17.13 + ripple.z;
            }
        }
    }

    var finalColor: vec3<f32>;
    var finalAlpha: f32;

    if (dist < lensRadius) {
        // Inside Lens: ASCII Effect

        // Define grid
        let grid = vec2<f32>(density * aspect, density); // Adjust X for aspect to make square cells
        let cellUV = floor(uv * grid) / grid;
        let localUV = fract(uv * grid);

        // Sample color at cell center (pixelated look)
        // Add half pixel offset to sample center of block
        let sampleUV = cellUV + (vec2<f32>(0.5) / grid);
        var col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

        // ── Idea 1: cell-mean luma (aalib/libcaca cell approximation) ────
        // HEAD decided the tier from ONE tap at the cell centre, so fine texture
        // aliased into flickering glyphs and tonal ramps broke into hard contour
        // bands. The cell's brightness is its mean: centre + 4 taps at +-0.3 cell.
        // The same four taps give the cell gradient for Idea 2 for free.
        let tapD = vec2<f32>(0.3) / grid;
        let lumaW = vec3<f32>(0.299, 0.587, 0.114);
        let lumaC = dot(col, lumaW);
        let lumaL = dot(textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(tapD.x, 0.0), 0.0).rgb, lumaW);
        let lumaR = dot(textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(tapD.x, 0.0), 0.0).rgb, lumaW);
        let lumaU = dot(textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(0.0, tapD.y), 0.0).rgb, lumaW);
        let lumaD = dot(textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(0.0, tapD.y), 0.0).rgb, lumaW);
        let cellLuma = (lumaC + lumaL + lumaR + lumaU + lumaD) * 0.2;

        // Per-cell audio flicker: each glyph cell shimmers by its own FFT bin.
        // (Rescue R2: was plasmaBuffer[1..8].x by cell hash, never uploaded; now
        // extraBuffer[5 + bin]. Zero audio -> flicker = 0 -> HEAD's idle look.)
        let cellHash = hash21(cellUV * 251.0);
        let flicker = fftVoice(u32(cellHash * 8.0) % 8u) * 0.4;

        // Click scramble: decaying hash jitter added to the luma tier selection.
        let jitter = (hash21(cellUV * 97.0 + vec2<f32>(scrambleSeed)) - 0.5) * scramble;

        var luma = cellLuma + (u.zoom_params.w - 0.5) * 0.4;
        luma = clamp(luma + jitter + (flicker - 0.2) * 0.25, 0.0, 1.0);

        // ── Idea 1 (cont.): Bayer-ordered tier dither ────────────────────
        // A 4x4 Bayer value of the cell index shifts the tier thresholds by up to
        // +-0.06, so a tonal ramp steps through the glyph tiers as a fine ordered
        // pattern instead of a contour band, and a cell on a threshold keeps its
        // glyph from frame to frame (the pattern is static in cell space).
        let cellIdx = vec2<u32>(floor(uv * grid));
        luma = luma + bayer4(cellIdx) * 0.12;

        var charVal = 0.0;
        var center = vec2<f32>(0.5, 0.5);
        let distCenter = length(localUV - center);

        // Line width proportional to density? Constant is better for pixel crispness.
        // In UV space (0-1), 1 pixel width is roughly 1.0 / (res.y / density * 8.0).
        // Let's use a fixed relative width.
        let width = mix(0.02, 0.25, u.zoom_params.z);

        // ── Idea 2: edge-directed strokes (structure-tensor orientation, §12.2A) ──
        // Real ASCII converters pick directional glyphs ( - | / \ ) where a cell
        // holds an edge. J = grad(L) grad(L)^T per cell (rank 1, so the orientation is
        // the gradient direction n; |g| is the confidence). The stroke runs along the
        // edge TANGENT (-n.y, n.x), snapped to the four ASCII stroke angles; its width
        // is the existing line-width slider. '#' and '@' stay for bright blocks.
        let g = vec2<f32>(lumaR - lumaL, lumaD - lumaU);
        let gLen = length(g);
        let n = g / max(gLen, 1e-4);
        let ax = abs(n.x);
        let ay = abs(n.y);
        let diagN = vec2<f32>(0.70710678, select(-0.70710678, 0.70710678, n.x * n.y >= 0.0));
        let nQ = select(select(diagN, vec2<f32>(0.0, 1.0), ax < 0.41421356 * ay),
                        vec2<f32>(1.0, 0.0), ay < 0.41421356 * ax);
        let edgeStroke = abs(dot(localUV - center, nQ)) < width;
        let isEdge = gLen > 0.08;

        // Procedural Glyphs
        // Sorted by brightness
        if (luma > 0.8) {
            // # Block / Full
            charVal = 1.0;
        } else if (luma > 0.6) {
            // @ Square Frame + Dot
            if (abs(localUV.x - 0.5) > 0.2 || abs(localUV.y - 0.5) > 0.2) { charVal = 1.0; }
            if (distCenter < 0.1) { charVal = 1.0; }
        } else if (luma > 0.1 && isEdge) {
            // Idea 2: + - . on an edge cell become one stroke along the tangent
            if (edgeStroke) { charVal = 1.0; }
        } else if (luma > 0.4) {
            // + Plus
            if (abs(localUV.x - 0.5) < width || abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.25) {
            // - Minus
             if (abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.1) {
            // . Dot
            if (distCenter < 0.15) { charVal = 1.0; }
        }

        // Audio shimmer: charVal dances with the cell's own FFT bin.
        charVal = charVal * (0.8 + flicker);

        finalColor = col * charVal;

        // Calculate luminance-based alpha
        let lumaFinal = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
        let alpha = clamp(mix(0.7, 1.0, lumaFinal), 0.0, 1.0); // clamp: audio shimmer can push lumaFinal past 1
        finalAlpha = mix(alpha * 0.8, alpha, depth);

    } else {
        // Outside Lens: Normal
        var col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        finalColor = col.rgb;
        finalAlpha = col.a;

        // Brief RGB split flicker marks the click outside the lens.
        if (scramble > 0.01) {
            let splitDir = vec2<f32>(hash21(vec2<f32>(scrambleSeed, 1.7)) - 0.5, 0.5) * 0.02 * scramble;
            let rUv = clamp(uv + splitDir, vec2<f32>(0.0), vec2<f32>(1.0));
            let bUv = clamp(uv - splitDir, vec2<f32>(0.0), vec2<f32>(1.0));
            let rCol = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
            let bCol = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;
            finalColor = vec3<f32>(rCol, finalColor.g, bCol);
        }
    }

    let displayColor = vec4<f32>(finalColor, finalAlpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), displayColor);
    // dataTextureA = display RGBA, except texel (0,0): cursor-glide state (Rescue R1).
    // The display pixel at (0,0) still goes to writeTexture above.
    var aOut = displayColor;
    if (global_id.x == 0u && global_id.y == 0u) {
        aOut = vec4<f32>(mouse, GLIDE_MARK, fract(time));
    }
    textureStore(dataTextureA, vec2<i32>(global_id.xy), aOut);

    // Pass depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
