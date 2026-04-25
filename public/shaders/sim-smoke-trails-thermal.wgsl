// ═══════════════════════════════════════════════════════════════════
//  sim-smoke-trails-thermal
//  Category: advanced-hybrid
//  Features: simulation, blackbody-radiation, volumetric-smoke, vorticity
//  Complexity: Very High
//  Chunks From: sim-smoke-trails.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-1 — Spectral & Physical Light Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Volumetric smoke fluid simulation with physically-correct
//  blackbody thermal coloring. Smoke temperature maps to Kelvin
//  via Planck's law — cool wisps glow ember-red, hot cores burn
//  blue-white. Stefan-Boltzmann radiance scaling preserves HDR.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DensityScale, y=Turbulence, z=RiseSpeed, w=ThermalIntensity
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (from sim-smoke-trails.wgsl) ═══
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

// ═══ CHUNK: curl noise (from sim-smoke-trails.wgsl) ═══
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let n1 = noise(p + vec2<f32>(eps, 0.0));
    let n2 = noise(p - vec2<f32>(eps, 0.0));
    let n3 = noise(p + vec2<f32>(0.0, eps));
    let n4 = noise(p - vec2<f32>(0.0, eps));
    return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;

    // Parameters
    let densityScale = mix(0.5, 2.0, u.zoom_params.x);
    let turbulence = mix(0.0, 2.0, u.zoom_params.y);
    let riseSpeed = mix(0.5, 3.0, u.zoom_params.z);
    let dissipation = 0.97;
    let thermalIntensity = mix(0.5, 2.5, u.zoom_params.w);

    // Read previous smoke state
    let prevSmoke = textureLoad(dataTextureC, gid.xy, 0);
    var smokeDensity = prevSmoke.r;
    var smokeTemp = prevSmoke.g;
    var velX = prevSmoke.b;
    var velY = prevSmoke.a;

    // Buoyancy force (hot smoke rises)
    let buoyancy = smokeTemp * riseSpeed * 0.01;
    velY += buoyancy;

    // Add turbulence
    let curl = curlNoise(uv * 3.0 + time * 0.1);
    velX += curl.x * turbulence * 0.01;
    velY += curl.y * turbulence * 0.005;

    // Advect smoke
    let prevUV = uv - vec2<f32>(velX, velY) * pixel * 3.0;
    let advectedSmoke = textureSampleLevel(dataTextureC, u_sampler, clamp(prevUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    smokeDensity = advectedSmoke.r * dissipation;
    smokeTemp = advectedSmoke.g * dissipation;

    // Seed smoke at bottom
    let bottomSource = smoothstep(0.05, 0.0, uv.y) * hash12(vec2<f32>(uv.x * 10.0, time * 0.5)) * densityScale;
    smokeDensity += bottomSource * 0.05;
    smokeTemp += bottomSource * 0.1;

    // Mouse smoke source
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseSource = smoothstep(0.08, 0.0, mouseDist) * 0.2;
    smokeDensity += mouseSource;
    smokeTemp += mouseSource * 1.5;

    // Ripple smoke sources
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let rippleAge = time - ripple.z;
            if (rippleAge > 0.0 && rippleAge < 4.0) {
                let rippleDist = length(uv - ripple.xy);
                let rippleSource = smoothstep(0.06, 0.0, rippleDist) * (1.0 - rippleAge / 4.0);
                smokeDensity += rippleSource * 0.3;
                smokeTemp += rippleSource * 0.5;
            }
        }
    }

    smokeDensity = clamp(smokeDensity, 0.0, 1.0);
    smokeTemp = clamp(smokeTemp, 0.0, 1.0);

    // Store simulation state
    textureStore(dataTextureA, gid.xy, vec4<f32>(smokeDensity, smokeTemp, velX * 0.99, velY * 0.99));

    // Render smoke with blackbody thermal coloring
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Map smokeTemp (0..1) to Kelvin (1000K..8000K)
    let temperature = mix(1000.0, 8000.0, smokeTemp);
    var thermalColor = blackbodyColor(temperature) * thermalIntensity;

    // Stefan-Boltzmann glow around hot dense regions
    let glowRadius = 0.015;
    var glowAccum = vec3<f32>(0.0);
    let glowSamples = 8;
    for (var i: i32 = 0; i < glowSamples; i = i + 1) {
        let angle = f32(i) * 0.785398 + time * 0.3;
        let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
        let sUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let sSample = textureSampleLevel(dataTextureC, u_sampler, sUV, 0.0);
        let sTemp = mix(1000.0, 8000.0, sSample.g);
        glowAccum += blackbodyColor(sTemp) * thermalIntensity;
    }
    glowAccum /= f32(glowSamples);
    thermalColor = mix(thermalColor, glowAccum, smokeDensity * 0.3);

    // Volumetric blending with tone-mapped thermal
    let alpha = 1.0 - exp(-smokeDensity * 3.0);
    let toneMapped = toneMapACES(thermalColor);
    var color = mix(baseColor, toneMapped, alpha * 0.8);

    // Add HDR glow at hot spots (post-tone-map for safety)
    let hotGlow = smokeTemp * smokeDensity * 0.25;
    color += vec3<f32>(hotGlow * 0.8, hotGlow * 0.4, hotGlow * 0.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, gid.xy, vec4<f32>(color, mix(0.85, 1.0, alpha)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - smokeDensity * 0.3), 0.0, 0.0, 0.0));
}
