// ═══════════════════════════════════════════════════════════════════
//  Focal Pixelate
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, domain-warp, depth-aware, upgraded-rgba
//  Complexity: Low
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

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + t * 0.1, 3), fbm(p + vec2<f32>(5.2, 1.3) - t * 0.08, 3));
    return p + strength * q;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / res;
    let mouse = u.zoom_config.yz;
    let aspect = res.x / res.y;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
    let d = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(d);
    let focus = smoothstep(p2, p2 + p3 + 0.001, dist);
    let invert = step(0.5, p4);
    let mix_factor = select(focus, 1.0 - focus, invert > 0.5);
    let base_blocks = mix(500.0, 20.0, p1) * (1.0 - bass * 0.3);
    let blocks = max(mix(2000.0, base_blocks, mix_factor), 1.0);
    let warp = domainWarp(uv * 8.0, 0.02 * mix_factor * (1.0 + bass), u.config.x);
    let sample_uv = clamp(floor((uv + warp * mix_factor) * blocks) / blocks + (0.5 / blocks), vec2<f32>(0.001), vec2<f32>(0.999));
    let color = textureSampleLevel(readTexture, non_filtering_sampler, sample_uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sample_uv, 0.0).r;
    let fog = exp(-depth * (1.5 + mix_factor));
    let tone = aces(color * (1.0 + treble * 0.15 + bass * 0.05) * fog);
    let alpha = clamp(0.2 + mix_factor * 0.35 + treble * 0.08, 0.08, 0.9);
    let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tone + dither, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(clamp(depth + mix_factor * 0.03, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mix_factor, 1.0 / blocks, bass, alpha));
}
