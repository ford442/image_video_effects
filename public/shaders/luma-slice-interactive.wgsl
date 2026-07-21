// ═══════════════════════════════════════════════════════════════════
//  Luma Slice Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, upgraded-rgba,
//            mouse-down-surge, fbm-wobble, palette-fringe
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  By: Phase A Upgrade Swarm
//  Upgraded by: kimi-swarm 2026-07-19
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=SliceDensity, z=RGBShift, w=Phase
  ripples: array<vec4<f32>, 50>,
};

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

    // ── Luma trigger: 3-tap average along the slice ─────────────────
    // Smooths the displacement field so strips bend gradually instead of
    // jumping with a single noisy sample.
    let sampleX = fract(mouse.x + time * 0.1);
    var lumaSum = 0.0;
    for (var t = 0; t < 3; t++) {
        let tapX = fract(sampleX + (f32(t) - 1.0) * 0.06);
        let tap = textureSampleLevel(readTexture, non_filtering_sampler,
                                     vec2<f32>(tapX, sliceCenterY), 0.0);
        lumaSum += lumaOf(tap.rgb);
    }
    let luma = lumaSum / 3.0;

    // ── Displacement field ──────────────────────────────────────────
    // Original terms: luma push + phase sine. New terms: organic fBM
    // wobble per slice and a mouse-down surge ripple from the cursor.
    let mouseFactor = smoothstep(0.0, 1.0, abs(mouse.y - 0.5) * 2.0 + 0.2);
    let wobble = (fbm3(vec2<f32>(sliceIndex * 0.37, time * 0.45)) - 0.5) * 0.35;
    let jitter = (hashf(sliceIndex * 7.13) - 0.5) * 0.25;

    let surgeDist = distance(uv, mouse);
    let surge = select(0.0, 1.0, mouseDown > 0.5)
              * sin(surgeDist * 36.0 - time * 9.0)
              * exp(-surgeDist * 5.0) * 0.6;

    let offsetBase = (luma - 0.5
                    + sin(time * 2.0 + sliceIndex * phase) * 0.2
                    + wobble
                    + jitter * intensity
                    + surge) * intensity * mouseFactor;
    let offset = clamp(offsetBase, -0.35, 0.35);

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

    // ── Highlight lift on strongly displaced bright strips ──────────
    let glowMask = smoothstep(0.55, 1.0, lumaOf(rgb)) * smoothstep(0.02, 0.2, abs(offset));
    rgb += rgb * glowMask * 0.22;

    // ── Vignette + fine grain ───────────────────────────────────────
    let vig = 1.0 - smoothstep(0.55, 1.05, length(uv - vec2<f32>(0.5))) * 0.16;
    let grain = (hash21(uv * resolution + vec2<f32>(fract(time) * 61.7, fract(time * 0.7) * 43.1)) - 0.5) * 0.02;
    rgb = rgb * vig + grain;

    // Bounded output (≤ ~1.3, HDR-friendly for downstream tonemapping)
    let finalColor = clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.3));

    // Preserve the input alpha from the unshifted source pixel
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = current.a;

    textureStore(writeTexture, coords, vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(finalColor, alpha));
}
