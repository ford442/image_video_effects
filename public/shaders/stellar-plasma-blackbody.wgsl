// ═══════════════════════════════════════════════════════════════════
//  stellar-plasma-blackbody
//  Category: advanced-hybrid
//  Features: generative, blackbody-radiation, procedural, audio-reactive
//  Complexity: High
//  Chunks From: stellar-plasma.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-1 — Spectral & Physical Light Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Cosmic nebula domain-warped FBM blended with Planck's law
//  blackbody thermal coloring. Energy intensity drives temperature
//  mapping — cool voids glow ember-red, hot plasma cores burn
//  blue-white with physically-correct radiance scaling.
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
  zoom_params: vec4<f32>,  // x=TempShift, y=Speed, z=ZoomScale, w=ThermalIntensity
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash & fbm (from stellar-plasma.wgsl) ═══
const HASH_CONST1: vec3<f32> = vec3<f32>(0.1031, 0.1031, 0.1031);
const HASH_CONST2: vec3<f32> = vec3<f32>(33.33, 33.33, 33.33);

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * HASH_CONST1);
    p3 += dot(p3, p3.yzx + HASH_CONST2);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    let u_f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u_f.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u_f.x),
        u_f.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0, 100.0);
    let c: f32 = 0.87758256189;
    let s: f32 = 0.4794255386;
    let rot = mat2x2<f32>(vec2<f32>(c, s), vec2<f32>(-s, c));
    var p_mut = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * noise(p_mut);
        p_mut = rot * p_mut * 2.0 + shift;
        a *= 0.5;
    }
    return v;
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / res;
    var p = uv * 2.0 - 1.0;
    p.x *= res.x / res.y;

    let dist = length(p);
    let lodFactor = smoothstep(1.5, 2.5, dist);

    if (dist > 3.0) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        return;
    }

    // Parameters
    let tempShift = u.zoom_params.x;
    let speed = mix(0.5, 2.0, u.zoom_params.y);
    let scale = mix(1.0, 4.0, u.zoom_params.z);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.w);

    // Audio reactivity
    let audioLow = u.config.y;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioMid * 0.3;
    let time = u.config.x * speed * audioReactivity;

    // Mouse interaction
    var mouse_pos = u.zoom_config.yz * 2.0 - 1.0;
    mouse_pos.x *= res.x / res.y;
    let dist_to_mouse = length(p - mouse_pos);
    let mouse_influence = exp(-dist_to_mouse * 3.0) * select(0.0, 1.0, u.zoom_config.w > 0.5);

    var q_pos = p * scale + mouse_influence;
    let octaves = i32(mix(6.0, 3.0, lodFactor));

    // Domain warping
    var q = vec2<f32>(
        fbm(q_pos + vec2<f32>(0.0, time * 0.2), octaves),
        fbm(q_pos + vec2<f32>(1.0, 2.0) + time * 0.2, octaves)
    );
    var r = vec2<f32>(
        fbm(q_pos + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, octaves),
        fbm(q_pos + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, octaves)
    );
    var f = fbm(q_pos + 4.0 * r, octaves);

    // Map plasma energy to temperature (800K - 15000K)
    // f is in ~0..1 range from FBM; boost with audio and structure
    let energy = clamp(f * f * f + 0.4 * f * f + 0.3 * length(q) + 0.2 * length(r.x), 0.0, 1.0);
    let audioHeatBoost = (audioLow - audioHigh) * 0.15;
    var temperature = mix(1200.0, 12000.0, energy + tempShift * 0.3 + audioHeatBoost);
    temperature = clamp(temperature, 800.0, 15000.0);

    // Blackbody thermal color
    var thermalColor = blackbodyColor(temperature) * thermalIntensity;

    // Add localized hotspot glow around high-energy regions
    let glowRadius = 0.02;
    var glowAccum = vec3<f32>(0.0);
    let glowSamples = 12;
    for (var i: i32 = 0; i < glowSamples; i = i + 1) {
        let angle = f32(i) * 0.523599 + time * 0.3;
        let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
        let sUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        // Approximate energy at offset using fast noise
        let sP = sUV * 2.0 - 1.0;
        let sEnergy = clamp(fbm(sP * scale, 3) * 0.7 + 0.3, 0.0, 1.0);
        let sTemp = mix(1200.0, 12000.0, sEnergy + tempShift * 0.3);
        glowAccum += blackbodyColor(clamp(sTemp, 800.0, 15000.0)) * thermalIntensity;
    }
    glowAccum /= f32(glowSamples);
    thermalColor = mix(thermalColor, glowAccum, 0.35);

    // Tone map HDR output
    let displayColor = toneMapACES(thermalColor);

    // Mouse creates local super-hotspot
    if (u.zoom_config.w > 0.5) {
        let mouseDistUV = length(uv - u.zoom_config.yz);
        let mouseHeat = exp(-mouseDistUV * mouseDistUV * 400.0);
        let hotspot = blackbodyColor(15000.0 * mouseHeat) * thermalIntensity;
        let finalWithHotspot = displayColor + toneMapACES(hotspot);
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithHotspot, 1.0));
    } else {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(displayColor, 1.0));
    }

    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(thermalColor, temperature / 15000.0));
}
