// ═══════════════════════════════════════════════════════════════════
//  spec-importance-sampled-bokeh
//  Category: advanced-hybrid
//  Features: importance-sampling, bokeh, HDR, depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-21
//  Ideas: cat's eye; Airy disc (§12.2F)
//  A packing: linear bokeh RGB + importance alpha in A (C unread); ACES on writeTexture only
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Importance-Sampled Bokeh Blur
//  Bokeh blur where sample distribution is guided by image brightness.
//  Bright pixels act as point light sources creating bokeh highlights.
//  Uses golden angle spiral with importance weighting.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn airyDisc(x: f32) -> f32 {
    let xs = clamp(abs(x), 0.001, 6.5);
    let x2 = xs * xs;
    let j1 = xs * (0.5 - x2 * (0.0625 - x2 * (0.0026042 - x2 * 0.0000543)));
    let v = 2.0 * j1 / xs;
    return max(v * v, 0.0);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0u].x;
    let mids = plasmaBuffer[0u].y;
    let treble = plasmaBuffer[0u].z;

    let baseRadius = mix(0.01, 0.08, u.zoom_params.x);
    let shapePower = mix(0.5, 4.0, u.zoom_params.y);
    var brightnessBoost = mix(0.5, 3.0, u.zoom_params.z) * (1.0 + bass * 0.2 + mids * 0.1);
    let chromaAmount = mix(0.0, 0.05, u.zoom_params.w) * (1.0 + treble * 0.15);

    // A critically-damped focus pull follows the normalized cursor. Every
    // invocation computes the same current-frame state; (0,0) persists it.
    let rawMouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    var focusPos = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var focusVel = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let focusInitialized = extraBuffer[137u] >= 0.5;
    if (!focusInitialized) {
        focusPos = rawMouse;
        focusVel = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), focusInitialized);
    let springOmega = 9.0;
    let focusAccel = springOmega * springOmega * (rawMouse - focusPos) - 2.0 * springOmega * focusVel;
    focusVel += focusAccel * springDt;
    focusPos = clamp(focusPos + focusVel * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133u] = focusPos.x;
        extraBuffer[134u] = focusPos.y;
        extraBuffer[135u] = focusVel.x;
        extraBuffer[136u] = focusVel.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    let aspect = res.x / max(res.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let focusDistance = length((uv - focusPos) * aspectVec);
    let focusMask = exp(-focusDistance * focusDistance * 18.0);

    // The sampled scene depth now drives the advertised depth-of-field:
    // pixels matching the cursor's depth stay tighter near the focus pull.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let focalDepth = textureSampleLevel(
        readDepthTexture, non_filtering_sampler,
        clamp(focusPos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0
    ).r;
    let depthDefocus = smoothstep(0.015, 0.4, abs(depth - focalDepth));
    let focusRadiusScale = mix(1.0, mix(0.4, 1.35, depthDefocus), focusMask);
    let radius = baseRadius * focusRadiusScale;

    // Clicks rack focus through expanding sharp rings and briefly bloom the
    // importance gain without changing the raw bokeh accumulation contract.
    var clickFocus = 0.0;
    var clickBloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.6) {
            let clickDistance = length((uv - ripple.xy) * aspectVec);
            let ring = exp(-abs(clickDistance - age * 0.38) * 30.0) * exp(-age * 1.4);
            clickFocus += ring;
            clickBloom += ring * 0.2;
        }
    }

    let region = min(u32(clamp(uv.x, 0.0, 0.9999) * 8.0), 7u);
    let regionVoice = plasmaBuffer[(region % 8u) + 1u].x;
    brightnessBoost *= 1.0 + regionVoice * 0.25 + clickBloom;

    // Golden angle spiral sampling with importance weighting
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let sampleCount = 48;

    for (var i: i32 = 0; i < sampleCount; i = i + 1) {
        let jitter = hash22(vec2<f32>(gid.xy) + vec2<f32>(f32(i) * 17.0, f32(i) * 31.0));
        let angle = f32(i) * 2.39996322973 + (jitter.x - 0.5) * 0.08;
        let r = sqrt(f32(i) / f32(sampleCount)) * radius * mix(0.98, 1.02, jitter.y);
        let offset = vec2<f32>(cos(angle), sin(angle)) * r;
        // ── Idea 1: cat's eye ─────────────────────────────────────────
        // Off-axis the disk is squeezed along the field vector. Centre stays
        // round. A wider Bokeh Radius clips more, as a real iris does.
        let field = uv - vec2<f32>(0.5);
        let fieldLen = length(field);
        let fieldDir = field / max(fieldLen, 0.0001);
        let squeeze = clamp(fieldLen * fieldLen * (1.4 + baseRadius * 12.0), 0.0, 0.7);
        let eyeOffset = offset - fieldDir * dot(offset, fieldDir) * squeeze;

        let sampleUV = uv + eyeOffset;
        // Clamp to avoid wrapping artifacts in bokeh
        let clampedUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));
        let sample = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);
        let luma = dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));

        // Importance weight: bright pixels contribute more.
        // ── Idea 2: Airy disc (§12.2F) ────────────────────────────────
        // Bright taps take the diffraction profile of r/radius. Dim taps
        // keep the flat disk. Highlight Shape is still the luma power.
        let importance = pow(max(luma + 0.1, 0.001), shapePower)
            * mix(1.0, airyDisc((r / max(radius, 0.0001)) * 5.2), smoothstep(0.4, 0.85, luma));

        // Chromatic aberration per sample based on radius
        let chromaShift = chromaAmount * r / max(radius, 0.0001);
        var shiftedColor = sample.rgb;
        let rSample = textureSampleLevel(readTexture, u_sampler, clamp(clampedUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let bSample = textureSampleLevel(readTexture, u_sampler, clamp(clampedUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        shiftedColor = vec3<f32>(rSample, shiftedColor.g, bSample);

        accumColor += shiftedColor * importance * brightnessBoost;
        accumWeight += importance;
    }

    let result = accumColor / max(accumWeight, 0.001);

    // Preserve some sharpness from center
    let centerSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let heldFocus = select(0.3, 0.45, isMouseDown);
    let sharpBlend = clamp(focusMask * heldFocus + clickFocus * 0.5, 0.0, 0.85);
    let finalColor = mix(result, centerSample, sharpBlend);

    // Tone map
    let display = toneMapACES(finalColor);

    // Alpha stores average importance
    let importanceAlpha = clamp(accumWeight / f32(sampleCount), 0.0, 1.0);
    textureStore(writeTexture, gid.xy, vec4<f32>(display, importanceAlpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(result, importanceAlpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
