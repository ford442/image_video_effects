// ═══════════════════════════════════════════════════════════════
//  Radial Hex Lens
//  Category: interactive-mouse
//  Features: mouse-driven, hexagonal, depth-aware, lod-bias, upgraded-rgba
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

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
);
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
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
fn getHexCenter(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let spacing = vec2<f32>(scale, scale * r.y);
    let a = (fract(uv / spacing) - 0.5) * spacing;
    let b = (fract((uv - spacing * 0.5) / spacing) - 0.5) * spacing;
    return select(uv - b, uv - a, dot(a, a) < dot(b, b));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let mouse = u.zoom_config.yz;
    let mouseA = vec2<f32>(mouse.x * aspect, mouse.y);
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;
    let uvA = uv * vec2<f32>(aspect, 1.0);
    let offset = uvA - mouseA;
    let dist = length(offset);
    let radius = p2 * 1.5;
    let falloff = smoothstep(radius, 0.0, dist);
    let zoom = 1.0 - p3 * falloff * 0.5;
    let distorted = mouseA + offset * zoom;
    let hex_size = mix(0.01, 0.1, p1);
    let warp = fbm(distorted * 12.0 + u.config.x * 0.2, 3) * 0.02 * falloff * (1.0 + bass);
    let center = getHexCenter(distorted + vec2<f32>(warp), hex_size);
    let sample_uv = vec2<f32>(center.x / aspect, center.y);
    let cell_freq = 1.0 / hex_size;
    let lod = clamp(log2(length(vec2<f32>(1.0 / res.x, 1.0 / res.y)) * cell_freq), 0.0, 4.0);
    let color = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0)), lod).rgb;
    let dist_to_center = length(distorted - center);
    let hex_mask = smoothstep(hex_size * 0.5, mix(hex_size * 0.3, hex_size * 0.55, p4), dist_to_center);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = exp(-depth * (1.0 + falloff));
    let tone = aces(color * hex_mask * fog * (1.0 + bass * 0.1));
    let alpha = clamp(hex_mask * (0.75 + falloff * 0.2), 0.0, 0.95);
    var blur = vec3<f32>(0.0); var wt = 0.0;
    for (var i = 0; i < 7; i = i + 1) {
        let off = HEX_TAPS[i] * hex_size * 0.5;
        blur += textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        wt += 1.0;
    }
    let final_col = mix(tone, blur / wt * fog, falloff * 0.3 * p3);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_col, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(falloff, hex_size, alpha, bass));
}
