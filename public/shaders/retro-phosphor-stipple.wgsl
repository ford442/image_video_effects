// ═══════════════════════════════════════════════════════════════════
//  retro-phosphor-stipple
//  Category: advanced-hybrid
//  Features: crt-simulation, blue-noise-stippling, temporal-persistence, audio-reactive
//  Complexity: High
//  Chunks From: retro_phosphor_dream (barrel distortion, scanlines, persistence), spec-blue-noise-stipple (blue-noise dots)
//  Created: 2026-04-18
//  By: Agent CB-6 — Alpha & Post-Process Enhancer
//  Upgraded: 2026-11-09
//  Ideas: per-channel phosphor persistence (native CRT, P22 decay); beam-width scanlines (native CRT)
//  A packing: raw phosphor light after persistence (pre-grain/vignette/boost/curve), a = 1; C read as colour history (trails ~2.3-2.8x brighter than HEAD, which re-applied curve+vignette per frame)
// ═══════════════════════════════════════════════════════════════════
//  CRT Phosphor with Blue-Noise Stippling
//  Authentic CRT barrel distortion, scanlines, and phosphor persistence
//  combined with blue-noise distributed phosphor dots. Each RGB channel
//  gets its own blue-noise jittered dot grid for authentic triad feel
//  without regular stripe banding.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

// ═══ CHUNK: hash (from retro_phosphor_dream.wgsl) ═══
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ═══ CHUNK: barrel distortion (from retro_phosphor_dream.wgsl) ═══
fn barrelDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 + strength * r2;
    return centered * distortion + 0.5;
}

fn barrelUndistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 / (1.0 + strength * r2);
    return centered * distortion + 0.5;
}

// ═══ CHUNK: scanlines (from retro_phosphor_dream.wgsl) ═══
// ── Idea 2: beam-width scanlines (native CRT) ───────────────────────────
// The beam spot widens with drive current, so a bright line swells and fills the gap while
// a dim line stays thin. `intensity` (Scanline Intensity) keeps its role as the maximum gap
// depth; `beamLuma` (0..1, local source brightness) fills it back in up to 55 %.
fn scanlines(uv: vec2<f32>, intensity: f32, time: f32, beamLuma: f32) -> f32 {
    let scanline = sin(uv.y * 480.0 * PI + time * 0.1) * 0.5 + 0.5;
    let swell = 1.0 - 0.55 * clamp(beamLuma, 0.0, 1.0);
    return 1.0 - (scanline * intensity * swell);
}

fn interlaceFlicker(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let field = floor(time * 30.0) % 2.0;
    let line = floor(uv.y * 240.0) % 2.0;
    let flicker = select(1.0, 0.85, line == field);
    return 1.0 - (1.0 - flicker) * intensity;
}

// ── Idea 1: per-channel phosphor persistence (native CRT) ───────────────
// P22 phosphors do not decay together: the rare-earth red lingers longest, blue is gone
// first — the warm smear behind a bright object on a dark CRT. decay = (R, G, B); G keeps
// the old per-frame constant 0.85. NOTE the trail is NOT the same as HEAD's: A now stores the
// raw persisted light, where HEAD stored the curved, vignetted, boosted colour and so
// re-applied c/(1+0.5c) and the vignette on every frame (~0.69/frame instead of 0.85).
// Measured on a moving disc: trails are ~2.3-2.8x brighter near the object than HEAD.
fn phosphorGlow(current: vec3<f32>, prev: vec3<f32>, decay: vec3<f32>) -> vec3<f32> {
    return max(current, prev * decay);
}

