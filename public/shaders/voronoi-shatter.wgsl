// ═══════════════════════════════════════════════════════════════════
//  Voronoi Shatter
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: voronoi-shatter
//  Created: 2026-05-30
//  By: Copilot CLI
//  Upgraded: 2026-09-11, 2026-10-31
//  Ideas: click-impact shockwave; bass-gated shard chatter; angular inertia; internal fissure
//  A packing: raw (m_dist, influence, coasted rot/pi, alpha)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Simple Hash
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Params
    let density = (u.zoom_params.x * 50.0 + 5.0) * (1.0 + bass * 0.15);
    let shatterForce = u.zoom_params.y * (1.0 + bass * 0.25);
    let rotationStr = clamp(u.zoom_params.z + mids * 0.15, 0.0, 1.0);
    let gapSize = u.zoom_params.w * 0.2; // 0 to 0.2

    var mouse = u.zoom_config.yz;

    // Scale UV
    let uvScaled = vec2<f32>(uv.x * aspect, uv.y) * density;
    let i_st = floor(uvScaled);
    let f_st = fract(uvScaled);

    var m_dist: f32 = 10.0; // Min distance
    var m_point: vec2<f32>; // Closest point (cell center relative to grid)
    var m_id: vec2<f32>;    // ID of the cell

    // Check 3x3 neighbor grids
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var p = hash22(i_st + neighbor); // Random point in cell
            let pointPos = neighbor + p;
            let diff = pointPos - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = pointPos;
                m_id = i_st + neighbor;
            }
        }
    }

    // Global Cell Center
    let globalCellCenter = (m_id + hash22(m_id)) / density;
    let globalCellCenterUV = vec2<f32>(globalCellCenter.x / aspect, globalCellCenter.y);

    // Interaction
    let vecToMouse = globalCellCenterUV - mouse;
    // Aspect correct distance
    let distMouse = length(vec2<f32>(vecToMouse.x * aspect, vecToMouse.y));

    // Force field
    let interactionRadius = 0.4;
    let influence = smoothstep(interactionRadius, 0.0, distMouse) * shatterForce; // 1 at mouse, 0 far away

    // Displacement: Move shard AWAY from mouse
    let vecLen = max(length(vecToMouse), 0.0001);
    let displace = (vecToMouse / vecLen) * influence * (0.2 + treble * 0.05);

    // Click-impact shockwave: u.ripples[] was bound but never read, so
    // clicking never broke a single shard. Each active ripple now gives
    // shards inside its expanding, age-decaying ring an outward kick and a
    // brief rotation snap — a click visibly shatters more glass.
    var shockDisplace = vec2<f32>(0.0);
    var shockRot = 0.0;
    var shockEnergy = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.2) {
            let toCell = (globalCellCenterUV - ripple.xy) * vec2<f32>(aspect, 1.0);
            let cellDist = length(toCell);
            let front = exp(-abs(cellDist - age * 0.55) * 16.0) * exp(-age * 1.6);
            let dir = select(vec2<f32>(0.0), toCell / max(cellDist, 0.0001), cellDist > 0.0001);
            shockDisplace += dir * front * 0.14;
            shockRot += front * 1.1;
            shockEnergy += front;
        }
    }

    // Bass shard chatter: a subtle bass-gated micro-jitter/rotation on top
    // of the continuous mouse-driven rotation, giving shards a percussive
    // rattle on beat independent of pointer proximity.
    let chatterSeed = hash22(m_id + floor(time * 9.0));
    let chatterGate = step(0.8 - bass * 0.5, chatterSeed.x);
    let chatterAngle = (chatterSeed.y - 0.5) * 0.3 * chatterGate * bass;

    // Rotation target, then coast toward it from the angle stored in C.b.
    let rotTarget = influence * rotationStr * 3.14 + shockRot + chatterAngle;
    let prevState = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let prevSane = prevState.b == prevState.b && abs(prevState.b) < 4.0;
    // ── Idea 1: angular inertia ─────────────────────────────────────
    let rotAngle = select(rotTarget, mix(prevState.b * 3.14, rotTarget, 0.22), prevSane);

    // Local coords relative to cell center
    let pixelPosAspect = vec2<f32>(uv.x * aspect, uv.y);
    let centerPosAspect = vec2<f32>(globalCellCenterUV.x * aspect, globalCellCenterUV.y);
    let localPos = pixelPosAspect - centerPosAspect;

    let s = sin(-rotAngle);
    let c = cos(-rotAngle);
    let rotatedLocal = vec2<f32>(
        localPos.x * c - localPos.y * s,
        localPos.x * s + localPos.y * c
    );

    // Final Sample Pos (Aspect Corrected)
    let totalDisplace = displace + shockDisplace;
    let samplePosAspect = centerPosAspect + rotatedLocal - vec2<f32>(totalDisplace.x * aspect, totalDisplace.y);

    // Back to UV
    let sampleUV = clamp(
        vec2<f32>(samplePosAspect.x / aspect, samplePosAspect.y),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );

    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add shading for 3D effect based on m_dist (distance to center)
    let edge = smoothstep(0.18 + gapSize * 0.25, 0.55, m_dist);
    let shardLight = (1.0 - edge) * (0.2 + bass * 0.1);
    let seamGlow = smoothstep(0.3 - gapSize, 0.55, m_dist) * (0.08 + treble * 0.12);
    var finalColor = baseColor.rgb * (1.0 + shardLight) + vec3<f32>(0.05, 0.09, 0.16) * seamGlow + vec3<f32>(0.85, 0.92, 1.0) * shockEnergy * 0.3;

    // ── Idea 2: internal fissure ────────────────────────────────────
    // A stable crack across the shard. Gap size sets the width;
    // shatter force sets how dark it reads.
    let crackSeed = hash22(m_id) - 0.5;
    let crackN = vec2<f32>(-crackSeed.y, crackSeed.x);
    let crackLen = max(length(crackN), 1e-3);
    let crackD = abs(dot(localPos, crackN / crackLen)) * density;
    let fissure = smoothstep(0.045 + gapSize * 0.4, 0.0, crackD) * shatterForce;
    finalColor = mix(finalColor, finalColor * vec3<f32>(0.18, 0.2, 0.24), clamp(fissure, 0.0, 1.0));
    let finalAlpha = clamp(0.26 + (1.0 - edge) * 0.28 + influence * 0.35 + bass * 0.08 + shockEnergy * 0.2, 0.18, 0.95);
    let depth = clamp(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + influence * 0.06,
        0.0,
        1.0
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesToneMap(max(finalColor, vec3<f32>(0.0))), finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(m_dist, influence, rotAngle / 3.14, finalAlpha));
}
