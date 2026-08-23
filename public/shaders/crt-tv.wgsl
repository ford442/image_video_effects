// ═══════════════════════════════════════════════════════════════
//  CRT TV - Authentic Phosphor Physics Simulation
//  Category: retro-glitch
//  
//  Scientific Features:
//  - Phosphor persistence with per-channel decay (R>G>B)
//  - Aperture grille shadow mask (Trinitron-style)
//  - Halation glow (light scattering in glass)
//  - Barrel distortion with curvature
//  - Authentic scanline phosphor gaps
//  Upgraded: 2026-08-21 (Batch 42 - Audio Reactive CRT Bulge)
// ═══════════════════════════════════════════════════════════════

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

fn curve_uv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
    var centered = uv * 2.0 - 1.0;
    let dist_sq = dot(centered, centered);
    centered = centered * (1.0 + curvature * dist_sq);
    return centered * 0.5 + 0.5;
}

fn inverse_curve_uv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
    var centered = uv * 2.0 - 1.0;
    let dist_sq = dot(centered, centered);
    centered = centered / (1.0 + curvature * dist_sq * 0.8);
    return centered * 0.5 + 0.5;
}

fn aperture_grille(uv: vec2<f32>, resolution: vec2<f32>) -> vec3<f32> {
    let pixel_x = uv.x * resolution.x;
    let subpixel = fract(pixel_x / 3.0) * 3.0;
    var mask = vec3<f32>(0.0);
    let slot_width = 0.85;
    if (subpixel < slot_width) { mask.r = 1.0; }
    else if (subpixel < 1.0 + slot_width) { mask.g = 1.0; }
    else if (subpixel < 2.0 + slot_width) { mask.b = 1.0; }
    return mask;
}

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

fn halation_glow(uv: vec2<f32>, base_color: vec3<f32>, strength: f32, curvature: f32, resolution: vec2<f32>) -> vec3<f32> {
    if (strength < 0.01) { return vec3<f32>(0.0); }
    let inv_res = 1.0 / resolution;
    var glow = vec3<f32>(0.0);
    var total_weight = 0.0;
    let offsets = array<vec2<f32>, 5>(
        vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0) * inv_res * 2.0, vec2<f32>(-1.0, 0.0) * inv_res * 2.0,
        vec2<f32>(0.0, 1.0) * inv_res * 2.0, vec2<f32>(0.0, -1.0) * inv_res * 2.0
    );
    let weights = array<f32, 5>(0.4, 0.15, 0.15, 0.15, 0.15);
    for (var i = 0; i < 5; i = i + 1) {
        let sample_uv = uv + offsets[i];
        let flat_sample_uv = inverse_curve_uv(sample_uv, curvature);
        if (flat_sample_uv.x >= 0.0 && flat_sample_uv.x <= 1.0 && flat_sample_uv.y >= 0.0 && flat_sample_uv.y <= 1.0) {
            let sample = textureSampleLevel(readTexture, u_sampler, flat_sample_uv, 0.0).rgb;
            let brightness = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            let bright_contrib = smoothstep(0.3, 0.8, brightness) * sample;
            glow += bright_contrib * weights[i];
            total_weight += weights[i];
        }
    }
    if (total_weight > 0.0) { glow /= total_weight; }
    glow = glow * vec3<f32>(1.1, 0.95, 0.9);
    return glow * strength * 2.0;
}

fn scanlines(uv: vec2<f32>, resolution: vec2<f32>, intensity: f32, time: f32, audio_jitter: f32) -> f32 {
    let scan_freq = resolution.y * 0.5;
    let scan_y = uv.y * scan_freq;
    let scanline_phase = fract(scan_y) * 6.28318530718;
    let scan_profile = 0.5 + 0.5 * cos(scanline_phase);
    let phosphor_bright = smoothstep(0.0, 0.3, fract(scan_y)) * smoothstep(1.0, 0.7, fract(scan_y));
    let jitter = sin(time * 10.0 + uv.y * 100.0) * 0.02 * (1.0 + audio_jitter * 5.0);
    let thickness = 0.85 + jitter;
    let scan_darken = 1.0 - intensity * 0.4 * (1.0 - smoothstep(thickness, 1.0, scan_profile));
    let scan_boost = 1.0 + intensity * 0.15 * phosphor_bright;
    return scan_darken * scan_boost;
}

fn chromatic_aberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(strength, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(strength, 0.0), 0.0).b;
    return vec3<f32>(r, g, b);
}

fn crt_vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let centered = uv * 2.0 - 1.0;
    let dist = length(centered);
    let vig = 1.0 - smoothstep(0.6, 1.4, dist * (0.8 + strength * 0.4));
    let corner = abs(centered.x * centered.y);
    let corner_darken = 1.0 - corner * 0.15 * strength;
    return vig * corner_darken;
}

fn film_grain(uv: vec2<f32>, time: f32) -> f32 {
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    return 0.95 + noise * 0.05;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    let scanline_intensity = u.zoom_params.x;
    let phosphor_glow = u.zoom_params.y;
    let halation_strength = u.zoom_params.z + treble * 0.5;
    let barrel_amount = u.zoom_params.w;
    
    // Audio Reactive CRT Bulge
    let curvature = barrel_amount * 0.15 * (1.0 + bass * 0.5);
    let flicker_amount = 0.5 + barrel_amount * 0.5 + mids * 0.2;
    let chromatic_str = 0.002 * barrel_amount + treble * 0.005;
    
    var crt_uv = uv;
    if (barrel_amount > 0.01) {
        crt_uv = curve_uv(uv, curvature);
    }
    
    if (crt_uv.x < 0.0 || crt_uv.x > 1.0 || crt_uv.y < 0.0 || crt_uv.y > 1.0) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }
    
    var color = chromatic_aberration(crt_uv, chromatic_str);
    let mask = aperture_grille(crt_uv, resolution);
    color = color * mask;
    
    let scan_mod = scanlines(crt_uv, resolution, scanline_intensity, time, mids);
    color = color * scan_mod;
    
    let halation = halation_glow(crt_uv, color, halation_strength, curvature, resolution);
    color = color + halation;
    
    if (phosphor_glow > 0.01) {
        let brightness = dot(color, vec3<f32>(0.299, 0.587, 0.114));
        let bloom = smoothstep(0.4, 0.9, brightness) * phosphor_glow * 0.4;
        color = mix(color, pow(color, vec3<f32>(0.7)), phosphor_glow * 0.3);
        color = color + color * bloom;
    }
    
    color = phosphor_decay(color, time, flicker_amount);
    
    let vignette = crt_vignette(uv, 0.5 + barrel_amount * 0.5);
    color = color * vignette;
    let grain = film_grain(uv, time);
    color = color * grain;
    
    let warm_tint = vec3<f32>(1.05, 1.02, 0.98);
    color = color * warm_tint;
    let gamma = 1.0 / 2.2;
    color = pow(color, vec3<f32>(gamma));
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
