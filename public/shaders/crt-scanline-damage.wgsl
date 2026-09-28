// ═══════════════════════════════════════════════════════════════════
//  CRT Scanline Damage
//  Category: image
//  Features: audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: misconvergence swirl (degauss rings pull the R/G/B rasters apart radially with a rotating magenta/green purity blotch that settles); flyback retrace lines (faint diagonal retrace sweeps during the dark-band fault); radial chromatic barrel (RGB split grows radially toward the tube edges)
//  A packing: pre-ACES linear display RGB + semantic alpha (opaque bezel outside the warp); C read back as that linear colour for phosphor persistence
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sampleClamped(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let scanlineIntensity = u.zoom_params.x;
    let distortionAmount = u.zoom_params.y;
    let flickerSpeed = u.zoom_params.z;
    let rgbSeparation = u.zoom_params.w;

    let depth = textureLoad(readDepthTexture, coords, 0).r;

    // Depth-aware barrel distortion: closer objects distort more
    let centered = uv - vec2<f32>(0.5);
    let r2 = dot(centered, centered);
    let r4 = r2 * r2;
    let depthDistortion = distortionAmount * (1.0 + depth * 0.5);
    let distortion = 1.0 + depthDistortion * r2 + depthDistortion * 0.5 * r4;
    var distortedUV = centered * distortion + vec2<f32>(0.5);

    // Clicks bruise the tube locally and launch degauss rings through the
    // sampling coordinates. Ripple positions are normalized canvas UVs.
    let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
    var rippleDamage = 0.0;
    var degaussBand = 0.0;
    // IDEA 1 accumulators: radial misconvergence vector and the purity blotch tint.
    var misVec = vec2<f32>(0.0);
    var purityTint = vec3<f32>(0.0);
    var purityAmt = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age < 0.0 || age > 2.4) { continue; }
        let deltaAspect = (uv - rp.xy) * aspectVec;
        let dist = length(deltaAspect);
        let fade = exp(-age * 1.25);
        let ring = exp(-abs(dist - age * 0.34) * 48.0) * fade;
        let core = smoothstep(0.20, 0.0, dist) * fade;
        let wave = sin(dist * 82.0 - age * 18.0) * exp(-dist * 5.5) * fade;
        rippleDamage = max(rippleDamage, max(ring, core * 0.45));
        degaussBand += wave;
        let radialUV = (deltaAspect / max(dist, 1e-4)) / aspectVec;
        distortedUV = distortedUV + radialUV * wave * 0.004 * (0.5 + distortionAmount);

        // IDEA 1 — misconvergence swirl. The degauss front magnetises the shadow mask: inside
        // the ring the three rasters are pulled apart along the radial, strongest just behind
        // the front and relaxing as the field collapses (settles over ~2 s). A purity blotch
        // (magenta vs green, the classic magnet-near-the-tube stain) rotates around the click
        // point with age and fades with the same relaxation.
        let behind = smoothstep(0.0, 0.08, age * 0.34 - dist);
        let relax = exp(-age * 1.6);
        misVec += radialUV * behind * relax * exp(-dist * 2.5);
        let ang = atan2(deltaAspect.y, deltaAspect.x);
        let lobe = 0.5 + 0.5 * sin(ang * 2.0 + age * 3.5 + rp.x * 9.0);
        let blotch = behind * relax * smoothstep(0.45, 0.05, dist);
        purityTint += mix(vec3<f32>(1.18, 0.82, 1.14), vec3<f32>(0.84, 1.16, 0.86), lobe) * blotch;
        purityAmt += blotch;
    }
    // Cap the accumulated degauss sum so stacked clicks cannot blow out the channels.
    degaussBand = clamp(degaussBand, -1.5, 1.5);
    let misLen = length(misVec);
    let misconvergence = misVec / max(misLen, 1e-4) * min(misLen, 1.0) * 0.012 * (1.0 + mids * 0.5);
    purityAmt = min(purityAmt, 1.0);
    let purity = select(vec3<f32>(1.0), purityTint / max(purityAmt, 1e-4), purityAmt > 1e-4);

    // Audio-driven RGB channel separation (HEAD's horizontal split) plus
    // IDEA 3 — radial chromatic barrel: the split also grows radially toward the tube edges,
    // as a real barrel-lensed tube misregisters its colour rasters more at the corners.
    let sep = rgbSeparation * 0.008 * (1.0 + bass * 0.4 + rippleDamage * 0.8);
    let radialSep = centered * r2 * rgbSeparation * 0.10 * (1.0 + bass * 0.4);
    let chromaOffset = vec2<f32>(sep, 0.0) + radialSep + misconvergence;
    let rUV = distortedUV + chromaOffset;
    let gUV = distortedUV - misconvergence * 0.35;
    let bUV = distortedUV - chromaOffset;

    // Black bezel outside the warped raster (HEAD clamped, which smeared the edge texels).
    let edgeSoft = 1.5 / res;
    let inside = smoothstep(vec2<f32>(0.0), edgeSoft, distortedUV) * smoothstep(vec2<f32>(0.0), edgeSoft, 1.0 - distortedUV);
    let tubeMask = inside.x * inside.y;

    var col = vec3<f32>(0.0);
    col.r = sampleClamped(rUV).r;
    col.g = sampleClamped(gUV).g;
    col.b = sampleClamped(bUV).b;
    let baseAlpha = sampleClamped(distortedUV).a;
    col *= purity;

    // Real raster: HEAD evaluated sin(k*pi) at texel centres, a constant 0.5. A 4-row beam
    // profile on integer screen rows averages to the same 0.925 at the default slider.
    let scanline = sin(f32(global_id.y) * PI * 0.5) * 0.5 + 0.5;
    let scanlineMask = mix(1.0, 0.85 + scanline * 0.15, scanlineIntensity);
    col = col * scanlineMask;

    let pixelX = f32(global_id.x) % 3.0;
    let phosphorR = select(1.0, 0.85, pixelX != 0.0);
    let phosphorG = select(1.0, 0.85, pixelX != 1.0);
    let phosphorB = select(1.0, 0.85, pixelX != 2.0);
    col = col * vec3<f32>(phosphorR, phosphorG, phosphorB);

    let flicker = 1.0 + sin(time * flickerSpeed * 10.0) * 0.03 * flickerSpeed;
    col = col * flicker;

    let rollTrigger = hash11(floor(time * 2.0)) < 0.05;
    let rollOffset = fract(hash11(floor(time * 2.0) + 100.0) + time * 0.5);
    let inRollBand = abs(uv.y - rollOffset) < 0.02;
    col = select(col, col * 0.5 + vec3<f32>(0.05), rollTrigger && inRollBand);

    // IDEA 2 — flyback retrace lines. While the vertical-hold fault is active the blanking
    // fails and the beam's return sweeps show: faint bright diagonals (steep, slightly
    // left-leaning) racing upward across the picture, brighter near the dark band.
    let retracePhase = fract((uv.y - uv.x * 0.18) * 7.0 + time * 4.0);
    let retraceLine = smoothstep(0.06, 0.0, abs(retracePhase - 0.5));
    let retraceGain = select(0.0, 1.0, rollTrigger) * (0.08 + smoothstep(0.25, 0.0, abs(uv.y - rollOffset)) * 0.14) * (1.0 + mids * 0.6);
    col += vec3<f32>(0.9, 0.95, 1.0) * retraceLine * retraceGain;

    // Treble now drives genuinely damaged static: sparse bright/dark snow and
    // short horizontal scar bands, rather than being a dead aggregate read.
    let staticSeed = hash21(vec2<f32>(global_id.xy) + vec2<f32>(floor(time * 31.0), floor(time * 17.0)));
    let staticGate = step(0.91 - clamp(treble, 0.0, 1.5) * 0.10, staticSeed);
    let staticSnow = (staticSeed - 0.5) * staticGate * treble * 0.28;
    let scarRow = floor(uv.y * res.y * 0.25);
    let scarNoise = hash11(scarRow + floor(time * 9.0) * 19.0);
    let scar = step(0.965 - clamp(treble, 0.0, 1.5) * 0.025, scarNoise)
      * (hash21(vec2<f32>(f32(global_id.x), scarRow)) - 0.5) * treble * 0.20;
    col = col + vec3<f32>(staticSnow + scar);

    // Degauss shifts channels in opposite directions while the local damage
    // briefly desaturates and blooms the struck phosphor.
    col += vec3<f32>(0.10, -0.025, 0.13) * degaussBand * (0.35 + mids * 0.25);
    let damagedLuma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    col = mix(col, vec3<f32>(damagedLuma) + vec3<f32>(0.04, 0.015, 0.06), rippleDamage * 0.28);

    let edgeDarken = 1.0 - smoothstep(0.3, 0.7, r2) * 0.3;
    col = col * edgeDarken;
    col = max(col, vec3<f32>(0.0)) * tubeMask;

    // Temporal phosphor decay: previous frame bleeds in for CRT persistence.
    // C holds last frame's pre-ACES linear colour (A packing), read exactly per texel.
    let prev = max(textureLoad(dataTextureC, coords, 0).rgb, vec3<f32>(0.0));
    let phosphorDecay = mix(col, prev * 0.85, 0.06 + mids * 0.02);
    col = mix(col, phosphorDecay, 0.5);
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(4.0));

    // Semantic alpha: source coverage inside the tube, opaque black bezel outside.
    let alpha = mix(1.0, clamp(baseAlpha + rippleDamage * 0.2, 0.0, 1.0), tubeMask);

    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
    textureStore(writeTexture, coords, vec4<f32>(acesToneMap(col), alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
