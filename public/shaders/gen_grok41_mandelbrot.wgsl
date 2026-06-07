// ═══════════════════════════════════════════════════════════════════
//  Buddhabrot Nebula v2 - Audio-reactive orbit accumulation
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            temporal, procedural, animated-accumulation
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Creative additions: bass-breathing sample count, orbital rainbow trails
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(p2) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let p3 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(p3) * 43758.5453);
}

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn escapes(c: vec2<f32>, max_iter: u32) -> bool {
    var z = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < max_iter; i = i + 1u) {
        z = cmul(z, z) + c;
        if (dot(z, z) > 4.0) { return true; }
    }
    return false;
}

fn random_c(seed: vec3<f32>, view_center: vec2<f32>, view_scale: f32) -> vec2<f32> {
    let rnd = hash3(seed);
    return view_center + (rnd.xy - 0.5) * view_scale * 3.0;
}

fn nebula_color(density: f32, time: f32, hueShift: f32) -> vec3<f32> {
    let d = clamp(density * 0.5, 0.0, 1.0);
    let t = time * 0.1;

    let deep_purple = vec3<f32>(0.1, 0.05, 0.2);
    let cosmic_blue = vec3<f32>(0.05, 0.15, 0.35);
    let nebula_cyan = vec3<f32>(0.1, 0.4, 0.5);
    let ethereal_pink = vec3<f32>(0.6, 0.3, 0.5);
    let stellar_gold = vec3<f32>(0.9, 0.7, 0.3);
    let white_core = vec3<f32>(1.0, 0.95, 0.9);

    var color = deep_purple;
    color = mix(color, cosmic_blue, smoothstep(0.05, 0.15, d));
    color = mix(color, nebula_cyan, smoothstep(0.1, 0.25, d) * (0.8 + 0.2 * sin(t + d * 5.0 + hueShift * 6.28)));
    color = mix(color, ethereal_pink, smoothstep(0.15, 0.35, d) * (0.6 + 0.4 * cos(t * 0.7 + d * 3.0 + hueShift * 6.28)));
    color = mix(color, stellar_gold, smoothstep(0.3, 0.6, d) * (0.5 + 0.5 * sin(t * 0.5 + hueShift * 6.28)));
    color = mix(color, white_core, smoothstep(0.5, 1.0, d));
    color = color * (0.9 + 0.1 * sin(d * 10.0 + t));

    let glow = pow(d, 2.0) * 0.5;
    color = color + vec3<f32>(glow * 0.5, glow * 0.6, glow * 0.8);
    return color;
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
    let coord = vec2<i32>(global_id.xy);
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-specific params: Center X, Center Y, Zoom Scale, Evolution Speed
    let centerX = mix(-2.0, 1.0, u.zoom_params.x);
    let centerY = mix(-1.5, 1.5, u.zoom_params.y);
    var view_center = vec2<f32>(centerX, centerY);
    var view_scale = mix(0.05, 2.5, u.zoom_params.z) / max(1.0 + bass * 0.6, 0.0001); // bass zooms
    let evolution_speed = mix(0.05, 1.5, u.zoom_params.w);

    // Mouse-driven panning when mouse-down
    let mouseDown = u.zoom_config.w > 0.5;
    if (mouseDown) {
        let mouseUV = (u.zoom_config.yz - 0.5) * 2.0;
        view_center = view_center + vec2<f32>(mouseUV.x * aspect, mouseUV.y) * view_scale * 0.5;
    }

    let t = time * evolution_speed * 0.1 * (1.0 + bass * 0.5);
    let c_pixel = view_center + vec2<f32>(uv.x * aspect, uv.y) * view_scale;

    // Sample count breathes with bass (16..40)
    let sample_count: u32 = 16u + u32(round(bass * 24.0));
    var density: f32 = 0.0;
    var rainbow: vec3<f32> = vec3<f32>(0.0);
    let pixel_seed = vec2<f32>(f32(global_id.x), f32(global_id.y));

    for (var s: u32 = 0u; s < 40u; s = s + 1u) {
        if (s >= sample_count) { break; }
        let seed = vec3<f32>(pixel_seed, f32(s) + t * 100.0);
        let c_rand = random_c(seed, view_center, view_scale);

        if (escapes(c_rand, 64u)) {
            var z = vec2<f32>(0.0);
            var orbit_points: array<vec2<f32>, 64>;
            var orbit_len: u32 = 0u;

            for (var i: u32 = 0u; i < 64u; i = i + 1u) {
                if (orbit_len >= 64u) { break; }
                z = cmul(z, z) + c_rand;
                if (dot(z, z) > 4.0) { break; }
                orbit_points[orbit_len] = z;
                orbit_len = orbit_len + 1u;
            }

            for (var i: u32 = 0u; i < orbit_len; i = i + 1u) {
                let orbit_p = orbit_points[i];
                let dist = length(orbit_p - c_pixel);
                let contribution = 1.0 / (1.0 + dist * dist * 1000.0 * view_scale);
                density = density + contribution;

                // ─── Creative: orbital rainbow — each orbit step gets a hue ───
                let orbitT = f32(i) / max(f32(orbit_len), 1.0);
                let hue = orbitT * 6.28;
                let band = vec3<f32>(
                    0.5 + 0.5 * cos(hue),
                    0.5 + 0.5 * cos(hue + 2.094),
                    0.5 + 0.5 * cos(hue + 4.188)
                );
                rainbow = rainbow + band * contribution;
            }
        }
    }

    let evolution = sin(t + length(c_pixel) * 3.0) * 0.1 + 1.0;
    density = density * evolution / f32(sample_count);
    density = density * 50.0;
    density = density / (1.0 + density);

    rainbow = rainbow / max(f32(sample_count) * 8.0, 1.0);

    // Mids drive nebula palette hue shift
    var color = nebula_color(density, t, mids * 0.5);
    color = color + rainbow * 0.6;

    // Treble: sparkle stars
    let star_noise = hash3(vec3<f32>(pixel_seed * 0.01, t * 0.01));
    let starThresh = 0.998 - treble * 0.005;
    if (star_noise.x > starThresh) {
        let star_brightness = hash2(pixel_seed + vec2<f32>(t)).x;
        color = mix(color, vec3<f32>(1.0), star_brightness * 0.8);
    }

    // Vignette
    let vignette = 1.0 - length(uv) * 0.3;
    color = color * vignette;

    // Temporal accumulation: blend with previous frame from dataTextureC
    // Param4 doubles as history blend (high evolution_speed → less persistence)
    let uv_norm = vec2<f32>(global_id.xy) / resolution;
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv_norm, 0.0).rgb;
    let historyBlend = clamp(0.85 - u.zoom_params.w * 0.5, 0.0, 0.85);
    color = mix(color, prev, historyBlend);

    // ACES tone mapping (replaces pow(color, 0.8))
    color = acesToneMapping(color);

    // Sample input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv_norm, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_norm, 0.0).r;

    let opacity = 0.9;
    let presence = smoothstep(0.05, 0.2, density);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let generatedAlpha = max(presence, smoothstep(0.04, 0.4, luma));

    let finalColor = mix(inputColor.rgb, color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));

    let finalDepth = mix(inputDepth, density, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));

    // Persist accumulated nebula for temporal feedback
    textureStore(dataTextureA, coord, vec4<f32>(color, generatedAlpha));
}
