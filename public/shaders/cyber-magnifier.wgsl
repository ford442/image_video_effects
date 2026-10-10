// ═══════════════════════════════════════════════════════════════════
//  Cyber Magnifier
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04
//  Ideas: digital-zoom texel grid at high magnification; sweep-traced Sobel outlines; depth rangefinder arc
//  A packing: masks (inLens, border, sweep, alpha); texel (0,0) = (glide.x, glide.y, 7 marker, 1) lens state
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

// Hue-preserving highlight clamp: scales rgb toward a peak ceiling while
// keeping channel ratios (and therefore hue) intact. Tames the additive
// HUD glow stack before the border/vignette mixes push cyan into clip.
fn lumaOf(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn huePreserveClamp(rgb: vec3<f32>, ceiling: f32) -> vec3<f32> {
    let peak = max(rgb.r, max(rgb.g, rgb.b));
    if (peak > ceiling) {
        return rgb * (ceiling / peak);
    }
    return rgb;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    // ── Lens glide ───────────────────────────────────────────────────
    // HEAD kept the eased centre in extraBuffer[133..134], written by every
    // pixel. The host re-uploads extraBuffer each frame, so after 2 s the lens
    // sat at 0.16 x mouse. The centre now lives in A texel (0,0) and is read
    // back with an exact C load: every pixel computes the same glide from last
    // frame's value, and only (0,0) stores it.
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let hasGlide = abs(glideState.z - 7.0) < 0.01;
    let lensCenter = select(rawMouse, glideState.xy, hasGlide);
    let glide = lensCenter + (rawMouse - lensCenter) * 0.16;
    let mouse = glide;
    // ── Slider-driven constants (u.zoom_params.x/y/z/w) ──────────────
    let baseMagnification = mix(1.0, 4.0, u.zoom_params.x);
    let radius = mix(0.1, 0.45, u.zoom_params.y);
    let aberrationStrength = u.zoom_params.z * 0.05;
    let gridOpacity = u.zoom_params.w;

    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Aspect-corrected distance math (VERBATIM from original algorithm).
    let distVec = uv - mouse;
    let distVecAspect = distVec * vec2<f32>(aspect, 1.0);
    let dist = length(distVecAspect);

    // ── Click lens flares + magnification pulse ──────────────────────
    // Each live ripple spawns an expanding cyan flare ring hugging the lens
    // border; young clicks also kick the magnification up by ~25%.
    var flareGlow = 0.0;
    var magPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let age = time - u.ripples[i].z;
        if (age > 0.0 && age < 1.5) {
            let fade = 1.0 - age / 1.5;            // alpha decays over ~1.5s
            let flareRadius = radius + age * 0.22; // ring expands outward
            let ringD = abs(dist - flareRadius);
            flareGlow = flareGlow + smoothstep(0.018, 0.0, ringD) * fade * fade;
            if (age < 0.5) {
                // Brief +25% magnification pulse while the click is young.
                magPulse = max(magPulse, 0.25 * (1.0 - age / 0.5));
            }
        }
    }
    let magnification = baseMagnification * (1.0 + magPulse);

    let edgeWidth = 0.005;
    let inLens = 1.0 - smoothstep(radius, radius + edgeWidth, dist);
    let uvZoomed = clamp((uv - mouse) / magnification + mouse, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let safeDir = distVecAspect / max(dist, 0.0001);
    let aberrationOffset = vec2<f32>(safeDir.x / aspect, safeDir.y) *
        aberrationStrength * (dist / max(radius, 0.001)) * (1.0 + treble * 0.4);

    // 3-tap r/g/b chromatic-aberration sampling pattern (VERBATIM).
    let rUV = clamp(uvZoomed - aberrationOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = uvZoomed;
    let bUV = clamp(uvZoomed + aberrationOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let smoothLens = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );
    // Idea 1: digital zoom. Past ~2.5x the magnifier stops interpolating and
    // shows the source texels themselves, each one outlined by the texel grid.
    let texRes = vec2<f32>(textureDimensions(readTexture));
    let pixAmt = smoothstep(2.2, 3.6, magnification);
    let snapR = (floor(rUV * texRes) + vec2<f32>(0.5)) / texRes;
    let snapG = (floor(gUV * texRes) + vec2<f32>(0.5)) / texRes;
    let snapB = (floor(bUV * texRes) + vec2<f32>(0.5)) / texRes;
    let blockLens = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, snapR, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, snapG, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, snapB, 0.0).b
    );
    let texelLocal = abs(fract(gUV * texRes) - 0.5);
    let texelLine = smoothstep(0.42, 0.5, max(texelLocal.x, texelLocal.y)) * pixAmt;
    let lensColor = vec4<f32>(mix(smoothLens, blockLens, pixAmt) * (1.0 - texelLine * 0.45), 1.0);
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var finalColor = mix(bgColor, lensColor, inLens);

    // ── HUD overlay: grid, expanding rings, radar sweep ──────────────
    let gridUV = distVecAspect * (18.0 + mids * 18.0);
    let gridLines = abs(fract(gridUV - 0.5) - 0.5);
    let lineMask = smoothstep(0.48, 0.43, min(gridLines.x, gridLines.y));
    // Fixed rates: scaling time by live audio made rings and sweep jump phase.
    // Audio now widens and brightens them instead.
    let ringPhase = abs(fract(length(gridUV) - time * 0.8) - 0.5);
    let ringMask = smoothstep(0.18 + bass * 0.08, 0.04, ringPhase);
    let scanAngle = atan2(distVecAspect.y, distVecAspect.x);
    let sweepPhase = time * 1.6;
    let sweep = smoothstep(0.82 - treble * 0.12, 0.99, cos(scanAngle - sweepPhase));

    // Idea 2: sweep-traced outlines. Sobel edges of the magnified image light
    // up as the radar beam passes over them and fade out behind it.
    let zt = vec2<f32>(1.0) / texRes / magnification * 1.5;
    let gx = lumaOf(textureSampleLevel(readTexture, u_sampler, clamp(gUV + vec2<f32>(zt.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb)
           - lumaOf(textureSampleLevel(readTexture, u_sampler, clamp(gUV - vec2<f32>(zt.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
    let gy = lumaOf(textureSampleLevel(readTexture, u_sampler, clamp(gUV + vec2<f32>(0.0, zt.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb)
           - lumaOf(textureSampleLevel(readTexture, u_sampler, clamp(gUV - vec2<f32>(0.0, zt.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
    let edge = smoothstep(0.06, 0.3, length(vec2<f32>(gx, gy)));
    let behind = fract((sweepPhase - scanAngle) / 6.28318530718);
    let traced = edge * exp(-behind * 5.0) * inLens;

    let hudGlow = vec4<f32>(0.0, 1.0, 1.0, 1.0) * ((lineMask * 0.18 + ringMask * 0.12 + sweep * 0.2) * gridOpacity * inLens + traced * (0.25 + gridOpacity * 0.45));
    finalColor = finalColor + hudGlow;

    // Tame the stacked additive glow BEFORE the border/vignette mixes so
    // hot bass + full grid opacity cannot clip the cyan HUD ugly.
    finalColor = vec4<f32>(huePreserveClamp(finalColor.rgb, 1.2), finalColor.a);

    let border = smoothstep(edgeWidth, 0.0, abs(dist - radius));
    finalColor = mix(finalColor, vec4<f32>(0.25, 0.9, 1.0, 1.0), border * (0.8 + bass * 0.2));

    // Click flare rings ride on top of the border, hue-clamped with it.
    finalColor = vec4<f32>(finalColor.rgb + vec3<f32>(0.2, 0.9, 1.0) * flareGlow * (0.6 + bass * 0.4), finalColor.a);
    finalColor = vec4<f32>(huePreserveClamp(finalColor.rgb, 1.2), finalColor.a);

    // Idea 3: rangefinder. An arc of ticks outside the border fills clockwise
    // from 12 o'clock in proportion to the depth under the lens centre.
    let centreDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, mouse, 0.0).r;
    let arcBand = 1.0 - smoothstep(0.003, 0.006, abs(dist - (radius + 0.018)));
    let arcAngle = fract((scanAngle + 1.5707963) / 6.28318530718);
    let arcFill = 1.0 - step(centreDepth * 0.75, arcAngle);
    let tick = 1.0 - smoothstep(0.08, 0.2, abs(fract(arcAngle * 36.0) - 0.5) * 2.0);
    let rangeMark = arcBand * mix(tick * 0.25, 0.4 + tick * 0.6, arcFill);
    finalColor = vec4<f32>(finalColor.rgb + vec3<f32>(0.35, 1.0, 0.95) * rangeMark * (0.5 + gridOpacity * 0.5), finalColor.a);

    let vignette = smoothstep(radius, radius + 0.2, dist);
    finalColor = mix(finalColor, finalColor * (0.65 - mids * 0.08), vignette * 0.55);

    let alpha = clamp(bgColor.a * 0.28 + inLens * 0.28 + border * 0.28 + sweep * 0.12 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, gUV, 0.0).r + inLens * 0.04, 0.0, 1.0);
    let outPixel = vec4<f32>(finalColor.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    // dataTextureA packing: (inLens, border, sweep, alpha) mask data — not color.
    var aOut = vec4<f32>(inLens, border, sweep, alpha);
    if (global_id.x == 0u && global_id.y == 0u) {
        aOut = vec4<f32>(glide, 7.0, 1.0);
    }
    textureStore(dataTextureA, vec2<i32>(global_id.xy), aOut);
}
