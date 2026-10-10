// ═══════════════════════════════════════════════════════════════════
//  Neon Contour
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha,
//            edge-detection, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: radial pulse front rolling outward from the cursor; starter-flicker cells gated by electricPulse; discrete tube palette (hue softly quantized to six tubes)
//  A packing: diagnostic (isEdge, glowStrength pre-ACES, cursor proximity, alpha)
// ═══════════════════════════════════════════════════════════════════
//  Sobel neon tubes on black. Hue cycles with edge strength and cursor
//  distance; the tubes breathe on a sine pulse. Created 2026-05-30 (Copilot
//  CLI), electric rim/audio pass 2026-05-31 (Grok).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Sobel kernels
const gx: array<f32, 9> = array<f32, 9>(-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0);
const gy: array<f32, 9> = array<f32, 9>(-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0);

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    var p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let texelSize = 1.0 / dims;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let audioBass = audio.x;
    let audioMid = audio.y;
    let audioHigh = audio.z;
    let audioOverall = dot(audio, vec3<f32>(0.5, 0.3, 0.2));
    let audioReactivity = 1.0 + audioOverall * 0.5;

    // Electric pulse: now gates the starter-flicker cells (idea 2).
    let electricPulse = 1.0 + audioBass * 0.7 + sin(time * 8.0) * audioHigh * 0.4;

    // Params
    // x: Threshold, y: Glow, z: CycleSpeed, w: PulseSpeed
    let threshold = u.zoom_params.x;
    let glowIntensity = u.zoom_params.y * mix(2.5, 7.0, audioBass);
    let cycleSpeed = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w;
    let occlusionBalance = 0.5;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Correct aspect ratio for distance
    let aspect = dims.x / dims.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Mouse interaction: Lower threshold near mouse
    let localThreshold = threshold * smoothstep(0.0, 0.4, dist) * mix(1.1, 0.75, audioBass);

    // Sobel Edge Detection
    var edgeX = 0.0;
    var edgeY = 0.0;

    for(var i = -1; i <= 1; i++) {
        for(var j = -1; j <= 1; j++) {
            let offset = vec2<f32>(f32(i), f32(j)) * texelSize;
            let c = textureSampleLevel(
                readTexture,
                u_sampler,
                clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)),
                0.0
            ).rgb;
            let luma = getLuminance(c);
            let idx = (j + 1) * 3 + (i + 1);
            edgeX += luma * gx[idx];
            edgeY += luma * gy[idx];
        }
    }

    let edge = sqrt(edgeX * edgeX + edgeY * edgeY);
    let isEdge = smoothstep(localThreshold, localThreshold + 0.05, edge);

    // Neon Color Calculation
    let baseHue = fract(time * cycleSpeed * audioReactivity * 0.1 + audioHigh * 0.15);
    var hue = fract(baseHue + edge * 2.0 + dist * 0.5);
    // Idea 3 (discrete tube palette): the continuous hue is softly pulled
    // toward one of six tube gases, so neighbouring edges read as the same
    // tube colour instead of a smooth rainbow, while the cycle still glides.
    let tubeHue = round(hue * 6.0) / 6.0;
    hue = mix(hue, tubeHue, 0.35);

    // Idea 1 (radial pulse front) + FIX: phase = time*speed + audio offset (the
    // audio used to multiply the rate). The -dist*6 term turns the breathing
    // into rings (~0.45 uv apart) that roll outward from the cursor.
    let pulsePhase = time * pulseSpeed * 5.0 + audioOverall * 2.0 - dist * 14.0;
    let pulse = sin(pulsePhase) * 0.5 + 0.5;
    let neonColor = hsv2rgb(vec3<f32>(hue, 1.0, 1.0));

    // Idea 2 (starter-flicker cells): a 12x8 grid of hash cells re-rolled at
    // 10 Hz; a cell whose roll falls under the fail probability drops its tube
    // to 40% like a failing neon starter. Probability is rare at idle (~2.5%
    // of cells) and grows with treble, with electricPulse gating the rate.
    let cell = floor(uv * vec2<f32>(12.0, 8.0));
    let roll = hash21(cell + (floor(time * 10.0) % 1024.0) * vec2<f32>(0.37, 0.91));
    let failProb = clamp((0.025 + audioHigh * 0.35) * electricPulse, 0.0, 0.8);
    let starter = select(1.0, 0.4, roll < failProb);

    // Emission calculation (HDR capable)
    var emission = neonColor * isEdge * glowIntensity * (0.55 + 0.9 * pulse) * starter;
    emission += vec3<f32>(0.05 * audioBass, 0.03 * audioMid, 0.08 * audioHigh) * isEdge;

    // Extra glow near mouse — FIX: only on tubes (× isEdge), not a flat disc.
    if (dist < 0.2) {
        emission += neonColor * (0.2 - dist) * 2.0 * glowIntensity * isEdge * starter;
    }
    emission = max(emission, vec3<f32>(0.0));

    // Calculate alpha based on (HDR, pre-ACES) emission intensity
    let glowStrength = length(emission);
    let finalAlpha = clamp(calculateEmissiveAlpha(glowStrength, occlusionBalance), 0.0, 1.0);
    let depth = clamp(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + isEdge * 0.06 + audioBass * 0.02,
        0.0,
        1.0
    );

    // FIX: clamp then ACES on display only; A keeps the diagnostic packing.
    let display = acesToneMap(clamp(emission, vec3<f32>(0.0), vec3<f32>(16.0)));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(display, finalAlpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(isEdge, glowStrength, 1.0 - smoothstep(0.0, 0.2, dist), finalAlpha));
}
