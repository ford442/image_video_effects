// ═══════════════════════════════════════════════════════════════════
//  Hyper-Space Jump Blackbody
//  Category: advanced-hybrid
//  Features: radial-streaks, blackbody-radiation, relativistic, HDR
//  Complexity: Very High
//  Chunks From: hyper-space-jump, spec-blackbody-thermal
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  High-velocity radial streaking where each streak's luminance maps
//  to blackbody temperature. Bright streaks burn blue-white, dim
//  streaks glow amber-red. Creates a thermally-colored warp tunnel.
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

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal) ═══
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

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    // Parameters
    let strength = u.zoom_params.x * 0.1;
    let samples = 24;
    let center = u.zoom_config.yz;

    let aspect = res.x / res.y;
    let center_aspect = vec2<f32>(center.x * aspect, center.y);
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    var dir = uv_aspect - center_aspect;
    let dist = length(dir);
    let dir_norm = normalize(dir);
    let dir_uv = uv - center;

    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);

    var color_acc = vec3<f32>(0.0);
    var temp_acc = 0.0;
    var weight_acc = 0.0;

    let decay = 0.95;
    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.y);
    let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.z);

    for (var i = 0; i < samples; i = i + 1) {
        let f = f32(i);
        let offset = dir_uv * (f / f32(samples)) * strength * dist * 10.0;
        let sample_uv = uv - offset;

        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            continue;
        }

        let jitter_offset = offset * (noise - 0.5) * 0.1;
        let s_color = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset, 0.0);

        // Chromatic aberration on streaks
        let r = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset + dir_uv * 0.005 * f, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset - dir_uv * 0.005 * f, 0.0).b;
        let sample_color = vec3<f32>(r, s_color.g, b);

        let luma = dot(sample_color, vec3<f32>(0.299, 0.587, 0.114));
        let weight = pow(decay, f) * (0.1 + smoothstep(0.3, 1.0, luma) * 2.0);

        // Map luminance to temperature for this streak sample
        let sampleTemp = mix(tempRangeLow, tempRangeHigh, luma);
        let thermalColor = blackbodyColor(sampleTemp);

        color_acc += thermalColor * weight;
        temp_acc += sampleTemp * weight;
        weight_acc += weight;
    }

    var final_color = vec3<f32>(0.0);
    var avgTemp = tempRangeLow;
    if (weight_acc > 0.001) {
        final_color = color_acc / weight_acc;
        avgTemp = temp_acc / weight_acc;
    } else {
        let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
        let luma = dot(base, vec3<f32>(0.299, 0.587, 0.114));
        final_color = blackbodyColor(mix(tempRangeLow, tempRangeHigh, luma));
    }

    // Vignette tunnel darkening
    let vignette = 1.0 - smoothstep(0.3, 1.2, dist);
    final_color *= vignette;

    // Mouse heat boost
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - center);
    let mouseHeat = exp(-mouseDist * mouseDist * 400.0) * mouseDown;
    if (mouseHeat > 0.001) {
        let hotColor = blackbodyColor(tempRangeHigh * 1.2);
        final_color = mix(final_color, hotColor, mouseHeat * 0.5);
    }

    let display = toneMapACES(final_color);
    let alpha = vignette;

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(final_color, alpha));

    // Clear depth for hyper-space effect
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0));
}
