// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Radar
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha,
//            radar-sweep, edge-detection, depth-aware, aces-tone-map,
//            ign-dither, hue-preserve-clamp, blackbody-temperature
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: analytic one-sided sweep wake behind the beam; three range rings where crossing edges pop white; hold to interrogate (beam parks on the cursor bearing, 2x wide)
//  A packing: display RGBA; (0,0) = (accumulated beam angle, 0, 0, sentinel -7)
// ═══════════════════════════════════════════════════════════════════
//  Black field; luma+depth edges are lit only under a rotating gaussian beam
//  centred between the screen centre and the mouse. The beam angle is
//  accumulated in a state texel (speed * (1 + bass) * dt) instead of
//  fract(time * bassSpeed), so bass no longer makes the beam jump.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SENTINEL: f32 = -7.0;
const DT: f32 = 1.0 / 60.0;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 { var s = 0.0; var a = 0.5; var f = 1.0; for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; } return s; }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829181 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn edgeMetric(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dx = vec2<f32>(ps.x, 0.0); let dy = vec2<f32>(0.0, ps.y);
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + dx, 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - dx, 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + dy, 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - dy, 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let lR = luma(textureSampleLevel(readTexture, u_sampler, uv + dx, 0.0).rgb);
    let lL = luma(textureSampleLevel(readTexture, u_sampler, uv - dx, 0.0).rgb);
    let lU = luma(textureSampleLevel(readTexture, u_sampler, uv + dy, 0.0).rgb);
    let lD = luma(textureSampleLevel(readTexture, u_sampler, uv - dy, 0.0).rgb);
    let lumaEdge = length(vec2<f32>(lR - lL, lU - lD));
    return smoothstep(0.02, 0.25, lumaEdge + depthEdge * 2.0);
}
fn neonSpectrum(t: f32) -> vec3<f32> { return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189)); }

// Preserve hue when channels exceed the display range by normalising the
// brightest channel back to 1.0 instead of clipping individual channels.
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
    let mx = max(max(c.r, c.g), c.b);
    return c / max(mx, 1.0);
}

// Curved-screen rim: 0 at the viewport centre, rising toward the corners.
// FIX: HEAD's version was brightest at the centre; it now only lives at the rim.
fn fresnelRim(uv: vec2<f32>, power: f32) -> f32 {
    let d = distance(uv, vec2<f32>(0.5));
    return pow(clamp(d * 2.0, 0.0, 1.0), power);
}

// Exponential volumetric fog that lets the radar glow soften as depth grows.
fn volumetricFog(depth: f32, density: f32) -> f32 { return exp(-depth * density); }

