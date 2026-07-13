// ═══════════════════════════════════════════════════════════════════
//  hyb-iridescent-fbm-glow
//  Category: hybrid
//  Features: upgraded-rgba, fbm-noise, iridescence, image-glow,
//            domain-warp, audio-reactive, aces-tone-map, ign-dither,
//            depth-aware, chromatic-aberration, fresnel-rim, oklab-mix
//  Complexity: Medium
//  Upgraded: 2026-07-12 (retry)
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 { var s = 0.0; var a = 0.5; var f = 1.0; for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; } return s; }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829181 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn iridescence(theta: f32, shift: f32) -> vec3<f32> { let t = theta * 4.0 + shift; return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189)); }

// Approximate sRGB -> OkLab conversion for perceptually even colour mixing.
fn srgbToOkLab(c: vec3<f32>) -> vec3<f32> {
    var lms = vec3<f32>(
        dot(c, vec3<f32>(0.8189330101, 0.3618667424, -0.1288597137)),
        dot(c, vec3<f32>(0.0329845436, 0.9293118715, 0.0361456387)),
        dot(c, vec3<f32>(0.0482003018, 0.2643662691, 0.6338517070))
    );
    lms = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
    return vec3<f32>(
        dot(lms, vec3<f32>(0.2104542553, 0.7936177850, -0.0040720468)),
        dot(lms, vec3<f32>(1.9779984951, -2.4285922050, 0.4505937099)),
        dot(lms, vec3<f32>(0.0259040371, 0.7827717662, -0.8086757660))
    );
}

// Approximate OkLab -> sRGB conversion.
fn okLabToSrgb(c: vec3<f32>) -> vec3<f32> {
    var lms = vec3<f32>(
        dot(c, vec3<f32>(1.0, 0.3963377774, 0.2158037573)),
        dot(c, vec3<f32>(1.0, -0.1055613458, -0.0638541728)),
        dot(c, vec3<f32>(1.0, -0.0894841775, -1.2914855480))
    );
    lms = lms * lms * lms;
    return vec3<f32>(
        dot(lms, vec3<f32>(1.2270138510, -0.5577992887, 0.2812561490)),
        dot(lms, vec3<f32>(-0.0405801784, 1.1122568696, -0.0716766787)),
        dot(lms, vec3<f32>(-0.0763812845, -0.4214819784, 1.5861632204))
    );
}

fn oklabMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return okLabToSrgb(mix(srgbToOkLab(a), srgbToOkLab(b), t));
}

// Directional RGB split pulled from bright areas of the source image.
fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let offset = dir * amount;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

// Fresnel rim that adds a thin-film edge glow around the viewport.
fn fresnelRim(uv: vec2<f32>, bias: f32, power: f32) -> f32 {
    let d = distance(uv, vec2<f32>(0.5));
    let f = 1.0 - pow(clamp(d * 2.0, 0.0, 1.0), power);
    return bias + (1.0 - bias) * f;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let fbmScale = mix(1.5, 18.0, p1);
    let octaves = i32(mix(2.0, 7.0, p2));
    let shiftSpeed = mix(0.0, 3.0, p3);
    let glowMix = p4;

    let q = vec2<f32>(
        fbm(uv * fbmScale + vec2<f32>(time * 0.07 * (1.0 + bass * 0.3), 0.0), octaves),
        fbm(uv * fbmScale + vec2<f32>(5.2, 1.3 + time * 0.07), octaves)
    );
    let warped = uv * fbmScale + 4.0 * q + vec2<f32>(time * 0.05);
    let noise = fbm(warped, octaves);
    let ird = iridescence(noise, time * shiftSpeed);
    let glowLayer = ird * noise * noise;

    // Layer the new upgrades over the original FBM glow.
    let brightness = smoothstep(0.25, 0.85, luma(src.rgb) + noise);
    let ca = chromaticAberration(uv, 0.003 * brightness);
    let rim = fresnelRim(uv, 0.06, 2.0) * ird * 0.35;

    let depthFog = exp(-depth * 2.0);
    let glow = glowLayer * glowMix * (1.0 + bass * 0.5) * depthFog;
    var outRGB = oklabMix(ca, ca + glow + rim, glowMix);
    outRGB = acesToneMap(outRGB);
    outRGB += (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;

    let energy = length(glow) * 0.5;
    let alpha = clamp(src.a + energy * (1.0 - depth * 0.3), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(outRGB, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(outRGB, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
