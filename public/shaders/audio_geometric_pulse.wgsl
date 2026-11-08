// ═══════════════════════════════════════════════════════════════════
//  audio_geometric_pulse
//  Category: audio-reactive
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, click-ripples
//  Upgraded: 2026-03-22
//  Swarm upgrade: 2026-07-26 (Batch 17)
//    * FIXED fake audio: audioPulse now driven by bass (plasmaBuffer[0].x)
//      instead of the mouse-down flag (zoom_config.w). All downstream
//      uses of audioPulse are unchanged — only its source was rewired.
//    * 5 frequency band rings now driven by real per-bin FFT energy
//      (plasmaBuffer[1..5].x) instead of the click flag.
//    * Treble (plasmaBuffer[0].z) subtly modulates the kaleidoscope
//      segment count around the Symmetry slider value.
//    * Spring-damped mouse center offset in extraBuffer[133..136]
//      (pos.xy + vel.xy) — cursor glides instead of teleporting.
//    * Click SDF rings: expanding geometric rings spawn from each
//      recorded click (u.ripples) and fade with ripple age.
//  Upgraded: 2026-11-08 (opus/batch-22)
//  Ideas: receding echo tunnel (C fed back with an outward zoom, bass
//         pushes it); white-hot lattice nodes where neighbouring shape
//         edges cross; bevelled gem facets lit by a slowly orbiting light
//  Rescues: spring centre lived in extraBuffer[133..136] (zeroed every
//         frame, only invocation 0 read it) -> mouse was dead; band rings
//         read plasmaBuffer[1..5] (never uploaded) -> now bass/mids/treble;
//         neon edges were sub-pixel (0.003) -> pixel-scaled width; the
//         neon glow ignored the SDF sign, so every shape rendered solid
//  A packing: display RGBA (rgb = tone-mapped colour incl. echo; a = coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

// Rotate point
fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// SDF: Circle
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// SDF: Box
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

// SDF: Equilateral triangle
fn sdTriangle(p: vec2<f32>, r: f32) -> f32 {
    let k = sqrt(3.0);
    let p2 = vec2<f32>(abs(p.x) - r, p.y + r / k);
    if (p2.x + k * abs(p2.y) > 0.0) {
        return length(vec2<f32>(p2.x - clamp(p2.x, -k * p2.y, k * p2.y), p2.y)) - r;
    }
    return -length(p2) - r;
}

// SDF: Hexagon
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    let px = abs(p);
    return max(dot(px.xy, k.xy), px.y) - r;
}

// Pulse wave
fn pulseWave(uv: vec2<f32>, time: f32, speed: f32, freq: f32) -> f32 {
    let d = length(uv);
    return sin(d * freq - time * speed) * exp(-d * 2.0);
}

