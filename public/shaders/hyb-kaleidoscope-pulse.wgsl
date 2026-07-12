// ═══════════════════════════════════════════════════════════════════
//  hyb-kaleidoscope-pulse
//  Category: hybrid
//  Features: kaleidoscope, radial-pulse, image-remix, upgraded-rgba,
//            depth-aware, aces-tone-map, domain-warp, ign-dither
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    let f = fract(p * vec2<f32>(0.06711056, 0.00583715));
    return fract(f.x * f.y * 52.9829189);
}
fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x);
    let seg = TAU / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}
fn rdPulse(p: vec2<f32>, t: f32, speed: f32, width: f32) -> f32 {
    let d = length(p);
    let phase = d * 8.0 - t * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    let glow = exp(-d * d / (max(width, 0.001) * max(width, 0.001)));
    return wave * envelope * glow;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    if (any(coord >= vec2<i32>(dims))) { return; }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let time = u.config.x;
    let segments = mix(3.0, 16.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let pulseSpeed = mix(0.2, 3.0, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulseWidth = mix(0.05, 0.6, clamp(u.zoom_params.z, 0.0, 1.0));
    let effectMix = clamp(u.zoom_params.w, 0.0, 1.0);

    let centered = uv - 0.5;
    let warpStr = 0.06 + effectMix * 0.14;
    let warp = vec2<f32>(fbm(centered * 6.0 + time * 0.2, 3),
                         fbm(centered * 6.0 + vec2<f32>(5.2, 1.3) - time * 0.15, 3)) * warpStr;
    let kUV = kaleido(centered + warp, segments);
    let sampleUV = clamp(kUV + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let kaleido = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    let pulse = rdPulse(centered, time, pulseSpeed, pulseWidth);
    let pulseColor = pulse * vec3<f32>(0.5, 0.85, 1.0);

    var outRGB = mix(kaleido.rgb, kaleido.rgb + pulseColor, effectMix);
    outRGB = acesToneMap(outRGB * (1.0 + pulse * 0.35));

    let luma = dot(outRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = mix(src.a, clamp(luma * 0.7 + pulse * 0.45 + depth * 0.15, 0.0, 1.0), effectMix);
    let dither = (ign(vec2<f32>(coord)) - 0.5) / 255.0;
    outRGB = outRGB + vec3<f32>(dither);

    textureStore(writeTexture, coord, vec4<f32>(outRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
