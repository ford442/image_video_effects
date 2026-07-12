// ═══════════════════════════════════════════════════════════════════
//  Temporal Halation Freeze
//  Category: post-processing
//  Features: halation, bloom, temporal, ghost, audio-envelope, hex-bokeh, upgraded-rgba
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

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
);
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let bassTarget = bass;
    return select(prev * release + bassTarget * (1.0 - release), prev * attack + bassTarget * (1.0 - attack), bassTarget > prev);
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
    let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
    let exposure = p1 * (0.6 + bass * 0.7);
    let decay = p2 * 0.92 + 0.06;
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let bloomRadius = (0.004 + exposure * 0.009) / res;
    var halo = vec3<f32>(0.0);
    for (var i = 0; i < 7; i = i + 1) {
        let off = HEX_TAPS[i] * bloomRadius * 18.0;
        halo += textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    halo /= 7.0;
    let brightMask = smoothstep(0.45, 0.92, luma);
    let env = bass_env(prev.a, bass, 0.2, 0.95);
    let newHalo = halo * brightMask * exposure * 0.85;
    let accumulated = prev.rgb * decay + newHalo * (0.6 + env * 0.3);
    let ghost = prev.rgb * (p4 * 0.45) * (0.7 + treble * 0.4);
    let warm = mix(vec3<f32>(1.0, 0.75, 0.45), vec3<f32>(0.6, 0.85, 1.0), p3);
    let bloomCol = accumulated * warm;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = exp(-depth * 0.8);
    var col = input.rgb * (1.0 - brightMask * 0.15) + bloomCol * 1.1 + ghost * 0.6;
    col = 1.0 - exp(-col * 1.05);
    col = aces(col * fog) * fog;
    let energy = length(accumulated) * 0.8 + length(ghost) * 0.5;
    let semantic_alpha = clamp(0.58 + energy * 0.55, 0.45, 1.0);
    let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
    textureStore(writeTexture, global_id.xy, vec4<f32>(col + dither, semantic_alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(accumulated, env));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(clamp(0.18 + energy * 0.45, 0.0, 0.93), 0.0, 0.0, 0.0));
}
