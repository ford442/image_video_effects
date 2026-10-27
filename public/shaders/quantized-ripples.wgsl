// ═══════════════════════════════════════════════════════════════════
//  Haptic Ripple Field
//  Category: image
//  Features: mouse-driven, depth-aware, haptic-response, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: deep-water dispersion (§12.2D); crest posterization
//  A packing: raw (effectStrength, shimmer, roughness, alpha); C unread
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    let h = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(dot(h, vec2<f32>(1.0, 1.3))) * 43758.5453123);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn decayProfile(elapsed: f32, damping: f32, mode: f32) -> f32 {
    let modePos = clamp(mode * 2.0, 0.0, 2.0);
    let linearW = max(1.0 - abs(modePos - 0.0), 0.0);
    let expW = max(1.0 - abs(modePos - 1.0), 0.0);
    let critW = max(1.0 - abs(modePos - 2.0), 0.0);
    let norm = max(linearW + expW + critW, 0.0001);

    let linearDecay = max(1.0 - elapsed * (0.7 + damping * 0.2), 0.0);
    let exponentialDecay = exp(-elapsed * (0.8 + damping * 1.4));
    let criticallyDamped = (1.0 + elapsed * (2.0 + damping * 2.5)) * exp(-elapsed * (1.5 + damping * 2.2));

    return (linearDecay * linearW + exponentialDecay * expW + criticallyDamped * critW) / norm;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);

    let stiffness = mix(8.0, 54.0, u.zoom_params.x);
    let damping = mix(0.15, 2.2, u.zoom_params.y);
    let roughness = u.zoom_params.z;
    let decayMode = u.zoom_params.w;

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let rippleCount = min(u32(u.config.y), 50u);

    var interference = 0.0;
    var energy = 0.0;
    var displacement = vec2<f32>(0.0);
    var shimmer = 0.0;

    for (var i: u32 = 0u; i < 50u; i = i + 1u) {
        if (i >= rippleCount) {
            break;
        }

        let ripple = u.ripples[i];
        let age = max(time - ripple.z, 0.0);
        if (age <= 3.5) {
            var velocity = vec2<f32>(0.0);
            if (i > 0u) {
                let prev = u.ripples[i - 1u];
                let dt = max(ripple.z - prev.z, 0.016);
                velocity = (ripple.xy - prev.xy) / dt;
            }

            let rel = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let dist = length(rel);
            let dir = select(vec2<f32>(0.0), rel / dist, dist > 0.0001);
            let roughNoise = hash12(floor((uv + vec2<f32>(f32(i) * 0.071, age)) * mix(8.0, 48.0, roughness) * 32.0));
            let localFreq = stiffness * mix(0.8, 1.65, roughNoise);
            let pressure = 0.55 + clamp(length(velocity) * 0.05, 0.0, 1.4);
            let decay = decayProfile(age, damping, decayMode);
            let phaseSpeed = 2.0 + stiffness * 0.18;
            let phase = dist * localFreq - age * phaseSpeed + roughNoise * 6.2831853 * roughness;
            let wave = sin(phase);
            // ── Idea 1: deep-water dispersion (§12.2D) ──────────────
            // The octave travels at 1/sqrt(2) the phase speed, so the
            // ring breaks into a short train. Stiffness sets the fundamental.
            let phase2 = dist * localFreq * 2.0 - age * phaseSpeed / sqrt(2.0) + roughNoise * 6.2831853 * roughness;
            let wave2 = sin(phase2) * 0.42;
            let envelope = decay / (1.0 + dist * (3.0 + damping * 2.0));

            interference = interference + (wave + wave2) * envelope * pressure;
            energy = energy + envelope * pressure;
            displacement = displacement + dir * (wave + wave2 * 0.5) * envelope * pressure;
            shimmer = shimmer + (0.5 + 0.5 * cos(phase * 0.5)) * envelope;
        }
    }

    if (rippleCount == 0u) {
        let rel = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
        let dist = length(rel);
        let dir = select(vec2<f32>(0.0), rel / dist, dist > 0.0001);
        let phaseSpeed = 2.0 + stiffness * 0.12;
        let phase = dist * stiffness - time * phaseSpeed;
        let wave = sin(phase);
        let phase2 = dist * stiffness * 2.0 - time * phaseSpeed / sqrt(2.0);
        let wave2 = sin(phase2) * 0.42;
        let envelope = (0.5 + 0.5 * u.zoom_config.w) / (1.0 + dist * 6.0);
        interference = interference + (wave + wave2) * envelope;
        energy = energy + envelope;
        displacement = displacement + dir * (wave + wave2 * 0.5) * envelope * 0.5;
        shimmer = shimmer + envelope;
    }

    let effectStrength = clamp(abs(interference) * 0.9 + energy * 0.35, 0.0, 1.0);
    let displacedUV = clamp(uv + displacement * (0.002 + roughness * 0.012), vec2<f32>(0.0), vec2<f32>(1.0));
    let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    let levels = max(3.0, floor(3.0 + stiffness * 0.25 + shimmer * 8.0));
    // ── Idea 2: crest posterization ─────────────────────────────────
    // The level count drops on the ring crest. Between rings the base
    // count, still set by stiffness, remains.
    let crestQ = smoothstep(0.12, 0.7, abs(interference));
    let crestLevels = max(3.0, floor(levels * mix(1.0, 0.42, crestQ)));
    var quantized = floor(displacedColor.rgb * crestLevels + interference * 0.75) / crestLevels;
    let touchTexture = 0.5 + 0.5 * sin((displacedUV.x + displacedUV.y) * mix(12.0, 120.0, roughness) + interference * 4.0);
    quantized = mix(quantized, quantized * (0.85 + 0.3 * touchTexture), roughness * effectStrength * 0.45);

    let finalColor = mix(original.rgb, quantized, effectStrength);
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.7, 1.0, depthSample);
    let finalAlpha = clamp(mix(original.a, depthAlpha, 0.35 * effectStrength) + effectStrength * 0.15 + luma * 0.05, 0.0, 1.0);

    let display = aces_tonemap(max(finalColor, vec3<f32>(0.0)));
    textureStore(writeTexture, coord, vec4<f32>(display, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthSample, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(effectStrength, shimmer, roughness, finalAlpha));
}
