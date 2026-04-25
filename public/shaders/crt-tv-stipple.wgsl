// ═══════════════════════════════════════════════════════════════════
//  CRT TV Stipple
//  Category: advanced-hybrid
//  Features: crt-simulation, blue-noise, stippling, barrel-distortion
//  Complexity: High
//  Chunks From: crt-tv.wgsl, spec-blue-noise-stipple.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Authentic CRT phosphor physics merged with blue-noise stippled
//  pointillism. Aperture grille shadow mask uses perceptually optimal
//  blue-noise dot distributions instead of regular stripes.
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

// ═══ CHUNK: hash22 (from spec-blue-noise-stipple.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Blue-noise offset via plastic constant
fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
    return fract(pixelCoord * phi2 + frame * phi2);
}

// Barrel distortion for CRT curvature
fn curve_uv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
    var centered = uv * 2.0 - 1.0;
    let dist_sq = dot(centered, centered);
    centered = centered * (1.0 + curvature * dist_sq);
    return centered * 0.5 + 0.5;
}

// Phosphor decay simulation
fn phosphor_decay(base_color: vec3<f32>, time: f32, flicker: f32) -> vec3<f32> {
    let decay_rates = vec3<f32>(2.5, 5.0, 10.0);
    let refresh_flicker = 1.0 - flicker * 0.03 * sin(time * 377.0);
    let hum_bar = 1.0 - flicker * 0.02 * sin(time * 6.28 * 0.5);
    var decayed = base_color;
    decayed.r = pow(decayed.r, 1.0 / decay_rates.r) * refresh_flicker * hum_bar;
    decayed.g = pow(decayed.g, 1.0 / decay_rates.g) * refresh_flicker * hum_bar;
    decayed.b = pow(decayed.b, 1.0 / decay_rates.b) * refresh_flicker * hum_bar;
    return decayed;
}

// Blue-noise stippled aperture grille
fn stipple_grille(uv: vec2<f32>, resolution: vec2<f32>, dotScale: f32, time: f32) -> vec3<f32> {
    let cellSize = 1.0 / dotScale;
    let cellId = floor(uv * dotScale);
    let cellLocal = fract(uv * dotScale) - 0.5;

    // Sample local color for luminance-driven dot size
    let sampleUV = (cellId + 0.5) / dotScale;
    let localColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let luma = dot(localColor, vec3<f32>(0.299, 0.587, 0.114));

    // RGB subpixel offsets within triad
    let triadX = fract(cellId.x / 3.0) * 3.0;
    var subpixelOffset = vec2<f32>(0.0);
    var mask = vec3<f32>(0.0);
    if (triadX < 1.0) {
        subpixelOffset = vec2<f32>(-0.25, 0.0);
        mask.r = 1.0;
    } else if (triadX < 2.0) {
        subpixelOffset = vec2<f32>(0.0, 0.0);
        mask.g = 1.0;
    } else {
        subpixelOffset = vec2<f32>(0.25, 0.0);
        mask.b = 1.0;
    }

    // Blue-noise jittered dot center
    let jitter = blueNoiseOffset(cellId + subpixelOffset * 10.0, time * 0.1);
    let dotCenter = (jitter - 0.5) * 0.6 + subpixelOffset * 0.3;

    // Dot size based on luminance
    let dotSize = mix(0.45, 0.08, luma);
    let dist = length(cellLocal - dotCenter);
    let edgeWidth = 0.06;
    let dotMask = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, dist);

    return mask * dotMask;
}

// Scanline simulation
fn scanlines(uv: vec2<f32>, resolution: vec2<f32>, intensity: f32, time: f32) -> f32 {
    let scan_freq = resolution.y * 0.5;
    let scan_y = uv.y * scan_freq;
    let scan_profile = 0.5 + 0.5 * cos(fract(scan_y) * 6.28318530718);
    let phosphor_bright = smoothstep(0.0, 0.3, fract(scan_y)) * smoothstep(1.0, 0.7, fract(scan_y));
    let jitter = sin(time * 10.0 + uv.y * 100.0) * 0.02;
    let thickness = 0.85 + jitter;
    let scan_darken = 1.0 - intensity * 0.4 * (1.0 - smoothstep(thickness, 1.0, scan_profile));
    let scan_boost = 1.0 + intensity * 0.15 * phosphor_bright;
    return scan_darken * scan_boost;
}

// Vignette
fn crt_vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let centered = uv * 2.0 - 1.0;
    let dist = length(centered);
    let vig = 1.0 - smoothstep(0.6, 1.4, dist * (0.8 + strength * 0.4));
    let corner = abs(centered.x * centered.y);
    return vig * (1.0 - corner * 0.15 * strength);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    let scanline_intensity = u.zoom_params.x;
    let phosphor_glow = u.zoom_params.y;
    let stipple_density = mix(20.0, 80.0, u.zoom_params.z);
    let barrel_amount = u.zoom_params.w;

    let curvature = barrel_amount * 0.15;
    let flicker_amount = 0.5 + barrel_amount * 0.5;
    let chromatic_str = 0.002 * barrel_amount;

    // Barrel distortion
    var crt_uv = uv;
    if (barrel_amount > 0.01) {
        crt_uv = curve_uv(uv, curvature);
    }

    // Bounds check
    if (crt_uv.x < 0.0 || crt_uv.x > 1.0 || crt_uv.y < 0.0 || crt_uv.y > 1.0) {
        textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    // Chromatic aberration
    let r = textureSampleLevel(readTexture, u_sampler, crt_uv + vec2<f32>(chromatic_str, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, crt_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, crt_uv - vec2<f32>(chromatic_str, 0.0), 0.0).b;
    var color = vec3<f32>(r, g, b);

    // Blue-noise stipple aperture grille
    let mask = stipple_grille(crt_uv, res, stipple_density, time);
    color = color * (0.3 + mask * 0.7);

    // Scanlines
    let scan_mod = scanlines(crt_uv, res, scanline_intensity, time);
    color = color * scan_mod;

    // Phosphor glow
    if (phosphor_glow > 0.01) {
        let brightness = dot(color, vec3<f32>(0.299, 0.587, 0.114));
        let bloom = smoothstep(0.4, 0.9, brightness) * phosphor_glow * 0.4;
        color = mix(color, pow(color, vec3<f32>(0.7)), phosphor_glow * 0.3);
        color = color + color * bloom;
    }

    // Phosphor decay
    color = phosphor_decay(color, time, flicker_amount);

    // Vignette
    let vignette = crt_vignette(uv, 0.5 + barrel_amount * 0.5);
    color = color * vignette;

    // Warm tint and gamma
    color = color * vec3<f32>(1.05, 1.02, 0.98);
    color = pow(color, vec3<f32>(1.0 / 2.2));
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