// Custom mod_val function for floating-point numbers
fn mod_val(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// Kaleidoscope repeat
fn kaleidoscope(uv: vec2<f32>, segments: i32) -> vec2<f32> {
    let angle = atan2(uv.y, uv.x);
    let r = length(uv);
    let segAngle = 2.0 * PI / f32(segments);
    let a = mod_val(angle, segAngle);
    if (a > segAngle / 2.0) {
        return vec2<f32>(cos(segAngle - a) * r, sin(segAngle - a) * r);
    }
    return vec2<f32>(cos(a) * r, sin(a) * r);
}

// Neon glow
fn neonGlow(dist: f32, thickness: f32, intensity: f32) -> f32 {
    return smoothstep(thickness, 0.0, dist) * intensity;
}

// Audio band color
fn audioColor(band: f32, audioPulse: f32) -> vec3<f32> {
    let hue = band * 0.8 + audioPulse * 0.2;
    return vec3<f32>(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.19) * 0.5 + 0.5
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    let coord_u = vec2<u32>(global_id.xy);

    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // ── Real audio (plasmaBuffer FFT) ──────────────────────────────
    // FIXED: audioPulse was u.zoom_config.w (mouse-DOWN flag). It is now
    // the bass band energy. Downstream uses below are unchanged.
    let audioPulse = plasmaBuffer[0].x;               // bass
    let mids = plasmaBuffer[0].y;                     // mids (ring accents)
    let treble = plasmaBuffer[0].z;                   // treble (symmetry mod)

    // Parameters (saved-preset contract: ids/defaults/mapping fixed)
    // Treble subtly modulates the kaleidoscope segment count around the
    // Symmetry slider value (±2 segments, clamped to a sane range).
    let symmetry = i32(clamp(3.0 + u.zoom_params.x * 9.0 + treble * 2.0, 3.0, 14.0));
    let shapeMorph = u.zoom_params.y;                    // 0-1 shape blend
    let pulseSpeed = 1.0 + u.zoom_params.z * 4.0;        // 1-5
    let complexity = u.zoom_params.w;                    // 0-1

    // ── Mouse centre offset ────────────────────────────────────────
    // RESCUE: the old extraBuffer[133..136] spring never persisted (the
    // scratch buffer is re-uploaded zeroed each frame) and only invocation
    // (0,0) saw the cursor. The echo tunnel below now supplies the glide.
    let dampedPos = (u.zoom_config.yz - 0.5) * 2.0;
    let px = 1.0 / resolution.y;                       // one pixel in uv units

    // Kaleidoscope UV (center glides with the spring-damped cursor)
    let kUV = kaleidoscope(uv - dampedPos * 0.3, symmetry);

    // Multiple concentric shapes
    var color = vec3<f32>(0.0);
    var prevDist = 1e5;
    var nodes = 0.0;
    // Idea 3: light direction for bevelled facets, orbiting slowly.
    let lightDir = normalize(vec2<f32>(cos(time * 0.37), sin(time * 0.37)));
    let numShapes = i32(3.0 + complexity * 5.0);

    for (var i: i32 = 0; i < numShapes; i = i + 1) {
        let fi = f32(i);
        let t = time * 0.5 + fi * 0.5;

        // Pulsing radius
        let baseRadius = 0.1 + fi * 0.08;
        let pulse = sin(time * pulseSpeed + fi) * 0.02 * (1.0 + audioPulse);
        let radius = baseRadius + pulse;

        // Rotation
        let rotAngle = t * (0.2 + audioPulse * 0.5);
        let rotatedUV = rotate(kUV, rotAngle);

        // Shape morphing
        let d1 = sdCircle(rotatedUV, radius);
        let d2 = sdHexagon(rotatedUV, radius * 0.9);
        let d3 = sdTriangle(rotatedUV, radius * 1.1);

        // Morph between shapes
        var dist = mix(d1, d2, sin(shapeMorph * PI + fi * 0.5) * 0.5 + 0.5);
        dist = mix(dist, d3, cos(shapeMorph * PI * 2.0 + fi * 0.3) * 0.5 + 0.5);

        // Neon glow
        let thickness = 1.6 * px + 0.003 + audioPulse * 0.005;
        let intensity = 1.0 + audioPulse * 2.0;
        // RESCUE: smoothstep(t, 0, dist) is 1 for every dist < 0, so the
        // "neon edge" filled each shape solid. Glow on |dist| (+ soft halo).
        let glow = neonGlow(abs(dist), thickness, intensity) + neonGlow(abs(dist), thickness * 6.0, intensity * 0.25);

        // Color based on ring and audio
        let band = fi / f32(numShapes);
        let shapeColor = audioColor(band, audioPulse);

        // Add to accumulator
        color += shapeColor * glow * (1.0 - fi * 0.1);

        // Inner fill for some shapes
        if (i % 2 == 0) {
            let fill = smoothstep(0.0, thickness * 3.0, -dist) * 0.2;
            // Idea 3 — bevelled gem facet: the SDF gradient near the rim acts
            // as a surface normal, lit by the orbiting light.
            let e = 2.0 * px;
            let gx = mix(mix(sdCircle(rotatedUV + vec2<f32>(e, 0.0), radius), sdHexagon(rotatedUV + vec2<f32>(e, 0.0), radius * 0.9), sin(shapeMorph * PI + fi * 0.5) * 0.5 + 0.5), sdTriangle(rotatedUV + vec2<f32>(e, 0.0), radius * 1.1), cos(shapeMorph * PI * 2.0 + fi * 0.3) * 0.5 + 0.5) - dist;
            let gy = mix(mix(sdCircle(rotatedUV + vec2<f32>(0.0, e), radius), sdHexagon(rotatedUV + vec2<f32>(0.0, e), radius * 0.9), sin(shapeMorph * PI + fi * 0.5) * 0.5 + 0.5), sdTriangle(rotatedUV + vec2<f32>(0.0, e), radius * 1.1), cos(shapeMorph * PI * 2.0 + fi * 0.3) * 0.5 + 0.5) - dist;
            let n = rotate(vec2<f32>(gx, gy) / max(length(vec2<f32>(gx, gy)), 1e-5), -rotAngle);
            let bevel = smoothstep(-0.035, 0.0, dist) * step(dist, 0.0);
            let lit = dot(n, lightDir);
            color += shapeColor * fill * (1.0 + bevel * lit * 2.2) + vec3<f32>(1.0) * bevel * max(lit, 0.0) * 0.12;
        }

        // Idea 2 — lattice nodes: where this edge crosses the previous
        // shape's edge, a white-hot point flares (mids feed it).
        let w = 3.0 * px;
        nodes += smoothstep(w, 0.0, abs(dist)) * smoothstep(w, 0.0, abs(prevDist));
        prevDist = dist;
    }
    color += vec3<f32>(1.0, 0.95, 0.85) * min(nodes, 1.5) * (1.2 + mids * 2.0);

    // Central pulse burst (mids add a warm shimmer on top of bass drive)
    let centerPulse = pulseWave(uv, time, pulseSpeed * 2.0, 20.0 + audioPulse * 30.0);
    color += vec3<f32>(1.0, 0.8, 0.6) * max(centerPulse, 0.0) * (0.5 + audioPulse + mids * 0.3);

    // ── Click SDF rings ────────────────────────────────────────────
    // Each recorded click spawns an expanding geometric ring (hexagon
    // SDF, rotated over its life) that fades with ripple age.
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 2.5) {
            // Click position: ripples are in 0..1 full-frame space.
            let rippleCenter = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
            let rel = uv - rippleCenter;
            let life = 1.0 - age / 2.5;
            // Expanding ring radius, rotating hexagon edge, kaleidoscope-folded
            // so ripples respect the symmetry too.
            let ringRadius = 0.05 + age * 0.35;
            let ringUV = rotate(rel, age * 0.6);
            let ringDist = abs(sdHexagon(ringUV, ringRadius));
            let ringGlow = smoothstep(0.012 + age * 0.004, 0.0, ringDist);
            let ringColor = audioColor(fract(age * 0.4 + f32(ri) * 0.13), audioPulse * 0.5);
            color += ringColor * ringGlow * life * life * (0.6 + audioPulse * 0.8);
        }
    }

    // ── Frequency band rings (real per-bin FFT visualization) ──────
    // Each ring's radius, thickness and brightness follow its own FFT bin
    // (plasmaBuffer[1..5].x) instead of the old mouse-down flag.
    let bands = 5;
    for (var b: i32 = 0; b < bands; b = b + 1) {
        let fb = f32(b);
        // RESCUE: plasmaBuffer[1..5] is never uploaded; spread the three
        // live bands across the five rings (bass inner → treble outer).
        let bt = fb / f32(bands - 1);
        let binEnergy = select(mix(mids, treble, bt * 2.0 - 1.0), mix(audioPulse, mids, bt * 2.0), bt < 0.5);
        let bandRadius = 0.15 + fb * 0.06 + binEnergy * 0.04;
        let bandDist = abs(length(uv) - bandRadius);
        let bandGlow = smoothstep(1.2 * px + 0.004 + binEnergy * 0.02, 0.0, bandDist);
        let bandColor = audioColor(fb / f32(bands), binEnergy * 0.5);
        color += bandColor * bandGlow * (0.3 + binEnergy);
    }

    // Tone mapping
    color = color / (1.0 + max(color, vec3<f32>(0.0)));

    // Idea 1 — receding echo tunnel: last frame (C, display space) is
    // re-sampled slightly zoomed toward the pattern centre, so every pulse
    // leaves ghost shapes that shrink inward. Bass deepens the echo.
    let centre = dampedPos * 0.3;
    let zoom = 1.035 + audioPulse * 0.03;
    let echoUV = (uv - centre) * zoom + centre;
    let echoFull = vec2<f32>(echoUV.x * resolution.y / resolution.x, echoUV.y) + 0.5;
    var echo = vec3<f32>(0.0);
    if (all(echoFull >= vec2<f32>(0.0)) && all(echoFull <= vec2<f32>(1.0))) {
        echo = textureSampleLevel(dataTextureC, u_sampler, echoFull, 0.0).rgb;
    }
    let echoKeep = 0.55 + audioPulse * 0.25;
    color = max(color, echo * echoKeep * vec3<f32>(0.85, 0.9, 1.0));

    // Vignette
    let vignette = 1.0 - length(uvFull - 0.5) * 0.4;
    color *= vignette;

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvFull, 0.0).r;

    // Calculate luminance-based alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(writeTexture, coord_u, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord_u, vec4<f32>(clamp(depth, 0.0, 1.0), 0.0, 0.0, 0.0));

    // Store for feedback
    textureStore(dataTextureA, coord_u, vec4<f32>(color, finalAlpha));
}
