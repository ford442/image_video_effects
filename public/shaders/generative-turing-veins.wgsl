// ═══════════════════════════════════════════════════════════════
// Generative Turing Veins - PASS 1 of 1
// Multiscale reaction-diffusion Turing patterns generating organic
// vein/network structures with bioluminescent glow. Evolves procedurally
// over time with depth-modulated complexity. Blends with input image.
// Upgraded: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
    var n = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    return fract(sin(n * 43758.5453) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 1.0;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

fn turing_pattern(uv: vec2<f32>, time: f32, scale: f32, feed: f32) -> vec2<f32> {
    var p = uv * scale;
    let activator = fbm(p + vec2(time * 0.1, 0.0), 6);
    let inhibitor = fbm(p * 0.5 + vec2(0.0, time * 0.05), 4);
    let reaction = activator * inhibitor * (feed + 0.5);
    let diffusion_a = (fbm(p * 1.2, 5) - 0.5) * 0.1;
    let diffusion_i = (fbm(p * 0.6, 4) - 0.5) * 0.2;
    return vec2(activator + diffusion_a + reaction * 0.1, inhibitor + diffusion_i - reaction * 0.05);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let params = u.zoom_params;
    var mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let complexity = mix(1.0, 3.0, depth);

    // Audio-driven feed rate modulation
    let scale1 = params.x * complexity + 1.0;
    let scale2 = params.y * complexity * 0.5 + 0.5;
    let feed_rate = params.z * 0.5 + 0.5 + bass * 0.1 * sin(time * 0.3);

    var pattern1 = turing_pattern(uv * scale1 + mouse * 0.1, time, scale1, feed_rate);
    var pattern2 = turing_pattern(uv * scale2 + vec2(time * 0.05), time * 0.7, scale2, feed_rate * 0.8);

    let veins = (pattern1.x * pattern2.y + pattern1.y * pattern2.x) * 2.0;
    let vein_mask = smoothstep(0.4, 0.6, veins) * (1.0 - smoothstep(0.7, 1.0, abs(veins - 0.5) * 2.0));

    // Chromatic activator/inhibitor separation
    let actColor = vec3<f32>(0.2, 0.9, 0.5) * pattern1.x * (1.0 + treble * 0.3);
    let inhColor = vec3<f32>(0.9, 0.3, 0.6) * pattern2.y * (1.0 + mids * 0.3);
    let vein_hue = fract(veins * 0.3 + time * 0.1 + pattern1.y * 0.5);
    let vein_sat = 0.8 + 0.2 * sin(time * 2.0);
    let vein_val = pow(vein_mask, 0.5) * (params.w + 0.5);
    let vein_color = mix(vec3(vein_hue, vein_sat, vein_val), actColor + inhColor, 0.3 + bass * 0.2);

    let src_color = textureSampleLevel(readTexture, u_sampler, uv + (veins - 0.5) * 0.01 * depth, 0.0);
    var final_color = mix(src_color.rgb, vein_color, vein_mask * 0.7);

    let glow = vein_mask * vein_val * 2.0;
    var final_rgb = final_color + glow * vec3(0.2, 0.4, 0.6);

    // Temporal pattern memory: previous veins blend for organic evolution
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    final_rgb = mix(final_rgb, prev * 0.9, 0.05 + bass * 0.02);

    let alpha = clamp(0.5 + vein_mask * 0.5 + glow * 0.2, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(final_rgb, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4(final_rgb, alpha));

    let mod_depth = depth * (1.0 + vein_mask * 0.3);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(mod_depth, 0.0, 0.0, 0.0));
}
