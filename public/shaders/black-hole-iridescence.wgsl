// ═══════════════════════════════════════════════════════════════════
//  black-hole-iridescence
//  Category: advanced-hybrid
//  Features: gravitational-lensing, thin-film-interference, accretion-disk
//  Complexity: High
//  Chunks From: black-hole.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Gravitational lensing black hole with iridescent accretion disk.
//  The warped background and glowing disk receive thin-film
//  interference coloring based on viewing angle, producing soap-bubble
//  and oil-slick chromatic effects around the event horizon.
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

// ═══ CHUNK: hash12 (from spec-iridescence-engine.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: wavelengthToRGB (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

// ═══ CHUNK: thinFilmColor (from spec-iridescence-engine.wgsl) ═══
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
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // Parameters
    let gravity = u.zoom_params.x;
    let radius = u.zoom_params.y * 0.3;
    let glow_intensity = u.zoom_params.z;
    let lensing_scale = u.zoom_params.w;

    let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.z);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
    let iridIntensity = mix(0.3, 1.5, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Vector from mouse to pixel
    let d_vec_raw = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec_raw.x * aspect, d_vec_raw.y);
    let dist = length(d_vec_aspect);

    var final_color = vec3<f32>(0.0, 0.0, 0.0);
    var alpha = 1.0;

    if (dist < radius) {
        // Event horizon — pure black with subtle iridescent rim
        let rimDist = dist / radius;
        let rimGlow = smoothstep(0.8, 1.0, rimDist);
        let toCenter = uv - vec2<f32>(0.5);
        let viewDist = length(toCenter);
        let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));
        let rimIrid = thinFilmColor(filmThicknessBase * 0.5, cosTheta, filmIOR) * iridIntensity;
        final_color = rimIrid * rimGlow * 0.5;
        alpha = rimGlow * 0.3;
    } else {
        // Gravitational lensing
        let dist_from_surface = dist - radius;
        let distortion = (gravity * 0.1) / (dist_from_surface * 5.0 + 0.1);
        let pinch_factor = distortion * (0.5 + lensing_scale);
        let offset = normalize(d_vec_aspect) * pinch_factor;
        let offset_uv = vec2<f32>(offset.x / aspect, offset.y);
        let sample_uv = uv - offset_uv;
        let bg_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

        // Accretion disk glow
        let glow_falloff = exp(-dist_from_surface * 20.0);
        let glow_color = vec3<f32>(1.0, 0.7, 0.3) * glow_intensity * 3.0 * glow_falloff;

        // ═══ Iridescence on accretion disk ═══
        let toCenter = uv - vec2<f32>(0.5);
        let viewDist = length(toCenter);
        let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));

        let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5
                     + hash12(uv * 25.0 - time * 0.15) * 0.25;
        var thickness = filmThicknessBase * (0.7 + glow_falloff * 0.6 + noiseVal * 0.3);

        if (isMouseDown) {
            let mouseDist = length(uv - mouse);
            let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
            thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
        }

        let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;

        // Fresnel blend
        let fresnel = pow(1.0 - cosTheta, 3.0);
        let diskColor = mix(glow_color, iridescent, fresnel * 0.7);

        final_color = bg_color + diskColor;
        alpha = 1.0;
    }

    // Tone map
    final_color = final_color / (1.0 + final_color * 0.2);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, alpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(final_color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
