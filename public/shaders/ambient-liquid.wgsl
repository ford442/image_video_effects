// ═══════════════════════════════════════════════════════════════════
//  Ambient Liquid
//  Category: artistic
//  Features: mouse-driven, liquid-distortion, upgraded-rgba,
//            curl-noise, depth-aware, aces-tone-map
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
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let mx = max(max(c.r, c.g), c.b);
    let mn = min(min(c.r, c.g), c.b);
    let d = mx - mn;
    var h = 0.0;
    if (d > 0.0) {
        if      (mx == c.r) { h = (c.g - c.b) / d + select(0.0, 6.0, c.g < c.b); }
        else if (mx == c.g) { h = (c.b - c.r) / d + 2.0; }
        else                { h = (c.r - c.g) / d + 4.0; }
        h /= 6.0;
    }
    return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    let m = hsv.z - c;
    var rgb: vec3<f32>;
    if      (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let flow = curl2D(uv * mix(4.0, 14.0, p2), time * 0.12);
    let mouse = u.zoom_config.yz;
    let to_mouse = mouse - uv;
    let mouse_influence = exp(-length(to_mouse) * 5.0) * 0.02 * (1.0 - p1);
    var disp = flow * mix(0.01, 0.06, p1) + to_mouse * mouse_influence;

    for (var i = 0; i < 50; i = i + 1) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        let rippleMask = f32(ripple.z > 0.0 && age > 0.0 && age < 4.0);
        let to_ripple = uv - ripple.xy;
        let ripple_dist = length(to_ripple);
        let ripple_strength = sin(ripple_dist * 20.0 - age * 5.0) * exp(-age * 0.5) * 0.01 * rippleMask;
        disp += vec2<f32>(to_ripple.y, -to_ripple.x) * ripple_strength * p3;
    }

    let displacedUV = clamp(uv + disp, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let freq = mix(8.0, 24.0, p2);
    let strength = 0.015 * (1.0 - p1);
    let brightMask = smoothstep(0.65, 0.8, luma);
    let darkMask = 1.0 - smoothstep(0.2, 0.35, luma);
    let brightUV = clamp(uv + vec2<f32>(sin(uv.x * freq + time * 0.65), cos(uv.y * freq * 0.7 + time * 0.65)) * strength, vec2<f32>(0.0), vec2<f32>(1.0));
    let darkUV = clamp(uv + vec2<f32>(sin(uv.x * freq + time * 0.45), cos(uv.y * freq * 0.7 + time * 0.45)) * strength, vec2<f32>(0.0), vec2<f32>(1.0));
    color = mix(color, textureSampleLevel(readTexture, u_sampler, brightUV, 0.0), brightMask * 0.25);
    color = mix(color, textureSampleLevel(readTexture, u_sampler, darkUV, 0.0), darkMask * 0.75);

    var hsv = rgb2hsv(color.rgb);
    hsv.x = fract(hsv.x + p4 * 0.08 + length(disp) * 2.0);
    color = vec4<f32>(hsv2rgb(hsv), color.a);
    color = vec4<f32>(acesToneMap(color.rgb * (1.0 + p4 * 0.2)), color.a);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = clamp(dot(color.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.8 + depth * 0.2 + length(disp) * 8.0, 0.15, 0.95);

    textureStore(writeTexture, coord, vec4<f32>(color.rgb, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
