// ═══════════════════════════════════════════════════════════════════
//  Rorschach Inkblot
//  Category: image
//  Features: audio-reactive, temporal-ink-diffusion, chromatic-ink-tints,
//            mouse-symmetry-axis, upgraded-rgba, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-05-31
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pp);
        pp = rot * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    var mouse = u.zoom_config.yz;

    let threshold = u.zoom_params.x;
    let distStr = u.zoom_params.y * 0.5 * (1.0 + bass * 0.3);
    let smoothness = u.zoom_params.z * 0.2;
    let invert = u.zoom_params.w;

    // Audio-driven symmetry axis drift
    var center = mouse.x + bass * 0.02 * sin(time);
    if (mouse.x == 0.0) { center = 0.5; }

    var sym_uv = uv;
    sym_uv.x = center - abs(uv.x - center);

    // Temporal ink diffusion: previous ink state bleeds in
    let prev = textureSampleLevel(dataTextureC, u_sampler, sym_uv, 0.0);
    let prevInk = prev.r;

    // FBM distortion with audio reactivity
    let noise_uv = sym_uv * 3.0 + vec2<f32>(0.0, time * 0.2 * (1.0 + mids * 0.3));
    let n = fbm(noise_uv);
    let displace = (n - 0.5) * distStr;
    let sample_uv = sym_uv + vec2<f32>(displace);

    // Chromatic ink tints: R from left, G from center, B from right
    let rUV = clamp(sample_uv + vec2<f32>(treble * 0.01, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sample_uv - vec2<f32>(treble * 0.01, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let color = vec3<f32>(colR, colG, colB);

    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Ink threshold with temporal accumulation
    var paper = smoothstep(threshold - smoothness, threshold + smoothness, luma);
    paper = mix(paper, prevInk, 0.03 + bass * 0.01);

    let grain = hash(uv * 100.0 + time) * 0.05;
    paper = clamp(paper - grain, 0.0, 1.0);

    var finalColor = vec3<f32>(paper);

    if (invert > 0.5) {
        finalColor = 1.0 - finalColor;
        // Chromatic ink tint: bass = warm, treble = cool
        let warmTint = vec3<f32>(0.9, 0.7, 0.5) * (1.0 + bass * 0.3);
        let coolTint = vec3<f32>(0.5, 0.7, 0.9) * (1.0 + treble * 0.3);
        finalColor *= mix(coolTint, warmTint, mids);
    }

    // Depth-aware ink density
    let depthInk = mix(1.0, 0.7, depth * 0.3);
    finalColor *= depthInk;

    let alpha = clamp(paper * (0.8 + bass * 0.1) + (1.0 - paper) * 0.3, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
