// ═══════════════════════════════════════════════════════════════════
//  gen_grok4_perlin - Perlin noise terrain generator
//  Category: generator
//  Features: upgraded-rgba, depth-aware
//  Upgraded: 2026-03-22
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

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var n = sin(dot(p, vec3<f32>(127.1, 311.7, 74.7)));
    return fract(vec3<f32>(n, n * 1.618, n * 3.14159));
}

fn permute(x: vec3<f32>) -> vec3<f32> {
    return ((x * 34.0) + 1.0) * x % 289.0;
}

fn noise(p: vec3<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(
            mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution * 10.0;
    let time = u.config.x * 0.1;
    var mouse = vec2<f32>(u.zoom_config.y * 10.0, (1.0 - u.zoom_config.z) * 10.0);

    // Multi-octave Perlin noise
    var n = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 5; i++) {
        n += amp * noise(vec3<f32>(uv * freq + mouse * 0.2, time * 0.5));
        amp *= 0.5;
        freq *= 2.0;
    }
    n = (n + 1.0) * 0.5;

    // Color as terrain: blue water, green land, white peaks
    var generatedColor: vec3<f32>;
    if (n < 0.3) {
        generatedColor = vec3<f32>(0.1, 0.2, 0.6) * (n / 0.3);
    } else if (n < 0.7) {
        generatedColor = vec3<f32>(0.2, 0.6, 0.3) * ((n - 0.3) / 0.4 + 0.6);
    } else {
        generatedColor = vec3<f32>(1.0, 1.0, 1.0) * ((n - 0.7) / 0.3 + 0.8);
    }

    // Sample input and depth
    let uv_norm = vec2<f32>(global_id.xy) / resolution;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv_norm, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_norm, 0.0).r;
    
    // Opacity control
    let opacity = 0.85;
    
    // Calculate alpha based on noise value and luminance
    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let generatedAlpha = mix(0.7, 1.0, luma * n);
    
    // Blend with input
    let finalColor = mix(inputColor.rgb, generatedColor, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
