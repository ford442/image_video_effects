// ═══════════════════════════════════════════════════════════════════
//  Double Exposure HDR
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-15
//  Ideas: overlap-only bloom knee; pivot-locked second plate; latent shadow-silhouette emulsion keying; halation & core bleach (§12.2A)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rotate2d(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
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
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    var uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoomParam = u.zoom_params.x;
    let zoom = 0.5 + zoomParam * 2.5;
    let rotParam = u.zoom_params.y;
    let angle = (rotParam - 0.5) * 1.57;
    let opacity = u.zoom_params.z;
    let saturation = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let aspect = res.x / max(res.y, 1.0);

    let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Idea 2 — pivot-locked second plate (mouse is the sandwich pin).
    var p = uv - mouse;
    p.x *= aspect;
    p = rotate2d(p, angle);
    p = p / zoom;
    p.x /= aspect;
    let uv2 = clamp(p + mouse, vec2<f32>(0.0), vec2<f32>(1.0));
    let c2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

    // ── Idea 3: latent shadow-silhouette emulsion keying ─────────────────
    // Unexposed silver halide in Plate 1's shadows develops Plate 2 richly,
    // while Plate 1 highlights near D-max yield smoothly instead of washing out.
    let luma1 = dot(c1.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let shadowReserve = 1.0 - smoothstep(0.16, 0.82, luma1);
    let plate2Gain = opacity * mix(0.62, 1.28, shadowReserve);
    let c2Keyed = clamp(c2.rgb * plate2Gain, vec3<f32>(0.0), vec3<f32>(1.0));

    var blended = 1.0 - (1.0 - c1.rgb) * (1.0 - c2Keyed);
    let gray = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    blended = mix(vec3<f32>(gray), blended, 0.5 + saturation * 0.5);

    let lum1 = max(c1.r, max(c1.g, c1.b));
    let lum2 = max(c2.r, max(c2.g, c2.b));
    // Idea 1 — overlap-only bloom knee (both plates bright).
    let overlapKnee = smoothstep(0.55, 0.92, min(lum1, lum2)) * opacity;

    let bloomRadius = 0.034 * (1.0 + bass * 0.2);
    let bloomSamples = 12;
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;
    var halationAccum = 0.0;
    var outerWeight = 0.0;
    for (var i = 0; i < bloomSamples; i = i + 1) {
        let a = f32(i) * 6.283185307 / f32(bloomSamples);
        let ringIdx = i % 4;
        let radius = bloomRadius * (1.0 + f32(ringIdx) * 0.5);
        let offset = vec2<f32>(cos(a), sin(a)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let n2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 + offset * 0.35, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let pair = min(max(neighbor.r, max(neighbor.g, neighbor.b)), max(n2.r, max(n2.g, n2.b)));
        let neighborExposure = max(0.0, pair - 0.65);
        let weight = exp(-f32(ringIdx) * 0.5);
        bloom += (neighbor + n2) * 0.5 * neighborExposure * weight;
        totalWeight += neighborExposure * weight;
        let isOuter = f32(ringIdx >= 2);
        halationAccum += max(pair - 0.72, 0.0) * isOuter * weight;
        outerWeight += isOuter * weight;
    }
    bloom /= max(totalWeight, 0.001);
    bloom *= 1.5 * overlapKnee * (1.0 + mids * 0.25);

    // ── Idea 4: emulsion base halation & shoulder core bleach (§12.2A) ───
    let halation = (halationAccum / max(outerWeight, 0.001)) * (0.45 + opacity * 0.65) * (1.0 + bass * 0.2);
    var hdrColor = blended + bloom + halation * vec3<f32>(1.0, 0.36, 0.12);
    let hdrLuma = dot(hdrColor, vec3<f32>(0.299, 0.587, 0.114));
    let coreBleach = smoothstep(0.85, 1.85, hdrLuma) * clamp(overlapKnee + halation * 0.5, 0.0, 1.0);
    hdrColor = mix(hdrColor, vec3<f32>(hdrLuma) * vec3<f32>(1.03, 0.99, 0.94), coreBleach * 0.42);

    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mouse);
    let mouseGlow = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 2.0;
    hdrColor += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        let live = f32(age < 0.5 && rDist < 0.1);
        let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0) * live;
        hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
    }

    let ldrColor = toneMapACES(max(hdrColor, vec3<f32>(0.0)) * 1.25);
    let energy = clamp(overlapKnee + halation * 0.3 + treble * 0.08, 0.0, 1.0);
    let alpha = clamp(c1.a * 0.3 + energy * 0.55 + opacity * 0.2, 0.0, 1.0);
    let outColor = vec4<f32>(ldrColor, alpha);

    textureStore(dataTextureA, coord, outColor);
    textureStore(writeTexture, coord, outColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
