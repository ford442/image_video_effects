// ═══════════════════════════════════════════════════════════════════
//  Luma Slice Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, upgraded-rgba, semantic-alpha,
//            mouse-down-surge, fbm-wobble, palette-fringe
//  Complexity: Medium
//  Upgraded: 2026-10-06
//  Ideas: luma parallax layers (bright strips in front travel further); cut-face bevel + cast shadow at slice seams
//  A packing: ACES display RGBA (C is never read)
//  History: created 2026-05-10; Phase A swarm 2026-05-23; kimi-swarm 2026-07-19
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Intensity, y=SliceDensity, z=RGBShift, w=Phase

const TAU: f32 = 6.28318530718;

// ── Hash & noise helpers ────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                   hash21(i + vec2<f32>(1.0, 0.0)), s.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x),
        s.y
    );
}
// 3-octave fBM, normalized to ~[0, 1]
fn fbm3(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 3; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum / 0.875;
}

// ── Color helpers ───────────────────────────────────────────────────
// IQ cosine palette for the chromatic fringes
fn cosPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}
fn lumaOf(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
// Luma trigger: 3-tap average along a slice centre (smooths the displacement field so strips
// bend gradually instead of jumping with a single noisy sample).
fn sliceLuma(sliceIndex: f32, sliceHeight: f32, sampleX: f32) -> f32 {
    let cy = (sliceIndex + 0.5) * sliceHeight;
    var lumaSum = 0.0;
    for (var t = 0; t < 3; t++) {
        let tapX = fract(sampleX + (f32(t) - 1.0) * 0.06);
        let tap = textureSampleLevel(readTexture, non_filtering_sampler, vec2<f32>(tapX, cy), 0.0);
        lumaSum += lumaOf(tap.rgb);
    }
    return lumaSum / 3.0;
}
// Per-slice displacement terms (original: luma push + phase sine; fBM wobble; hashed jitter).
fn sliceTerms(sliceIndex: f32, luma: f32, time: f32, phase: f32, intensity: f32) -> f32 {
    let wobble = (fbm3(vec2<f32>(sliceIndex * 0.37, time * 0.45)) - 0.5) * 0.35;
    let jitter = (hashf(sliceIndex * 7.13) - 0.5) * 0.25;
    return luma - 0.5 + sin(time * 2.0 + sliceIndex * phase) * 0.2 + wobble + jitter * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let time = u.config.x;

    // ── Params (semantics preserved from the original) ──────────────
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0) * 0.5 * max(1.0 + bass * 0.2, 0.001);
    let sliceCount = 10.0 + clamp(u.zoom_params.y, 0.0, 1.0) * 190.0;
    let rgbShift = clamp(u.zoom_params.z, 0.0, 1.0) * 0.05;
    let phase = clamp(u.zoom_params.w, 0.0, 1.0);

    // ── Slice geometry ──────────────────────────────────────────────
    let sliceHeight = 1.0 / sliceCount;
    let sliceIndex = floor(uv.y * sliceCount);
    let sliceCenterY = (sliceIndex + 0.5) * sliceHeight;

    let sampleX = fract(mouse.x + time * 0.1);
    let luma = sliceLuma(sliceIndex, sliceHeight, sampleX);
    let aboveIndex = max(sliceIndex - 1.0, 0.0);
    let lumaAbove = sliceLuma(aboveIndex, sliceHeight, sampleX);

    // ── Displacement field ──────────────────────────────────────────
    let mouseFactor = smoothstep(0.0, 1.0, abs(mouse.y - 0.5) * 2.0 + 0.2);
    let surgeDist = distance(uv, mouse);
    let surge = select(0.0, 1.0, mouseDown > 0.5)
              * sin(surgeDist * 36.0 - time * 9.0)
              * exp(-surgeDist * 5.0) * 0.6;

    // IDEA 1 — luma parallax layers: the strip's luma is its layer z (bright = front);
    // front strips travel further, back strips lag.
    let z = luma;
    let zAbove = lumaAbove;
    let offset = clamp((sliceTerms(sliceIndex, luma, time, phase, intensity) + surge)
                       * intensity * mouseFactor * mix(0.7, 1.3, z), -0.35, 0.35);
    let offsetAbove = clamp((sliceTerms(aboveIndex, lumaAbove, time, phase, intensity) + surge)
                       * intensity * mouseFactor * mix(0.7, 1.3, zAbove), -0.35, 0.35);

    // ── RGB-split sampling (u_sampler wraps; fract keeps it explicit) ─
    // Mids add a subtle shimmer to the channel separation.
    let shift = rgbShift * (1.0 + mids * 0.4);
    let uvR = vec2<f32>(fract(uv.x + offset + shift), uv.y);
    let uvG = vec2<f32>(fract(uv.x + offset), uv.y);
    let uvB = vec2<f32>(fract(uv.x + offset - shift), uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var rgb = vec3<f32>(r, g, b);

    // ── Fringe tint: palette color only where channels separate ─────
    let fringe = clamp(abs(r - b) * 2.0, 0.0, 1.0) * smoothstep(0.0, 0.12, shift);
    let tint = cosPalette(luma + time * 0.04 + sliceIndex * 0.013);
    rgb += tint * fringe * 0.18;

    // ── Scanline shading (kept from the original, softened) ─────────
    let distCenter = abs(uv.y - sliceCenterY) / sliceHeight * 2.0;
    let scanline = 1.0 - smoothstep(0.75, 1.0, distCenter) * 0.28;
    rgb *= scanline;

    // IDEA 2 — cut-face bevel + cast shadow at the seam with the strip above. The sideways
    // step (shear) plus the layer gap sets how tall the exposed cut face is; the front strip
    // shows a lit bevel, a strip under a front neighbour receives its shadow.
    let shear = offset - offsetAbove;
    let dz = z - zAbove;
    let dy = uv.y - sliceIndex * sliceHeight;
    let faceH = min(abs(shear) * 0.8 + abs(dz) * sliceHeight * 0.5, sliceHeight * 0.45);
    let band = (1.0 - smoothstep(0.0, max(faceH, 1e-5), dy)) * step(0.5, sliceIndex);
    let inFront = smoothstep(-0.02, 0.02, dz);
    let bevel = band * inFront;
    let shadow = band * (1.0 - inFront);
    rgb = rgb * (1.0 + 0.35 * bevel) + vec3<f32>(0.04) * bevel;
    rgb *= 1.0 - 0.45 * shadow;

    // ── Highlight lift on strongly displaced bright strips ──────────
    let glowMask = smoothstep(0.55, 1.0, lumaOf(rgb)) * smoothstep(0.02, 0.2, abs(offset));
    rgb += rgb * glowMask * 0.22;

    // ── Vignette + fine grain ───────────────────────────────────────
    let vig = 1.0 - smoothstep(0.55, 1.05, length(uv - vec2<f32>(0.5))) * 0.16;
    let grain = (hash21(uv * resolution + vec2<f32>(fract(time) * 61.7, fract(time * 0.7) * 43.1)) - 0.5) * 0.02;
    rgb = rgb * vig + grain;

    // Bounded HDR, then ACES for display
    let finalColor = aces(clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.3)));

    // Semantic alpha: slice coverage — source alpha, dimmed under a cast shadow
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = clamp(current.a * (1.0 - 0.3 * shadow), 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(finalColor, alpha));
}
