// ═══════════════════════════════════════════════════════════════════
//  bioluminescent-blackbody
//  Category: advanced-hybrid
//  Features: organic-growth, blackbody-thermal, bioluminescence
//  Complexity: High
//  Chunks From: bioluminescent.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Living organic growth patterns with physically-correct thermal
//  coloring. Growth energy maps to blackbody temperature — cooler
//  regions glow deep red, active growth burns orange-yellow, and
//  intense bioluminescent hotspots reach white-hot temperatures.
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

// ═══ CHUNK: hash (from bioluminescent.wgsl) ═══
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3d(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    var u = f * f * (3.0 - 2.0 * f);
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    return mix(mix(mix(hash(vec2<f32>(n + 0.0, 0.0)), hash(vec2<f32>(n + 1.0, 0.0)), u.x),
                   mix(hash(vec2<f32>(n + 57.0, 0.0)), hash(vec2<f32>(n + 58.0, 0.0)), u.x), u.y),
               mix(mix(hash(vec2<f32>(n + 113.0, 0.0)), hash(vec2<f32>(n + 114.0, 0.0)), u.x),
                   mix(hash(vec2<f32>(n + 170.0, 0.0)), hash(vec2<f32>(n + 171.0, 0.0)), u.x), u.y), u.z);
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let texel = 1.0 / res;

    // Parameters
    let spread_mult = 1.0 + u.zoom_params.x * 0.1;
    let branch_density = u.zoom_params.y;
    let glow_intensity = u.zoom_params.z;
    let spore_count = u32(u.zoom_params.w * 10.0);
    let growth_rate = u.zoom_config.x;
    let pulse = u.zoom_config.z;
    let depth_influence = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Initialize or load growth state
    var growth = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Interactive Spore Placement
    for (var i: u32 = 0u; i < min(50u, spore_count + 1u); i = i + 1u) {
        if (i < u32(u.config.y)) {
            let ripple = u.ripples[i];
            let center = ripple.xy;
            let age = time - ripple.z;
            if (age > 0.1 && age < 2.0) {
                let aspect = res.x / res.y;
                let d_aspect = distance(uv * vec2<f32>(aspect, 1.0), center * vec2<f32>(aspect, 1.0));
                let influence = smoothstep(0.05, 0.0, d_aspect) * (1.0 - smoothstep(1.5, 2.0, age));
                growth = max(growth, influence);
            }
        }
    }

    // Simple growth diffusion
    let n1 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let n2 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let n3 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let n4 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let neighbor_avg = (n1 + n2 + n3 + n4) * 0.25;
    let depth_mask = smoothstep(0.1, 0.9, depth);
    let noise_val = noise3d(vec3<f32>(uv * 5.0, time * 0.1));

    if (growth_rate > 0.01) {
        growth = min(1.0, growth * 0.998 + neighbor_avg * spread_mult * depth_mask * branch_density);
    }

    textureStore(dataTextureA, gid.xy, vec4<f32>(growth, 0.0, 0.0, 1.0));

    // Vein structure
    let vein_noise = noise3d(vec3<f32>(uv * 20.0, time * 0.5));
    let veins = smoothstep(0.3, 0.7, growth + vein_noise * 0.2);

    // ═══ Blackbody thermal coloring based on growth energy ═══
    // Map growth intensity to temperature:
    // Low growth = 1200K (deep red)
    // Medium growth = 4000K (orange-yellow)
    // High growth = 9000K (blue-white)
    let tempLow = 1200.0;
    let tempHigh = 9000.0;
    let growthEnergy = pow(growth, 1.5) * glow_intensity;
    let temperature = mix(tempLow, tempHigh, growthEnergy);
    var bio_light = blackbodyColor(temperature);

    // Pulse modulation
    let pulse_beat = sin(time * 10.0 + pulse * 5.0) * 0.3 + 0.7;
    bio_light = bio_light * pulse_beat;

    // Subsurface scattering
    let ss_scatter = smoothstep(0.0, 0.5, growth) * 0.3;

    // Organic absorption
    let absorptionR = exp(-growth * 1.2);
    let absorptionG = exp(-growth * 0.9);
    let absorptionB = exp(-growth * 0.7);
    let scattered = vec3<f32>(
        base_color.r * absorptionR,
        base_color.g * absorptionG,
        base_color.b * absorptionB
    );
    let veinScatter = veins * vec3<f32>(0.3, 0.5, 0.4) * growth;
    let scatteredBase = scattered + veinScatter;

    // Composition
    let growth_alpha = mix(0.25, 0.92, growth * glow_intensity);
    var final_color = scatteredBase * (1.0 - veins * 0.3) + bio_light + ss_scatter;

    // Tone map
    final_color = toneMapACES(final_color);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, growth_alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
