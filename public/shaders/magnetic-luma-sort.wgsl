// ═══════════════════════════════════════════════════════════════════
//  Magnetic Luma Sort
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-09
//  Ideas: dipole field-line offset; luma domains; comparator sort taps; magnetic hysteresis
//  A packing: pre-grade trail RGB (linear) + trail energy in .a (hysteresis)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn get_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
    return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let pullStrength = u.zoom_params.x * 0.05; // Scaling for reasonable speed
    // Bass loosens the sort: beats lower the effective luma threshold.
    let threshold = u.zoom_params.y * (1.0 - bass * 0.3);
    let decay = u.zoom_params.z;
    let repel = step(0.5, u.zoom_params.w); // 0 or 1

    // HEAD rescue: the extraBuffer[133..138] spring was zeroed every frame, so it
    // never integrated (magnet == raw pointer). The fake state is removed.
    let time = u.config.x;
    let magnetPos = u.zoom_config.yz;

    var mousePos = magnetPos;
    let aspect = resolution.x / resolution.y;

    // Vector to mouse
    var dirToMouse = mousePos - uv;
    dirToMouse.x *= aspect;
    let dist = length(dirToMouse);

    var dir = normalize(dirToMouse);
    if (dist < 0.001) { dir = vec2(0.0, 0.0); }

    if (repel > 0.5) {
        dir = -dir;
    }

    // Read current image source
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(srcColor.rgb);

    // Read history (trail)
    // We want to sample the history from "upstream".
    // If pixels move towards mouse, we (at current pixel) look AWAY from mouse to see what's coming.
    // Movement speed depends on luma. Brighter = faster.

    // Idea 2 — luma domains: sort energy peaks at discrete luma steps.
    let domain = abs(fract(luma * 6.0) - 0.5);
    let domainGate = smoothstep(0.22, 0.08, domain);

    // Idea 4 — magnetic hysteresis (remanence): pixels whose trail was already
    // moving (energy in C.a) keep sorting below the luma gate.
    let historyDims = vec2<i32>(textureDimensions(dataTextureC));
    let remanence = clamp(textureLoad(dataTextureC, historyCoord(uv, historyDims), 0).a, 0.0, 1.0);
    let gate = threshold * (1.0 - 0.45 * remanence);

    var speed = 0.0;
    if (luma > gate) {
        speed = pullStrength * (luma - gate) / (1.0 - gate + 0.001) * mix(0.35, 1.0, domainGate);
    }

    // Per-row read-only FFT voice lives in engine slots [5..132].
    let band = min(u32(uv.y * 128.0), 127u);
    var fftVoice = 0.0;
    if (arrayLength(&extraBuffer) >= 133u) { fftVoice = clamp(extraBuffer[5u + band], 0.0, 1.0); }
    speed = speed * (1.0 + bass * 0.35 + mids * 0.2 + treble * 0.15 + fftVoice * 0.4);

    // Dampen speed by distance? Maybe infinite reach is better.
    // Let's dampen slightly so the edge of screen doesn't pull too hard if mouse is center.
    // speed *= smoothstep(0.0, 0.1, dist);

    // Idea 1 — dipole field-line offset: perpendicular B so trails loop.
    let tangent = vec2<f32>(-dir.y, dir.x);
    var pull = dir * speed + tangent * speed * 0.35 * (0.5 + mids * 0.5);

    // Click vortex pulses: each live ripple adds a decaying second attractor at
    // its click point, stirring the flow. Composed with the main pull here.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge < 0.0 || rippleAge > 3.0) { continue; }

        var dirToRipple = ripple.xy - uv;
        dirToRipple.x *= aspect;
        let rippleDist = length(dirToRipple);

        var rippleDir = vec2<f32>(0.0, 0.0);
        if (rippleDist > 0.001) { rippleDir = normalize(dirToRipple); }
        if (repel > 0.5) { rippleDir = -rippleDir; }

        // Smoothstep falloff over a ~0.25 radius, decaying with exp(-age * 2).
        let falloff = smoothstep(0.25, 0.0, rippleDist);
        let pulse = exp(-rippleAge * 2.0);
        pull = pull + rippleDir * (speed * falloff * pulse);
    }

    let offset = -pull;

    // Sample history at the upstream position
    let historyUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    // Idea 3 — comparator sort taps: compare-swap over three taps along the pull,
    // the brightest upstream run wins, so streaks read as sorted, not blurred.
    var historyColor = textureLoad(dataTextureC, historyCoord(historyUV, historyDims), 0);
    var bestL = get_luma(historyColor.rgb);
    for (var k = 1; k <= 2; k = k + 1) {
        let tapUV = clamp(uv + offset * (1.0 + 0.5 * f32(k)), vec2<f32>(0.0), vec2<f32>(1.0));
        let tap = textureLoad(dataTextureC, historyCoord(tapUV, historyDims), 0);
        let tl = get_luma(tap.rgb);
        if (tl > bestL + 0.02 && speed > 0.0) { historyColor = tap; bestL = tl; }
    }

    // Combine
    // If we are just moving the image, we should primarily see the history moving.
    // But we need to inject the new frame's content otherwise it fades out or is empty initially.
    // A common "trail" technique is max(current, history * decay).

    // Let's try a blend:
    // The "moved" content is history. The "source" is the current video frame.
    // If we only use history, the video won't update.
    // So we mix current frame into history.

    // (Dead finalColor experiment removed: the mix/max candidates above were
    // computed and then thrown away - `mixed` below was always what won.)

    // To make it look like "sorting" or "smearing", we heavily favor the displaced history
    // but we clamp it so it doesn't blow out.

    // Alternative: If the pixel is bright enough to move, it "leaves" its spot and "arrives" at the next.
    // This is hard in a gather-based shader.
    // Gather approach: I am pixel P. Who arrived here?
    // The pixel at P + offset (away from mouse) arrived here if it was moving towards mouse.

    // Let's stick to the feedback loop approach.
    // New Value = (Old Value at Upstream P) * Decay + (Current Input) * Blend

    let mixed = mix(srcColor.rgb, historyColor.rgb, decay);
    let trailEnergy = clamp(length(mixed - srcColor.rgb) * 1.5 + speed * 7.0, 0.0, 1.0);
    let alpha = clamp(srcColor.a + (1.0 - srcColor.a) * trailEnergy, 0.0, 1.0);
    // HEAD rescue: A held ACES display that C fed back → re-graded every frame.
    // A now keeps the linear trail colour; ACES is applied on display only.
    let display = vec4<f32>(acesToneMap(max(mixed, vec3<f32>(0.0)) * 1.12), alpha);

    // If luma is low, we don't move history much?
    // Actually, if luma is low (speed 0), offset is 0. So we sample history at current UV.
    // This results in a standard feedback trail.

    textureStore(writeTexture, vec2<i32>(global_id.xy), display);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mixed, max(trailEnergy, historyColor.a * decay * 0.92)));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
