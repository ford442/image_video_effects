// ═══════════════════════════════════════════════════════════════════
//  Reaction-Diffusion
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-12, 2026-11-15
//  Ideas: anisotropic Laplacian along flowDir; mitosis pinch on −∇²V; autocatalytic front glow (native); photo-driven kill map (native)
//  Rescue: U re-supply floor removed (HEAD flooded to a frozen V=1 field after ~15 s); kill range shifted +0.005 (default sat in the flat active-state regime)
//  A packing: raw (U, V, packet, accumulation)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyLoad(pixel: vec2<i32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
    let diffusionRate = 0.025 + u.zoom_params.x * 0.075;
    let feedRate = 0.018 + u.zoom_params.y * 0.052;
    // ── Rescue 2: kill range ──────────────────────────────────────────
    // HEAD's 0.035 + z*0.045 put the saved default (feed 0.044, kill 0.0575) on the flat side of the
    // Gray-Scott saddle-node line f = 4(f+k)^2: with the substrate floor gone it relaxes to a uniform
    // V ~ 0.3 field (numpy port: std 0.03 after 15 s). +0.005 puts the default in the excitable band
    // and keeps the slider's full 0.045 span and its role.
    let killRate = 0.040 + u.zoom_params.z * 0.045;
    let accumulationRate = u.zoom_params.w;

    // Rotate a one-pixel state conveyor to move the chemistry coherently.
    let flowDir = normalize(vec2<f32>(cos(time * 0.71), sin(time * 0.93)));
    let advectPixels = vec2<i32>(round(flowDir * (1.0 + u.zoom_params.x * 2.0)));
    let baseCoord = coord - advectPixels;
    let prev = historyLoad(baseCoord);
    let left = historyLoad(baseCoord + vec2<i32>(-1, 0));
    let right = historyLoad(baseCoord + vec2<i32>(1, 0));
    let up = historyLoad(baseCoord + vec2<i32>(0, -1));
    let down = historyLoad(baseCoord + vec2<i32>(0, 1));
    let isoLap = (left + right + up + down - 4.0 * prev) * 0.25;

    // Idea 1 — anisotropic Laplacian along flowDir (conveyor smears, not just translates)
    let flowStep = vec2<i32>(i32(round(flowDir.x)), i32(round(flowDir.y)));
    let along = historyLoad(baseCoord + flowStep);
    let against = historyLoad(baseCoord - flowStep);
    let anisoLap = (along + against - 2.0 * prev) * 0.5;
    let laplacian = mix(isoLap, anisoLap, 0.55);

    let input = textureLoad(readTexture, coord, 0);
    let seed = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    // ── Rescue 1: substrate floor ─────────────────────────────────────
    // HEAD: a = max(prev.r, 0.75 + seed*0.25) re-supplied U to >= 0.75 on EVERY frame. The reaction could
    // never exhaust it, so V = 1 was an absorbing state: the field flooded to a frozen black frame after
    // ~15 s (SwiftShader 192 px: uniform grey at 300 frames, black at 900; numpy port agrees). U now keeps
    // what the chemistry left (the f*(1-a) feed term is the only supply) and is seeded from the photo only
    // on a cold start, when C is still empty.
    let fresh = (prev.r + prev.g) < 0.0001;
    var a = clamp(select(prev.r, 0.75 + seed * 0.25, fresh), 0.0, 1.0);
    var b = clamp(prev.g + seed * 0.002, 0.0, 1.0);

    // Narrow analytic packets alternately feed and inhibit the reaction.
    let packetPhase = dot(uv, normalize(vec2<f32>(0.82, -0.57))) * 24.0 - time * (6.0 + u.zoom_params.y * 9.0);
    let packet = pow(0.5 + 0.5 * cos(packetPhase), 18.0);
    var front = 0.0;
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.19 + audio.y * 0.06));
            front += (1.0 - smoothstep(0.0, 0.022, ring)) * (1.0 - age / 3.0);
        }
    }
    let mouseSeed = smoothstep(0.09, 0.0, length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0))) * u.zoom_config.w;
    b = clamp(b + packet * (0.008 + audio.z * 0.012) + front * 0.12 + mouseSeed * 0.16, 0.0, 1.0);

    // Idea 2 — mitosis pinch: extra V where −∇²V is large (spots split)
    let mitosis = max(-laplacian.g, 0.0) * b * (0.08 + audio.x * 0.04);
    b = clamp(b + mitosis, 0.0, 1.0);

    let reaction = a * b * b;
    let newA = clamp(a + diffusionRate * laplacian.r - reaction + feedRate * (1.0 - a), 0.0, 1.0);
    // ── Idea 4 (batch-38 card idea 2): photo-driven kill map (native) ──
    // One global kill rate gives one pattern type. Gray-Scott's morphology (spots / worms / sheets) is set
    // by (f, k), so let k follow the photo's luma (already computed as `seed`): +-0.005 around the Scale
    // slider's value, which stays the global kill. Bright regions extinguish sooner, dark regions keep
    // their fronts alive, so the pattern's character follows the picture's tonal regions.
    let killLocal = killRate + (clamp(seed, 0.0, 1.0) - 0.5) * 0.010;
    let newB = clamp(b + diffusionRate * 0.5 * laplacian.g + reaction - (killLocal + feedRate) * b, 0.0, 1.0);
    let pattern = clamp(newA - newB, -1.0, 1.0);
    // ── Idea 3 (batch-38 card idea 1, replaces the 9-point stencil): autocatalytic front glow (native) ──
    // `reaction` = U*V^2 is the autocatalytic rate. It was computed and used only for the update, yet it
    // peaks exactly on the moving fronts, where the chemistry is actually happening. Show it as emission
    // (reaction-rate map, hot orange -> white-ish core) so every front reads as a burning edge instead of
    // a flat band boundary. A is untouched; this only reaches the display.
    let rate = 1.0 - exp(-reaction * 14.0);
    let frontGlow = mix(vec3<f32>(1.0, 0.42, 0.10), vec3<f32>(1.0, 0.85, 0.55), rate * rate) * rate;
    let color = vec3<f32>(
        smoothstep(-0.15, 0.55, pattern),
        smoothstep(0.05, 0.68, pattern + packet * 0.2),
        smoothstep(0.22, 0.82, pattern + front * 0.25 + mitosis * 2.0)
    ) + frontGlow * 0.55;
    let newAlpha = 1.0 - exp(-abs(pattern) * 2.0);
    let totalAlpha = clamp(prev.a * (0.90 + accumulationRate * 0.08) + newAlpha * accumulationRate * 0.2, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(newA, newB, packet, totalAlpha));
    let mapped = aces(max(color * (0.95 + audio.y * 0.12), vec3<f32>(0.0)));
    let alpha = clamp(input.a * 0.15 + totalAlpha * 0.55 + newAlpha * 0.45 + front * 0.2, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
