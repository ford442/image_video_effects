// ═══════════════════════════════════════════════════════════════════
//  Holographic Contour
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-06-28, 2026-11-01
//  Ideas: Sobel contour ink; reference-beam fringes on the march
//  A packing: pre-ACES linear display RGBA (C mixed as that colour); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn luma3(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    // Live pointer. The old extraBuffer spring was cleared by the host every frame.
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Saved scalar roles: lattice scale, edge gate, fringe frequency, ink.
    let dotSize = (u.zoom_params.x * 20.0) + 2.0;
    let edgeThresh = max(0.01, (1.0 - u.zoom_params.y) * 0.5);
    let levels = floor(u.zoom_params.z * 10.0) + 2.0;
    let inkDensity = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    var mp = mouse * 2.0 - 1.0;
    mp.x *= aspect;

    let prev = textureLoad(dataTextureC, coord, 0);

    var ripple_sum = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rip = u.ripples[i];
        let age = time - rip.z;
        let live = rip.z > 0.0 && age > 0.0 && age < 3.0;
        let rip_p = rip.xy * 2.0 - 1.0;
        let rp = vec2<f32>(rip_p.x * aspect, rip_p.y);
        let d = length(p - rp);
        let r = age * 1.5;
        let w = 0.05 + age * 0.02;
        let v = smoothstep(w, 0.0, abs(d - r)) * smoothstep(3.0, 2.0, age);
        ripple_sum = ripple_sum + select(0.0, v, live);
    }
    ripple_sum = min(ripple_sum, 1.5);

    var ro = vec3<f32>(0.0, 0.0, -3.5);
    let rd = normalize(vec3<f32>(p, 1.5));
    ro.x += mp.x * held * 0.5;
    ro.y -= mp.y * held * 0.5;

    var t = 0.0;
    var hit_pos = ro;

    for (var i = 0; i < 60; i = i + 1) {
        let pos0 = ro + rd * t;
        let twistedXZ = rot(time * 0.1 + ripple_sum * 0.5) * pos0.xz;
        let pos1 = vec3<f32>(twistedXZ.x, pos0.y, twistedXZ.y);
        let twistedXY = rot(sin(time * 0.05 + pos1.z) * 0.5) * pos1.xy;
        let pos = vec3<f32>(twistedXY.x, twistedXY.y, pos1.z);

        let q = fract(pos + vec3<f32>(0.0, 0.0, time * 0.2)) - 0.5;
        let d_grid = length(q) - (0.15 + bass * 0.05);
        let d_shape = length(pos) - (dotSize * 0.1) - mid * 0.1;
        let dist = max(d_grid, d_shape);

        let done = dist < 0.001 || t > 10.0;
        hit_pos = select(hit_pos, pos, done);
        t = select(t + dist, t, done);
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    let hit = t < 10.0;
    let glow = saturate(1.0 - t * 0.1);
    let n_phase = time + hit_pos.x * levels + hit_pos.y * levels + hit_pos.z * levels;
    var spectral = vec3<f32>(0.5) + 0.5 * cos(n_phase + vec3<f32>(0.0, 2.0, 4.0));

    // ── Idea 2: reference-beam fringes ────────────────────────────────
    // The march distance is the object beam. A tilted plane is the reference.
    // levels stays the carrier frequency.
    let refAng = time * 0.15;
    let refBeam = dot(hit_pos.xy, vec2<f32>(cos(refAng), sin(refAng))) * levels;
    let plateFringe = 0.5 + 0.5 * cos(t * levels - refBeam);
    spectral = spectral * (0.35 + 0.65 * plateFringe);

    let ndoth = saturate(dot(-rd, normalize(hit_pos + vec3<f32>(0.0001))));
    let fresnel = pow(1.0 - ndoth, 3.0);
    let hitCol = spectral * glow * (0.5 + fresnel * 2.0) + treble * vec3<f32>(0.2, 0.5, 1.0) * fresnel;
    let hitAlpha = saturate(glow * inkDensity * (0.5 + ripple_sum) * (0.45 + 0.55 * plateFringe));
    col = select(col, hitCol, hit);
    alpha = select(alpha, hitAlpha, hit);

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).xyz;
    let luma = luma3(base);
    let px = vec2<f32>(1.0) / resolution;
    let lR = luma3(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).xyz);
    let lL = luma3(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).xyz);
    let lD = luma3(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).xyz);
    let lU = luma3(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).xyz);
    let edgeMag = length(vec2<f32>(lR - lL, lD - lU));
    let lumaGate = smoothstep(edgeThresh, edgeThresh + 0.1, luma);

    // ── Idea 1: Sobel contour ink ─────────────────────────────────────
    // The luma gate stays. A ridge along the photo gradient is drawn on top,
    // still opened and closed by edgeThresh.
    let sobel = smoothstep(edgeThresh, edgeThresh + 0.12, edgeMag);
    let contourFringe = 0.5 + 0.5 * cos((uv.x * aspect + uv.y) * levels * 6.0 - time * 0.8);

    let contour_col = base * 2.0 * vec3<f32>(0.5, 1.0, 2.0);
    col = mix(col, contour_col, lumaGate * 0.6);
    col = col + vec3<f32>(0.45, 0.85, 1.15) * sobel * inkDensity * (0.4 + 0.6 * contourFringe);
    alpha = saturate(alpha + lumaGate * inkDensity + sobel * 0.35);

    col = mix(col, prev.xyz, 0.3 * (1.0 - saturate(ripple_sum)));
    alpha = mix(alpha, prev.w, 0.3);
    col = max(col, vec3<f32>(0.0));
    alpha = saturate(alpha);

    let depthOut = select(1.0, clamp(t / 10.0, 0.0, 1.0), hit);
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeTexture, coord, vec4<f32>(aces_tonemap(col), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
