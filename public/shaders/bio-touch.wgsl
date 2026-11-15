// ═══════════════════════════════════════════════════════════════════
//  Bio-Luminescent Touch
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: original bio-touch
//  Created: 2026-05-10
//  Upgraded: 2026-05-23, 2026-11-15
//  Ideas: nucleus and cell wall; afterglow held in C.a
//  A packing: ACES display RGB; raw glow in A.a
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=GlowRadius, y=CellDensity, z=ColorShift, w=PulseSpeed

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash22 (from _hash_library.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(k) * 43758.5453);
}

fn voronoi(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);

    var minDist = 1.0;

    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cellId = i + neighbor;
            let point = neighbor + hash22(cellId) - f;
            var dist = length(point);
            minDist = min(minDist, dist);
        }
    }

    return minDist;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001, 0.001));
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse Interaction
    var mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDown = u.zoom_config.w; // 1.0 if down

    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / max(resolution.y, 0.001);
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    var dist = length(distVec);

    // Params
    let glowRadius = clamp(u.zoom_params.x * 0.5, 0.0, 0.5); // 0.0 to 0.5
    let cellDensity = (10.0 + u.zoom_params.y * 50.0) * (1.0 + bass * 0.25);
    let colorShift = clamp(u.zoom_params.z, 0.0, 1.0);
    let pulseSpeed = u.zoom_params.w * 5.0 * (1.0 + bass * 0.5);

    // Bio-Luminescence Logic
    // Only active near mouse
    let influence = smoothstep(glowRadius + 0.1, glowRadius, dist);
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.7) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.34) * 62.0);
    }

    // Animate voronoi
    let heldCurl = vec2<f32>(-distVec.y, distVec.x) / max(dist, 0.001) * influence * mouseDown;
    let offset = vec2<f32>(sin(time * 0.5), cos(time * 0.4)) * 0.1 + heldCurl * 0.08;
    let v = voronoi((uv + offset) * max(cellDensity, 0.001));

    // ── Idea 1: nucleus and cell wall from the same Voronoi distance
    let body = 1.0 - smoothstep(0.0, 0.5, v);
    let nucleus = exp(-v * v * 60.0);
    let cellWall = exp(-abs(v - 0.22) * 16.0);
    let glow = body * 0.7 + nucleus * 0.85 + cellWall * 0.5;

    // Pulse
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed - dist * 10.0);

    // Combine
    let membrane = sin(v * cellDensity * 0.8 - time * (2.0 + mids * 5.0));
    let finalGlow = glow * influence * pulse * (1.0 + mouseDown * 2.0) + clickFront * 0.5;

    // ── Idea 2: afterglow. C.a is the previous glow, not a photo smear.
    let prevGlow = textureLoad(dataTextureC, coord, 0).a;
    let decay = mix(0.90, 0.78, clamp(u.zoom_params.w, 0.0, 1.0));
    let after = max(finalGlow, prevGlow * decay);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let color = src.rgb;

    // Color Tinting (branchless)
    var tint = vec3<f32>(0.2, 0.8, 0.6); // Default teal
    tint = select(vec3<f32>(0.8, 0.2, 0.6), tint, colorShift <= 0.3);
    tint = select(vec3<f32>(0.2, 0.4, 0.9), tint, colorShift <= 0.6);

    // Composite
    // Add glow to original color
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + membrane * 2.0 + colorShift * 6.283 + treble * 2.0);
    let outColor = color + mix(tint, spectral, 0.35 + treble * 0.35) * after + spectral * abs(membrane) * influence * 0.08;

    let storedGlow = clamp(after, 0.0, 1.0);
    let alpha = clamp(storedGlow * 0.75 + influence * 0.15 + src.a * 0.1, 0.0, 1.0);
    let mapped = aces(max(outColor, vec3<f32>(0.0)));
    let display = vec4<f32>(mapped, alpha);

    textureStore(writeTexture, coord, display);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(mapped, storedGlow));
}
