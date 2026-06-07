// ═══════════════════════════════════════════════════════════════════
//  Luminous-Fluid Chladni-Resonator
//  Category: generative
//  Features: audio-reactive, Chladni, curl-fluid, Voronoi, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Created: 2026-05-09
//  Upgraded: 2026-06-06
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var q = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 5; i++) { v += a * noise(q); q = rot * q * 2.0 + vec2<f32>(100.0); a *= 0.5; }
    return v;
}
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let e = 0.01; let nx = fbm(p + vec2<f32>(0.0, e)) - fbm(p - vec2<f32>(0.0, e)); let ny = fbm(p + vec2<f32>(e, 0.0)) - fbm(p - vec2<f32>(e, 0.0));
    return vec2<f32>(nx, -ny) / (2.0 * e);
}
fn voronoiRidge(p: vec2<f32>) -> f32 {
    let ip = floor(p); let fp = fract(p); var F1 = 1e9; var F2 = 1e9;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let n = vec2<f32>(f32(i), f32(j));
            let d = length(n + vec2<f32>(hash21(ip + n), hash21(ip + n + 17.0)) - fp);
            let updateF1 = step(d, F1);
            let oldF1 = F1;
            F1 = mix(F1, d, updateF1);
            F2 = mix(F2, oldF1, updateF1);
            let updateF2 = step(d, F2) * (1.0 - updateF1);
            F2 = mix(F2, d, updateF2);
        }
    }
    return F2 - F1;
}
fn chladni_multi(uv: vec2<f32>, n: f32, m: f32, t: f32) -> f32 {
    let a1 = sin(n * PI * uv.x) * sin(m * PI * uv.y); let a2 = sin(m * PI * uv.x) * sin(n * PI * uv.y);
    let b1 = sin((n + 1.0) * PI * uv.x) * sin((m + 1.0) * PI * uv.y); let b2 = sin((m + 1.0) * PI * uv.x) * sin((n + 1.0) * PI * uv.y);
    return cos(t) * a1 + sin(t) * a2 + (cos(t * PHI) * b1 + sin(t * PHI) * b2) * 0.4;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) * 0.01;
    var r = select(clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0), 1.0, t <= 66.0);
    var g = select(clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0), clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0), t <= 66.0);
    var b = select(select(clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0), 1.0, t >= 66.0);
    return vec3<f32>(r, g, b);
}
fn srgb2oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = pow(vec3<f32>(dot(c,vec3<f32>(0.4122,0.5363,0.0514)),dot(c,vec3<f32>(0.2119,0.6807,0.1074)),dot(c,vec3<f32>(0.0883,0.2817,0.6300))),vec3<f32>(1.0/3.0));
    return vec3<f32>(dot(lms,vec3<f32>(0.2105,0.7936,-0.0041)),dot(lms,vec3<f32>(1.9780,-2.4286,0.4506)),dot(lms,vec3<f32>(0.0259,0.7828,-0.8087)));
}
fn oklab2srgb(c: vec3<f32>) -> vec3<f32> {
    let lms = pow(c.x+c.y*vec3<f32>(0.3963,-0.1056,-0.0895)+c.z*vec3<f32>(0.2158,-0.0639,-1.2915),vec3<f32>(3.0));
    return vec3<f32>(dot(lms,vec3<f32>(4.0767,-1.2684,-0.0042)),dot(lms,vec3<f32>(-3.3077,2.6098,-0.7034)),dot(lms,vec3<f32>(0.2310,-0.3413,1.7076)));
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab2srgb(mix(srgb2oklab(a), srgb2oklab(b), t));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / res;
    let t = u.config.x * 0.5;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let param_n = u.zoom_params.x;
    let param_m = u.zoom_params.y;
    let param_fluid = u.zoom_params.z;
    let param_glow = u.zoom_params.w;

    let velocity = curl2D(uv * 5.0 + vec2<f32>(t * 0.3));
    let uv_dist = uv + velocity * param_fluid * 0.05 * (1.0 + bass * 0.5 + mids * 0.3);
    let n = param_n + bass * 2.0 * sin(t);
    let m = param_m + bass * 2.0 * cos(t * PHI);
    let c_val = chladni_multi(uv_dist * 2.0 - vec2<f32>(1.0), n, m, t * 2.0);
    let ridge = 1.0 - smoothstep(0.0, 0.18, voronoiRidge(uv * 8.0 + velocity * 0.2));
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let d_mouse = distance(uv, mouse_uv);
    let damp = smoothstep(0.0, 0.2, d_mouse);
    let depthAttn = exp(-d_mouse * 1.5);
    let final_val = abs(c_val) * damp + ridge * 0.35 * depthAttn;
    let prior = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let settled = mix(prior, final_val, 0.35);
    let intensity = smoothstep(0.18, 0.0, settled) * param_glow * (1.0 + bass + treble * 0.3);
    let warm = blackbodyRGB(3500.0 + bass * 3000.0 + sin(t * 0.7) * 1000.0) * intensity * 3.0;
    let cool = blackbodyRGB(8500.0 + cos(t * 0.4) * 2000.0) * (intensity * 0.6 + ridge * 0.8);
    let hdr = mixOkLab(warm, cool, ridge * 0.5 + 0.25) * (1.0 + intensity);
    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(intensity * 0.7 + luma * 0.25 + ridge * 0.15, 0.0, 1.0);
    let mapped = aces(hdr) + vec3<f32>((ign(vec2<f32>(coord)) - 0.5) / 255.0);
    let gamma = pow(mapped, vec3<f32>(1.0 / 2.2));
    let finalColor = vec4<f32>(acesToneMap((gamma * alpha) * 1.1), alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
