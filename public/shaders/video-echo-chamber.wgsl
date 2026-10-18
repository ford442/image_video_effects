// ═══════════════════════════════════════════════════════════════════
//  Video Echo Chamber
//  Category: image
//  Features: mouse-driven, click-reactive, audio-reactive, temporal-persistence, bounded-history, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: motion-keyed echo (|current − history| drives the echo weight, static content stays clean); depth-weighted persistence (near echoes last longer)
//  A packing: rgb = pre-ACES echo composite clamped 0..1 (C.rgb read back as colour history, nearest textureLoad); a = motion-echo memory 0..1 (C.a read back and decayed). Display alpha = source coverage + echo coverage, on writeTexture only
// ═══════════════════════════════════════════════════════════════════
// Video echo chamber with orbiting history conveyors and click-launched echoes.

#include "_prelude.wgsl"

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

fn rotate2(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let globalDecay = mix(0.82, 0.995, u.zoom_params.x);
    let mouseRadius = mix(0.03, 0.35, u.zoom_params.y);
    let echoStrength = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    let current = textureLoad(readTexture, coord, 0);
    // Exact, un-warped history at this pixel (previous frame's A).
    let prev = textureLoad(dataTextureC, coord, 0);
    let aspect = resolution.x / resolution.y;
    let aspectScale = vec2<f32>(aspect, 1.0);

    // HEAD fix: rotate/zoom in an aspect-square space so the mouse zone is a circle and the
    // spin does not shear on wide frames; map back to UV afterwards.
    let center = u.zoom_config.yz;
    let local = (uv - center) * aspectScale;
    let mouseMask = smoothstep(mouseRadius, mouseRadius * 0.15, length(local));
    let orbit = (0.004 + echoStrength * 0.018) * (0.35 + mouseMask * (0.65 + u.zoom_config.w));
    let angle = time * (1.8 + audio.y * 1.5);
    let orbitUV = center + (rotate2(local, orbit * sin(angle)) / (1.0 - orbit * cos(angle))) / aspectScale;

    // A second directional conveyor creates horizontal chromatic afterimages.
    let runner = pow(0.5 + 0.5 * sin(uv.y * 42.0 - time * (7.0 + audio.x * 4.0)), 14.0);
    let streak = vec2<f32>((0.003 + runner * 0.018) * (1.0 + echoStrength), 0.0);
    let echoR = historyLoadUV(orbitUV - streak * (1.0 + colorShift)).r;
    let echoG = historyLoadUV(orbitUV).g;
    let echoB = historyLoadUV(orbitUV + streak * (1.0 + colorShift)).b;
    var echoColor = vec3<f32>(echoR, echoG, echoB);

    var clickEcho = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.22 + audio.z * 0.08));
            clickEcho += (1.0 - smoothstep(0.0, 0.028, ring)) * (1.0 - age / 2.8);
        }
    }
    echoColor += clickEcho * vec3<f32>(0.30, 0.12, 0.42);

    // Idea 2 — depth-weighted persistence: near content (depth → 1) decays slower, so a close
    // subject's echoes outlast the background's. Far/absent depth (0) is exactly HEAD's decay.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let nearness = smoothstep(0.35, 0.9, depth);
    let depthDecay = mix(globalDecay, 0.995, nearness * 0.5);
    let motionPersist = depthDecay * mix(0.85, 0.99, nearness);

    // Idea 1 — motion-keyed echo: |luma(current) − luma(history)| at the un-warped pixel says
    // where content moved. The key is held in A.a as a decaying memory so a moving subject
    // leaves a trail for several frames instead of one. Sensor-noise-sized differences are
    // ignored. The floor (0.15 in the open frame, 0.85 under the pointer) keeps the tunnel
    // visible near the pointer on a still image — the pointer is the user asking for echoes —
    // while static background away from it stays almost clean. The key is ≤ 1, so the echo
    // weight is never stronger than HEAD's.
    let lumaW = vec3<f32>(0.299, 0.587, 0.114);
    let frameDiff = abs(dot(current.rgb, lumaW) - dot(prev.rgb, lumaW));
    let motionNow = smoothstep(0.05, 0.18, frameDiff);
    let motionMemory = clamp(max(motionNow, prev.a * motionPersist), 0.0, 1.0);
    let staticFloor = mix(0.15, 0.85, mouseMask);
    let motionKey = staticFloor + (1.0 - staticFloor) * motionMemory;

    let historyWeight = echoStrength * depthDecay * (0.45 + runner * 0.25) * motionKey;
    let echoWeight = clamp(historyWeight + clickEcho * 0.18, 0.0, 0.92);
    let blended = clamp(mix(current.rgb, echoColor, echoWeight), vec3<f32>(0.0), vec3<f32>(1.0));

    // HEAD fix: semantic alpha — source coverage plus the coverage the echo layer lays over it;
    // no frame-to-frame alpha accumulation, so it no longer saturates.
    let alpha = clamp(mix(current.a, 1.0, echoWeight), 0.0, 1.0);

    // A stays pre-ACES 0..1 so the loop is never tone-mapped twice; ACES on display only.
    textureStore(dataTextureA, coord, vec4<f32>(blended, motionMemory));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(blended), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