// ═══ CHUNK: blue-noise offset (from spec-blue-noise-stipple.wgsl) ═══
fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
    return fract(pixelCoord * phi2 + frame * phi2);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let curvature = u.zoom_params.x * 0.3;
    let phosphorScale = mix(8.0, 40.0, u.zoom_params.y);
    let scanlineIntensity = u.zoom_params.z * 0.5;
    let flickerIntensity = u.zoom_params.w * 0.3;
    // R1: HEAD read zoom_config.w (the MOUSE-DOWN flag) as "audio"; bass is plasmaBuffer[0].x
    let audioPulse = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Barrel distortion
    let distortedUV = barrelDistort(uv, curvature);

    // R2: glass edge. HEAD wrapped the opposite screen edge in with fract() where the barrel
    // maps past the border. Replicate the edge for the first ~1.2 % of overflow, then fade
    // to a black bezel over the next ~1.2 %.
    let overflow = max(max(-distortedUV.x, distortedUV.x - 1.0), max(-distortedUV.y, distortedUV.y - 1.0));
    let glass = 1.0 - smoothstep(0.012, 0.024, overflow);

    // Chromatic aberration at edges
    let centered = distortedUV - 0.5;
    let r = length(centered);
    let aberration = curvature * 0.5 * r * r;
    let rUV = distortedUV + normalize(centered + 0.0001) * aberration;
    let gUV = distortedUV;
    let bUV = distortedUV - normalize(centered + 0.0001) * aberration;

    var channelColors = vec3<f32>(0.0);

    // ═══ CHUNK: Blue-noise stippled phosphor triad (hybrid) ═══
    // Each channel gets its own blue-noise jittered dot grid
    let cellSize = 1.0 / phosphorScale;
    let cellId = floor(uv * phosphorScale);
    let cellLocal = fract(uv * phosphorScale) - 0.5;

    // R channel dots
    let jitterR = blueNoiseOffset(cellId + vec2<f32>(0.0, 0.0), time * 0.1);
    let dotCenterR = (jitterR - 0.5) * 0.8;
    let distR = length(cellLocal - dotCenterR);

    // G channel dots (offset)
    let jitterG = blueNoiseOffset(cellId + vec2<f32>(17.0, 31.0), time * 0.1);
    let dotCenterG = (jitterG - 0.5) * 0.8 + vec2<f32>(0.15, 0.0);
    let distG = length(cellLocal - dotCenterG);

    // B channel dots (offset)
    let jitterB = blueNoiseOffset(cellId + vec2<f32>(53.0, 11.0), time * 0.1);
    let dotCenterB = (jitterB - 0.5) * 0.8 - vec2<f32>(0.15, 0.0);
    let distB = length(cellLocal - dotCenterB);

    let dotSize = mix(0.35, 0.6, audioPulse * 0.5);
    let edgeWidth = 0.08;

    let maskR = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distR);
    let maskG = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distG);
    let maskB = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distB);

    let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    channelColors.r = sampleR * maskR * 1.4;
    channelColors.g = sampleG * maskG * 1.4;
    channelColors.b = sampleB * maskB * 1.4;

    var color = channelColors * glass;

    // Scanlines — beam width follows the (unmasked) source brightness
    let beamLuma = dot(vec3<f32>(sampleR, sampleG, sampleB), vec3<f32>(0.299, 0.587, 0.114));
    color *= scanlines(uv, scanlineIntensity, time, beamLuma);

    // Interlaced flicker
    color *= interlaceFlicker(uv, time, flickerIntensity);

    // Temporal phosphor persistence — per-channel decay. A stores only the persisted
    // phosphor light; grain / vignette / boost / curve are display-side. (HEAD stored the
    // curved, vignetted colour, so each frame re-applied them to the trail; the documented
    // decay now actually applies, so trails are ~2.3-2.8x brighter and longer than HEAD's.)
    let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
    let decay = min(vec3<f32>(0.89, 0.85, 0.78) + vec3<f32>(audioPulse * 0.1), vec3<f32>(0.97));
    color = phosphorGlow(color, prevFrame, decay);
    let phosphorState = color;

    // Film grain
    color *= hash(uv + time * 0.1) * 0.1 + 0.95;

    // Vignette
    let edgeDist = length(uv - 0.5) * 1.4;
    let vignette = 1.0 - edgeDist * edgeDist * 0.5;
    color *= vignette;

    // HDR boost
    color = color * (1.0 + audioPulse * 0.5);
    color = max(color, vec3<f32>(0.0));
    color = color / (1.0 + color * 0.5);

    // R4: alpha = emission coverage (smooth source brightness x glass), never below 0.88
    let emission = clamp(max(sampleR, max(sampleG, sampleB)) * glass, 0.0, 1.0);
    let alpha = mix(0.88, 1.0, emission);

    // R3: HEAD stored vec4(0,0,0,1) here, wiping the downstream depth — pass the source depth through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(phosphorState, 1.0));
}
