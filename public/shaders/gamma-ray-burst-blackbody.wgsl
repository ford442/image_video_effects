// ═══════════════════════════════════════════════════════════════════
//  Gamma Ray Burst Blackbody
//  Category: advanced-hybrid
//  Features: radial-blur, blackbody-thermal, mouse-driven, HDR, exposure-burst, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: gamma-ray-burst.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  Upgraded: 2026-09-15, 2026-11-01
//  Ideas: bipolar jet lobes on atan2; afterglow energy stored in C.a; blast-wave shell; red cooling afterglow
//  A packing: raw burst RGB + energy
// ═══════════════════════════════════════════════════════════════════
//  Intense gamma-ray burst with physically-correct blackbody thermal
//  coloring. Radial blur samples are mapped to temperature via luminance,
//  creating an authentic stellar explosion from deep-red embers to
//  blue-white plasma at the epicenter.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / max(res.y, 0.001);
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = (u.zoom_params.x * 2.0 + 0.5) * (1.0 + bass * 0.35);
    let decay = u.zoom_params.y * 0.1 + 0.9;
    let rayDensity = u.zoom_params.z * 50.0 + 10.0;
    let exposure = (u.zoom_params.w * 2.0 + 1.0) * (1.0 + bass * 0.25);
    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.x);
    let tempRangeHigh = mix(4000.0, 20000.0, u.zoom_params.y);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.z);

    let mouse = u.zoom_config.yz;
    let dir = uv - mouse;
    let dist = length(dir * vec2<f32>(aspect, 1.0));

    let samples = 20;
    var acc = vec3<f32>(0.0);
    var weightSum = 0.0;
    let dither = hash12(uv * time);

    for (var i = 0; i < samples; i = i + 1) {
        let t = (f32(i) + dither) / f32(samples);
        let sampleUV = clamp(mix(uv, mouse, t * 0.3 * intensity), vec2<f32>(0.0), vec2<f32>(1.0));
        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let w = pow(decay, f32(i));
        let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
        let boost = smoothstep(0.5, 1.0, luma) * 2.0;

        let temperature = mix(tempRangeLow, tempRangeHigh, luma);
        let thermal = blackbodyColor(temperature) * thermalIntensity;
        let thermallyTinted = mix(col, thermal, 0.6);

        acc += thermallyTinted * w * (1.0 + boost);
        weightSum += w;
    }

    var rawColor = acc / max(weightSum, 0.001);

    let angle = atan2(dir.y, dir.x);
    // Idea 1 — bipolar jet lobes (two collimated opposite beams, not a sunflower)
    let jetAxis = time * 0.12;
    let ca = cos(angle - jetAxis);
    let collimation = mix(6.0, 22.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let lobe = pow(max(abs(ca), 0.0), collimation);
    let ray = sin(angle * rayDensity + time * 2.0)
            + 0.5 * sin(angle * rayDensity * 2.3 - time);
    let rayInJet = smoothstep(0.0, 1.0, ray) * lobe * (1.0 + treble * 0.3);
    let jetMask = lobe * smoothstep(1.2, 0.04, dist) * (1.0 + mids * 0.35);
    let rayColor = mix(vec3<f32>(0.5, 0.8, 1.0), blackbodyColor(tempRangeHigh) * thermalIntensity, 0.5);
    rawColor += rayColor * (jetMask * 0.22 + rayInJet * 0.08) * intensity / (dist + 0.1);

    // ── Idea 3: blast-wave shell. The burst's own ring, not a click ripple.
    let shellR = fract(time * (0.17 + bass * 0.1)) * 0.9;
    let shell = exp(-abs(dist - shellR) * 28.0) * (1.0 - shellR) * intensity;
    rawColor += blackbodyColor(tempRangeHigh * (1.0 - shellR * 0.4)) * thermalIntensity * shell * 0.2;

    let glare = 1.0 / (dist * 10.0 + 0.1);
    let coreTemp = mix(tempRangeHigh * 0.8, tempRangeHigh, smoothstep(0.1, 0.0, dist));
    let coreColor = mix(vec3<f32>(1.0, 0.95, 0.8), blackbodyColor(coreTemp) * thermalIntensity, 0.5);
    rawColor += coreColor * glare * exposure * 0.5;

    rawColor *= smoothstep(1.5, 0.0, dist);

    // Idea 2 — afterglow from exact C (energy in .a, raw RGB; not display)
    let prev = textureLoad(dataTextureC, coord, 0);
    // ── Idea 4: red afterglow. The stored tail is warmer than the prompt.
    let cooled = prev.rgb * (0.78 + decay * 0.12) * vec3<f32>(1.0, 0.46, 0.14);
    rawColor += cooled * prev.a * 0.55;

    let energy = clamp(length(rawColor) * 0.12 + glare * 0.15 + jetMask * 0.35, 0.0, 1.0);
    let alpha = clamp(energy * 0.55 + jetMask * 0.3 + glare * 0.08 + 0.12, 0.0, 1.0);
    let display = toneMapACES(rawColor);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(rawColor, energy));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
