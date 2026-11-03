// ═══════════════════════════════════════════════════════════════════
//  Hyper-Space Jump Blackbody
//  Category: advanced-hybrid
//  Features: radial-streaks, blackbody-radiation, relativistic, HDR, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: hyper-space-jump, spec-blackbody-thermal
//  Created: 2026-04-18
//  Upgraded: 2026-09-15, 2026-11-01
//  Ideas: Lorentz length-contracted streaks; relativistic beaming on dir_norm chroma; Cauchy split on the streak (§12.2F); cooling afterglow from C
//  A packing: pre-ACES RGB + vignette alpha
// ═══════════════════════════════════════════════════════════════════
//  High-velocity radial streaking where each streak's luminance maps
//  to blackbody temperature. Bright streaks burn blue-white, dim
//  streaks glow amber-red. Creates a thermally-colored warp tunnel.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(max(t, 1e-3)) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(max(t - 1.0, 1e-3)) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

fn cauchyScale(spreadB: f32) -> vec3<f32> {
    let lam = vec3<f32>(0.650, 0.550, 0.450);
    let lam2 = lam * lam;
    let n = 1.0 + spreadB / max(lam2, vec3<f32>(1e-4));
    return n / max(n.y, 1e-4);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.4);
    let samples = 24;
    let center = u.zoom_config.yz;

    let aspect = res.x / max(res.y, 0.001);
    let center_aspect = vec2<f32>(center.x * aspect, center.y);
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    var dir = uv_aspect - center_aspect;
    let dist = length(dir);
    let dir_norm = dir / max(dist, 0.001);
    let dir_uv = uv - center;

    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);

    var color_acc = vec3<f32>(0.0);
    var weight_acc = 0.0;

    let decay = 0.95;
    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.y);
    let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.z);
    let chromaticSpread = u.zoom_params.w;

    // Idea 1 — Lorentz-like stretch: tunnel elongates at the rim
    let beta = clamp(dist * 0.85, 0.0, 0.95);
    let gammaStretch = 1.0 / max(sqrt(1.0 - beta * beta), 0.2);
    let cauchy = cauchyScale(mix(0.02, 0.22, chromaticSpread));

    for (var i = 0; i < samples; i = i + 1) {
        let f = f32(i);
        let inward = f / f32(samples);
        let offset = dir_uv * inward * strength * 10.0 * gammaStretch;

        let sample_uv = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));

        let jitter_offset = offset * (noise - 0.5) * 0.1 * (1.0 + treble * 0.25);

        // ── Idea: Cauchy split (§12.2F). Chromatic Spread still sets the magnitude.
        let chromBase = vec2<f32>(dir_norm.x / aspect, dir_norm.y) * chromaticSpread * 0.012 * f;
        let r_uv = clamp(sample_uv + jitter_offset + chromBase * cauchy.x, vec2<f32>(0.0), vec2<f32>(1.0));
        let b_uv = clamp(sample_uv + jitter_offset - chromBase * cauchy.z, vec2<f32>(0.0), vec2<f32>(1.0));
        let g_uv = clamp(sample_uv + jitter_offset, vec2<f32>(0.0), vec2<f32>(1.0));

        let s_color = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0);
        let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
        let sample_color = vec3<f32>(r, s_color.g, b);

        let luma = dot(sample_color, vec3<f32>(0.299, 0.587, 0.114));
        // Idea 2 — relativistic beaming: inward/approaching hotter, wake cooler
        let beam = mix(0.72, 1.48, inward) * (1.0 + mids * 0.25);
        let weight = pow(decay, f) * (0.1 + smoothstep(0.3, 1.0, luma) * 2.0) * beam;

        let sampleTemp = mix(tempRangeLow, tempRangeHigh, luma) * beam;
        let thermalColor = blackbodyColor(sampleTemp);

        color_acc += thermalColor * weight;
        weight_acc += weight;
    }

    var final_color = vec3<f32>(0.0);
    if (weight_acc > 0.001) {
        final_color = color_acc / weight_acc;
    } else {
        let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
        let luma = dot(base, vec3<f32>(0.299, 0.587, 0.114));
        final_color = blackbodyColor(mix(tempRangeLow, tempRangeHigh, luma));
    }

    // ── Idea: cooling afterglow. Last frame's pre-ACES heat shifts toward red.
    let prevHeat = textureLoad(dataTextureC, coord, 0).rgb;
    let cooled = prevHeat * vec3<f32>(1.08, 0.62, 0.38);
    final_color = mix(final_color, cooled, 0.14);

    let vignette = 1.0 - smoothstep(0.3, 1.2, dist);
    final_color *= vignette;

    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - center);
    let mouseHeat = exp(-mouseDist * mouseDist * 400.0) * mouseDown;
    let hotColor = blackbodyColor(tempRangeHigh * 1.2);
    final_color = mix(final_color, hotColor, select(0.0, mouseHeat * 0.5, mouseHeat > 0.001));

    let display = toneMapACES(max(final_color, vec3<f32>(0.0)));
    let alpha = clamp(vignette, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(final_color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
