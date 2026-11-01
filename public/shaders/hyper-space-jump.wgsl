// ═══════════════════════════════════════════════════════════════════
//  Hyper-Space Jump
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, relativistic-streaks, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: rim blue-shift; tunnel afterimage from exact C
//  A packing: ACES display RGBA. Depth store stays 0.
// ═══════════════════════════════════════════════════════════════════
//  Brightness-weighted radial streaks. Streak Decay, Chromatic Spread,
//  and Vignette Size drive the existing loop. Depth stays cleared.

#include "_prelude.wgsl"

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Calculate velocity-based alpha for streaks
fn calculateStreakAlpha(
    sampleAlpha: f32,
    luma: f32,
    sampleIndex: f32,
    totalSamples: f32,
    decay: f32
) -> f32 {
    // Bright features streak more prominently
    let brightWeight = smoothstep(0.5, 1.0, luma);
    
    // Distance along streak affects opacity
    let streakFactor = 1.0 - (sampleIndex / totalSamples);
    
    // Decay reduces contribution
    let decayFactor = pow(decay, sampleIndex);
    
    return sampleAlpha * (0.1 + brightWeight * 2.0) * streakFactor * decayFactor;
}

// Calculate relativistic Doppler alpha shift
fn calculateRelativisticAlpha(
    baseAlpha: f32,
    dist: f32,
    strength: f32
) -> f32 {
    // Higher velocity = more time dilation = light accumulation
    let timeDilation = 1.0 + strength * (1.0 - smoothstep(0.0, 1.5, dist));
    
    // But also more scattering
    let scattering = strength * dist * 0.2;
    
    return clamp(baseAlpha * timeDilation - scattering, 0.3, 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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

    let bass = plasmaBuffer[0].x;
    let held = select(1.0, 1.18, u.zoom_config.w > 0.5);
    let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.35) * held;
    let decay = mix(0.88, 0.99, clamp(u.zoom_params.y, 0.0, 1.0));
    let chroma = mix(0.0, 0.012, clamp(u.zoom_params.z, 0.0, 1.0));
    let samples = 30;
    let center = u.zoom_config.yz;

    // Aspect ratio correction
    let aspect = resolution.x / resolution.y;
    let center_aspect = vec2<f32>(center.x * aspect, center.y);
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    let dir = uv_aspect - center_aspect;
    let dist = length(dir);
    let dir_uv = (uv - center);

    // Random jitter for "speed" effect
    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);

    var color_acc = vec4<f32>(0.0);
    var alpha_acc = 0.0;
    var weight_acc = 0.0;

    for (var i = 0; i < samples; i = i + 1) {
        let f = f32(i);
        let offset = dir_uv * (f / f32(samples)) * strength * dist * 10.0;
        let jitter_offset = offset * (noise - 0.5) * 0.1;
        let gUV = clamp(uv - offset + jitter_offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let rUV = clamp(gUV + dir_uv * chroma * f, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(gUV - dir_uv * chroma * f, vec2<f32>(0.0), vec2<f32>(1.0));

        let s_color = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
        let sample_color = vec4<f32>(r, s_color.g, b, s_color.a);

        // Calculate streak alpha
        let luma = getLuma(sample_color.rgb);
        let weight = pow(decay, f) * (0.1 + smoothstep(0.5, 1.0, luma) * 2.0);
        
        // Accumulate with alpha
        let streakAlpha = calculateStreakAlpha(s_color.a, luma, f, f32(samples), decay);

        color_acc = color_acc + sample_color * weight;
        alpha_acc = alpha_acc + streakAlpha * weight;
        weight_acc = weight_acc + weight;
    }

    let safeW = max(weight_acc, 1e-4);
    let final_color = color_acc / safeW;
    let baseAlpha = alpha_acc / safeW;
    let finalAlpha = calculateRelativisticAlpha(baseAlpha, dist, strength);

    let vig0 = mix(0.15, 0.85, clamp(u.zoom_params.w, 0.0, 1.0));
    let vignette = 1.0 - smoothstep(vig0, vig0 + 1.0, dist);
    var outputRGB = mix(vec3<f32>(0.0), final_color.rgb, vignette);

    // ── Idea 1: rim blue-shift. Jump Strength scales how far the rim goes blue.
    let rim = smoothstep(0.15, 1.1, dist) * clamp(strength * 12.0, 0.0, 1.0);
    let shifted = outputRGB * vec3<f32>(0.62, 0.78, 1.45);
    let shiftLuma = dot(outputRGB, vec3<f32>(0.299, 0.587, 0.114));
    outputRGB = mix(outputRGB, mix(vec3<f32>(shiftLuma), shifted, 0.75), rim * 0.6);

    // ── Idea 2: tunnel afterimage from exact C.
    let prev = textureLoad(dataTextureC, coord, 0);
    outputRGB = mix(outputRGB, prev.rgb, 0.16);

    let vignetteAlpha = clamp(finalAlpha * vignette, 0.0, 1.0);
    let display = acesToneMap(max(outputRGB, vec3<f32>(0.0)));
    let outColor = vec4<f32>(display, vignetteAlpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
