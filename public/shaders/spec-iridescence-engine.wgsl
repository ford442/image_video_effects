// ═══════════════════════════════════════════════════════════════════
//  spec-iridescence-engine
//  Category: advanced-hybrid
//  Features: thin-film-interference, depth-aware, spectral-render, mouse-driven, audio-reactive
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
//  Upgraded: 2026-08-02 — wired dead audio (spectral FFT voices),
//  sprung film lens (always-on hover), click film waves (ripples[])
// ═══════════════════════════════════════════════════════════════════
//  Thin-Film Interference (Soap Bubbles / Oil Slicks)
//  Simulates thin-film interference where reflected color depends on
//  viewing angle and film thickness. Uses depth texture for thickness.
//  Audio: plasmaBuffer FFT bins ride per-wavelength RGB channels so
//  music plays across the rainbow; bass breathes the intensity.
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;

    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    // Slider params (saved-preset contract — ids/defaults fixed):
    //   x: Film Thickness -> base film thickness in nm
    //   y: Film IOR       -> refractive index of the film
    //   z: Intensity      -> iridescence gain
    //   w: Turbulence     -> animated noise thickness amplitude
    let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
    var intensity = mix(0.3, 1.5, u.zoom_params.z);
    let turbulence = mix(0.0, 1.0, u.zoom_params.w);

    let isMouseDown = u.zoom_config.w > 0.5;

    // ── Sprung film lens (mouse matters unpressed) ─────────────────
    // Critically-damped spring chasing the raw mouse. Persistent state
    // lives in extraBuffer[133..137] = (pos.xy, vel.xy, init flag) — [0..4] is
    // reserved and [5..132] belongs to the engine FFT bins.
    let rawMouse = u.zoom_config.yz;
    var sprung = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var vel = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    if (extraBuffer[137u] < 0.5) {
        sprung = rawMouse; // cold start: snap to the cursor
        vel = vec2<f32>(0.0);
    }
    let dt = 0.016;              // fixed per-frame step
    let omega = 10.0;            // spring rate (critically damped)
    let accel = (rawMouse - sprung) * (omega * omega) - vel * (2.0 * omega);
    vel = vel + accel * dt;
    sprung = clamp(sprung + vel * dt, vec2<f32>(-0.25), vec2<f32>(1.25));
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133u] = sprung.x;
        extraBuffer[134u] = sprung.y;
        extraBuffer[135u] = vel.x;
        extraBuffer[136u] = vel.y;
        extraBuffer[137u] = 1.0;
    }

    // Sample base image and depth
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Viewing angle from pixel position (simulated)
    let toCenter = uv - vec2<f32>(0.5);
    let dist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

    // Film thickness varies with depth + animated noise
    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - time * 0.15) * 0.25;

    var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

    // Always-on thickness lens around the SPRUNG point: hovering tilts
    // the film with a gentle aspect-corrected gaussian (~0.25 radius).
    let aspect = res.x / max(res.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let lensVec = (uv - sprung) * aspectVec;
    let lensDist = length(lensVec);
    let lensRadius = 0.25;
    let lensG = exp(-(lensDist * lensDist) / (lensRadius * lensRadius));
    thickness += 80.0 * lensG;

    // Mouse interaction: local thickness perturbation (rides the SPRUNG
    // position so the held press lags and settles with the spring)
    if (isMouseDown) {
        let mouseDist = length((uv - sprung) * aspectVec);
        let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
        thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
    }

    // Click film waves: each live ripple launches an expanding thickness
    // wave from its click point (~1.5s life), sending iridescent rings
    // across the oil slick.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 1.5) {
            continue;
        }
        let rVec = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
        let rDist = length(rVec);
        let ring = exp(-abs(rDist - age * 0.45) * 18.0); // expanding ring mask
        thickness += 150.0 * sin(age * 20.0 - rDist * 40.0) * exp(-age * 2.0) * ring;
    }

    // ── WIRE THE DEAD AUDIO: per-wavelength spectral voices ────────
    // Global bass breathing on intensity.
    let bass = plasmaBuffer[0u].x;
    intensity = intensity * (1.0 + bass * 0.3);

    var iridescent = thinFilmColor(thickness, cosTheta, filmIOR);

    // FFT bins mapped across the visible range — high wavelengths ride
    // high bins, so music plays across the rainbow.
    iridescent = vec3<f32>(
        iridescent.r * (1.0 + plasmaBuffer[7u].x * 0.25),
        iridescent.g * (1.0 + plasmaBuffer[4u].x * 0.25),
        iridescent.b * (1.0 + plasmaBuffer[2u].x * 0.25)
    ) * intensity;

    // Fresnel-like blend based on viewing angle
    let fresnel = pow(1.0 - cosTheta, 3.0);
    let outColor = mix(baseColor, iridescent, fresnel * 0.7);

    // HDR tone map
    let tonemapped = outColor / (1.0 + outColor * 0.2);

    // Alpha stores film thickness for downstream use
    let thicknessAlpha = clamp(thickness / 1000.0, 0.0, 1.0);
    textureStore(writeTexture, gid.xy, vec4<f32>(tonemapped, thicknessAlpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(iridescent, thicknessAlpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