// Approximate blackbody emission for hot radar contact points.
fn blackbody(t: f32) -> vec3<f32> {
    let k = mix(1000.0, 10000.0, clamp(t, 0.0, 1.0));
    let k2 = k * k;
    let k3 = k2 * k;
    let r = 1.0;
    let g = clamp(-4.959e-12 * k3 + 6.351e-8 * k2 - 0.0002776 * k + 0.4756, 0.0, 1.0);
    let b = clamp(4.22e-12 * k3 - 2.55e-7 * k2 + 0.0005156 * k - 0.3266, 0.0, 1.0);
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(pixel) / res;
    let ps = 1.0 / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    // FIX: sensitivity up = more edges (default p1 = 0.2 -> 0.10, HEAD ~0.076).
    let threshold = mix(0.12, 0.02, p1);
    let radarSpeed = p2 * 2.0;                 // revolutions per second
    let sweepWidthBase = mix(0.05, 0.5, p3);
    let intensity = p4 * 3.0;

    let aspect = res.x / res.y;
    let beamOrigin = mix(vec2<f32>(0.5), mouse, 0.6);
    let centered = uv - beamOrigin;
    let angle = atan2(centered.y, centered.x);

    // ── Beam angle state texel (0,0): .x = accumulated angle, .w = sentinel ──
    let stRaw = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st = select(vec4<f32>(0.0), stRaw, stRaw == stRaw);
    let stateValid = st.w == SENTINEL;
    let seedAngle = fract(time * radarSpeed) * TAU - PI;
    var beamAngle = select(seedAngle, st.x, stateValid);
    // Idea 3 (hold to interrogate): while the pointer is held the beam parks on
    // the cursor bearing from the beam origin and widens 2x; the stored angle
    // follows it so the sweep resumes from the cursor on release.
    let toCursor = mouse - beamOrigin;
    let cursorBearing = atan2(toCursor.y, toCursor.x);
    if (held && dot(toCursor, toCursor) > 1e-6) {
        beamAngle = cursorBearing;
    } else {
        beamAngle = beamAngle + radarSpeed * TAU * (1.0 + bass) * DT;
    }
    beamAngle = beamAngle % TAU;
    let sweepAngle = beamAngle;
    let sweepWidth = sweepWidthBase * select(1.0, 2.0, held);

    let diff = abs(fract((angle - sweepAngle) / TAU + 0.5) - 0.5) * TAU;
    let sweep = exp(-diff * diff / (sweepWidth * sweepWidth));

    // Idea 1 (analytic sweep wake): a one-sided exponential decay behind the
    // beam (the beam turns toward +angle, so "behind" is sweepAngle - angle,
    // wrapped to [0, TAU)). Stateless: no history texel, no phosphor. Held
    // beams have no wake because they are not moving.
    let behindAngle = fract((sweepAngle - angle) / TAU) * TAU;
    let wakeDecay = 1.5;
    let wake = exp(-behindAngle * wakeDecay) * select(0.55, 0.0, held) * (1.0 - sweep);
    let lit = clamp(sweep + wake, 0.0, 1.0);

    let edgeRaw = edgeMetric(uv, ps);
    let edge = smoothstep(threshold, threshold + 0.05, edgeRaw);
    let hue = time * 0.3 + bass * 0.5 + fbm(uv * 3.0 + time * 0.1, 3) * 0.4;
    let neon = neonSpectrum(hue) * intensity;
    // The wake is a slightly cooler hue than the beam so the tail reads as decay.
    let emission = neon * edge * sweep + neonSpectrum(hue + 0.6) * intensity * edge * wake;

    // Idea 2 (range-ring contacts): three concentric range rings around the
    // beam origin (aspect-corrected). Rings are faintly drawn only where the
    // beam/wake lights them; an edge crossing a ring pops bright and white.
    let rangeDist = length(centered * vec2<f32>(aspect, 1.0));
    var ringMask = 0.0;
    for (var k = 1; k <= 3; k = k + 1) {
        let ringR = f32(k) * 0.16;
        let dr = (rangeDist - ringR) / 0.006;
        ringMask = ringMask + exp(-dr * dr);
    }
    ringMask = clamp(ringMask, 0.0, 1.0);
    let ringLine = vec3<f32>(0.35, 1.0, 0.75) * ringMask * lit * intensity * 0.12;
    let contact = edge * ringMask * lit;
    let contactGlow = vec3<f32>(1.0) * contact * intensity * 0.9;

    // Rim: curved-screen brightening of lit edges near the viewport rim only.
    let rim = fresnelRim(uv, 2.5) * intensity * 0.35;
    let rimColor = neonSpectrum(hue + 0.5) * rim * edge * lit * (0.7 + bass * 0.3);
    // FIX: hotspot temperature comes from the edge strength, not the width slider.
    let hotSpot = blackbody(mix(0.3, 0.9, edgeRaw)) * smoothstep(0.82, 1.0, sweep) * edge * 0.25;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = volumetricFog(depth, 0.6);   // FIX: constant density

    var color = huePreserveClamp(emission + rimColor + hotSpot + ringLine + contactGlow) * (1.0 + bass) * fog;
    color = acesToneMap(clamp(color, vec3<f32>(0.0), vec3<f32>(16.0)));
    color += (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;

    let energy = edge * lit * intensity + contact + rim * edge * lit;
    let alpha = clamp(energy * (0.6 + depth * 0.4), 0.0, 0.98);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    if (pixel.x == 0 && pixel.y == 0) {
        textureStore(dataTextureA, pixel, vec4<f32>(beamAngle, 0.0, 0.0, SENTINEL));
    } else {
        textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    }
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
