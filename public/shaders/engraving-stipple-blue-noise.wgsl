// ═══════════════════════════════════════════════════════════════════
//  Engraving Stipple Blue Noise
//  Category: advanced-hybrid
//  Features: engraving-stipple, blue-noise, pointillism, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-02
//  Ideas: drypoint shoulder; raking shadow
//  A packing: ACES display RGBA
//  Chunks From: engraving-stipple.wgsl, spec-blue-noise-stipple.wgsl
//  Created: 2026-04-18
//  By: Agent CB-22 — Artistic & Texture Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Combines traditional copper-plate engraving stipple aesthetics
//  with blue-noise dithered dot placement. Golden-ratio low-
//  discrepancy sequences create perceptually optimal, uniformly-
//  spaced dot distributions that eliminate aliasing and banding.
//  Mouse acts as a raking light source revealing engraved depth.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Blue-noise offset via plastic constant low-discrepancy sequence
fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
    return fract(pixelCoord * phi2 + frame * phi2);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    var uv = vec2<f32>(coord) / res;
    let time = u.config.x;

    // Params
    let density = mix(1.0, 4.0, u.zoom_params.x);
    let threshold_bias = u.zoom_params.y;
    let mouse_light_strength = u.zoom_params.z;
    let burrTexture = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;

    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var luma = getLuma(color);

    // Mouse Interaction: Flashlight / Reveal
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);
    let light_radius = 0.3;
    let bass = plasmaBuffer[0].x;
    let light = smoothstep(light_radius, 0.0, dist) * (1.0 + bass * 0.28);
    luma = luma + light * mouse_light_strength * 0.3;

    // ═══ BLUE-NOISE STIPPLE PLACEMENT ═══
    // Cell-based stippling with blue-noise jitter
    let dotScale = mix(8.0, 40.0, u.zoom_params.x);
    let cellSize = 1.0 / dotScale;
    let cellId = floor(uv * dotScale);
    let cellLocal = fract(uv * dotScale) - 0.5;

    // Blue-noise jittered dot center within each cell
    let jitter = blueNoiseOffset(cellId, time * 0.1);
    let dotCenter = (jitter - 0.5) * 0.8;

    // Sample local color for this cell
    let sampleUV = clamp((cellId + 0.5) / dotScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let localColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let localLuma = getLuma(localColor);

    // Dot size based on luminance (darker = bigger dot)
    let dotSizeBase = mix(0.3, 1.2, u.zoom_params.y);
    let dotSize = mix(dotSizeBase * 0.9, dotSizeBase * 0.15, localLuma);
    let distDot = length(cellLocal - dotCenter);
    let edgeWidth = 0.08;
    let dotMask = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distDot);

    // Secondary dot for mid-tones
    let jitter2 = blueNoiseOffset(cellId + vec2<f32>(37.0, 17.0), time * 0.1);
    let dotCenter2 = (jitter2 - 0.5) * 0.6;
    let dotSize2 = mix(dotSizeBase * 0.5, dotSizeBase * 0.05, localLuma) * 0.7;
    let dist2 = length(cellLocal - dotCenter2);
    let dotMask2 = 1.0 - smoothstep(dotSize2 - edgeWidth, dotSize2 + edgeWidth, dist2);
    let combinedMask = max(dotMask, dotMask2 * 0.5);

    // Engraving plate texture
    let plate_tex = hash12(uv * 80.0) * 0.08 + 0.92;

    // ═══ ENGRAVING INK + BLUE-NOISE DOT FUSION ═══
    let threshold = luma + (threshold_bias - 0.5);
    let isMark = threshold < combinedMask;
    let mark_depth = smoothstep(0.0, 0.3, combinedMask - threshold);

    // Burr effect
    let burr_noise = hash12(uv * vec2<f32>(res) * density * 2.0);
    let burr_effect = smoothstep(0.4, 0.6, burr_noise) * burrTexture;

    let ink = vec3<f32>(0.06, 0.06, 0.08);
    let paper = vec3<f32>(0.94, 0.92, 0.87);
    let mark = select(0.0, 1.0, isMark);

    let depth_alpha = mix(0.6, 0.95, mark_depth);
    var ink_alpha = min(1.0, depth_alpha + burr_effect * 0.3) * mark;
    let depth_darken = mix(0.85, 1.0, mark_depth);
    var inkCol = ink * depth_darken;
    inkCol = mix(inkCol, inkCol * 1.1, burr_effect);
    let chromaticShift = hash22(cellId) - 0.5;
    inkCol = inkCol + chromaticShift.xyx * 0.02;

    let paperDot = dotMask * 0.08;
    var paperCol = paper * plate_tex;
    paperCol = mix(paperCol, paperCol * 0.96, paperDot);
    var final_col = mix(paperCol, inkCol, mark);

    ink_alpha *= plate_tex;
    let edge_feather = smoothstep(0.0, 0.2, mark_depth);
    ink_alpha *= mix(0.85, 1.0, edge_feather);

    // ── Idea 1: drypoint shoulder — a bright ring of raised metal just outside the engraved dot
    let pastDot = distDot - (dotSize + edgeWidth);
    let shoulder = smoothstep(0.0, 0.035, pastDot) * (1.0 - smoothstep(0.035, 0.11, pastDot));
    final_col = final_col + vec3<f32>(0.10, 0.09, 0.06) * shoulder * (1.0 - mark) * burrTexture;

    // ── Idea 2: raking shadow — each dot darkens the plate a short step away from the pointer
    let away = dist_vec / max(dist, 1e-4);
    let shadowCenter = dotCenter + away * 0.12;
    let shadowDist = length(cellLocal - shadowCenter);
    let shadow = (1.0 - smoothstep(dotSize * 0.85, dotSize * 0.85 + 0.14, shadowDist)) * mark * mouse_light_strength;
    final_col = final_col * (1.0 - shadow * 0.4);

    // Mouse light vignette
    final_col = mix(final_col * 0.6, final_col, 0.5 + 0.5 * light);

    let tint_strength = clamp((luma - 0.7) * 0.3, 0.0, 0.3);
    final_col = mix(final_col, color, tint_strength);

    let mapped = acesToneMap(clamp(final_col, vec3<f32>(0.0), vec3<f32>(1.5)));
    let shown = vec4<f32>(mapped, clamp(ink_alpha, 0.0, 1.0));
    textureStore(writeTexture, coord, shown);
    textureStore(dataTextureA, coord, shown);

    let depth_val = mark * (mark_depth + burr_effect * 0.2);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_val, 0.0, 0.0, ink_alpha));
}
