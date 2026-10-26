// ═══════════════════════════════════════════════════════════════════
//  Sim: Volumetric Fake (Fast God Rays)
//  Category: lighting-effects
//  Features: simulation, fake-volumetrics, radial-blur, god-rays, upgraded-rgba, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-10-26
//  Ideas: depth occlusion vs the light; discrete dust motes on radial taps; Beer-Lambert march (§12.2F); Henyey-Greenstein lobe (§12.2F)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn hg(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = max(1.0 + g2 - 2.0 * g * cosTheta, 0.0001);
    return (1.0 - g2) / max(pow(denom, 1.5), 0.0001);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    let lightIntensity = mix(0.5, 2.0, u.zoom_params.x);
    let dustDensity = mix(0.0, 1.0, u.zoom_params.y);
    let scattering = mix(0.3, 1.5, u.zoom_params.z);
    let noiseSpeed = mix(0.1, 1.0, u.zoom_params.w);

    let lightPos = vec2<f32>(
        0.5 + cos(time * 0.2) * 0.3,
        0.2 + sin(time * 0.15) * 0.1
    );

    let toLight = lightPos - uv;
    let distToLight = max(length(toLight), 0.001);
    let dirToLight = toLight / distToLight;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let lightDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(lightPos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;

    var volumetric = vec3<f32>(0.0);
    var motes = 0.0;
    let samples = i32(16.0 + dustDensity * 16.0);
    var occlusion = 0.0;

    for (var i = 0; i < 32; i++) {
        if (i >= samples) { break; }
        let t = f32(i) / f32(max(samples, 1));
        let samplePos = uv + dirToLight * t * distToLight;
        if (samplePos.x < 0.0 || samplePos.x > 1.0 || samplePos.y < 0.0 || samplePos.y > 1.0) {
            continue;
        }
        let sampleColor = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).rgb;
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, samplePos, 0.0).r;
        let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
        // Idea 1: occluder closer to camera than the light blocks the shaft
        let blocked = step(lightDepth + 0.02, sampleDepth);
        occlusion += luma * (1.0 - t) * (1.0 - blocked);
        // ── Idea 1: Beer-Lambert along the march (§12.2F) ───────────
        let extinct = exp(-t * scattering * (0.35 + dustDensity));
        let attenuation = (1.0 - t) * (1.0 - t) * (1.0 - blocked) * extinct;
        volumetric += vec3<f32>(1.0) * attenuation;
        // Idea 2: discrete motes on taps
        let mote = step(0.92, hash12(floor(samplePos * 80.0) + vec2<f32>(time * noiseSpeed, f32(i))));
        motes += mote * attenuation * dustDensity;
    }

    volumetric /= f32(max(samples, 1));
    occlusion = clamp(occlusion / f32(max(samples, 1)), 0.0, 1.0);
    motes /= f32(max(samples, 1));

    let dustNoise = noise(uv * 20.0 + time * noiseSpeed) * noise(uv * 15.0 - time * noiseSpeed * 0.5);
    let dust = pow(dustNoise, 3.0) * dustDensity;

    let density = 0.3 * scattering * (1.0 + bass * 0.3);
    var lightRays = volumetric * (1.0 - occlusion) * density * lightIntensity;
    lightRays += vec3<f32>(dust * lightIntensity * 0.5);
    lightRays += vec3<f32>(1.0, 0.97, 0.88) * motes * lightIntensity * 2.2;
    let sunColor = vec3<f32>(1.0, 0.95, 0.8);
    lightRays *= sunColor;

    var color = src.rgb + lightRays;
    let lightDir = normalize(vec2<f32>(0.5) - lightPos);
    let viewDir = normalize(uv - lightPos);
    // ── Idea 2: Henyey-Greenstein (§12.2F) ──────────────────────────
    // Same angle as the old alignment term. Peak brightness is matched
    // to that term; scattering sets how tight the forward lobe is.
    let gPhase = clamp((scattering - 0.3) / 1.2 * 0.72, 0.0, 0.72);
    let cosT = clamp(dot(viewDir, lightDir), -1.0, 1.0);
    let phase = hg(cosT, gPhase);
    let phaseN = phase / max(hg(1.0, gPhase), 0.001);
    color += sunColor * phaseN * lightIntensity * 0.1;
    let falloff = 1.0 / (1.0 + distToLight * distToLight * 2.0);
    color = mix(src.rgb, color, falloff);

    let alpha = clamp(0.55 + length(lightRays) * 0.8 + treble * 0.1, 0.0, 1.0) * src.a;
    let display = vec4<f32>(aces(max(color, vec3<f32>(0.0))), alpha);
    textureStore(writeTexture, gid.xy, display);
    textureStore(dataTextureA, gid.xy, display);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
