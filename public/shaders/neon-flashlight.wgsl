// ═══════════════════════════════════════════════════════════════════
//  Neon Flashlight
//  Category: lighting-effects
//  Features: mouse-driven, neon, edge-light, audio-pulse, depth-fog, edge-reveal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-11, 2026-10-27
//  Ideas: umbra vs penumbra cone; specular catch on edges inside the cone; inverse-square core (§12.2F); hot core
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let mids = select(0.0, plasmaBuffer[0].y, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // JSON: radius, intensity, threshold, ambient
    let beamRadius = max(u.zoom_params.x * 0.45 + 0.04, 0.02);
    let intensity = u.zoom_params.y * 3.0;
    let edgeThreshold = u.zoom_params.z * 0.1 + 0.02;
    let ambient = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let innerR = beamRadius * (0.55 - held * 0.12);
    let outerR = beamRadius * (1.0 - held * 0.15);
    let umbra = 1.0 - smoothstep(innerR * 0.85, innerR, mouseDist);
    let penumbra = (1.0 - smoothstep(innerR, outerR, mouseDist)) * (1.0 - umbra);
    // ── Idea: inverse-square core (§12.2F) — finite hotspot, cone still ends at the penumbra.
    let r0 = max(beamRadius * 0.5, 0.02);
    let inv = 1.0 / ((mouseDist * mouseDist) / (r0 * r0) + 1.0);
    let beamFalloff = umbra * (0.35 + 0.65 * inv) + penumbra * 0.45 * inv;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length(uv - event.xy) - age * 0.4) * 65.0);
    }

    let l = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(pixelSize.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(pixelSize.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let t = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, pixelSize.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, pixelSize.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let edge = length(r - l) + length(b - t) * 0.5;

    let pulse = 1.0 + bass * 0.8 + treble * 0.4;
    let hueShift = treble * 1.5;
    let audioNeon = vec3<f32>(
        0.5 + 0.5 * sin(time + hueShift),
        0.5 + 0.5 * sin(time + 2.09 + hueShift),
        0.5 + 0.5 * sin(time + 4.18)
    );

    let coneRibs = pow(0.5 + 0.5 * sin(atan2(uv.y - mousePos.y, uv.x - mousePos.x) * 18.0 + time * 2.0), 5.0) * beamFalloff;
    let sweep = exp(-abs(fract(mouseDist * 3.0 - time * (0.12 + mids * 0.2)) - 0.5) * 16.0);
    let specCatch = pow(edge * 3.0, 1.6) * (umbra + penumbra * 0.3);
    // ── Idea: hot core — umbra goes white, penumbra keeps the neon hue.
    let beamTint = mix(audioNeon, vec3<f32>(0.92, 0.96, 1.0), umbra * inv);
    let emission = beamTint * (
        edge * beamFalloff * intensity * pulse
        + specCatch * intensity * 1.4
        + coneRibs * 0.22
        + sweep * 0.12
        + clickFront * 0.35
    );
    let litPhoto = src.rgb * (ambient * 0.35 + beamFalloff * (0.55 + umbra * 0.45));
    let color = aces(litPhoto + emission);
    let alpha = edgePreserveAlpha(uv, pixelSize, edgeThreshold) * max(beamFalloff, ambient * 0.4) * (0.8 + bass * 0.4) * src.a;

    let display = vec4<f32>(color, alpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), display);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
}
