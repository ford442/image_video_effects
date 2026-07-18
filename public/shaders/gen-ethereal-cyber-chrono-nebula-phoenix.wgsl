// ═══ Ethereal Cyber-Chrono Nebula-Phoenix ═══════════════════════════════════
//  Category: generative
//  Features: SDF cyber-phoenix, domain-warped nebula, strange-attractor
//            chrono-glow, bass/mids/treble reactivity, ACES + IGN dither,
//            semantic alpha, depth-aware compositing
//  Complexity: Medium

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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Core math ───────────────────────────────────────────────────────────────
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
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
fn domainWarp(p: vec2<f32>, t: f32, strength: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + strength * q;
}

// ── Tone map & dither ───────────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// ── Chrono-orbit strange attractor ──────────────────────────────────────────
fn attractorTrap(p: vec2<f32>, t: f32, mids: f32) -> f32 {
    var z = p * 2.0;
    var trap = 100.0;
    let a = -1.4 + mids * 0.3;
    let b = 1.6 + sin(t * 0.2) * 0.1;
    let c = 1.0;
    let d = 0.7;
    let orbitTarget = vec2<f32>(0.4 * sin(t), 0.3 * cos(t));
    for (var i = 0; i < 24; i = i + 1) {
        let nx = sin(a * z.y) + c * cos(a * z.x);
        let ny = sin(b * z.x) + d * cos(b * z.y);
        z = vec2<f32>(nx, ny);
        trap = min(trap, length(z - orbitTarget));
    }
    return trap;
}

// ── SDF cyber-phoenix silhouette ────────────────────────────────────────────
fn sdPhoenix(p: vec2<f32>, wingspan: f32) -> f32 {
    let body = length(vec2<f32>(p.x * 4.0, max(0.0, abs(p.y) - 0.22))) - 0.06;
    let wingY = p.y - 0.12;
    let wingX = abs(p.x) - 0.06;
    let wingUV = rot(0.25 + wingspan * 2.0) * vec2<f32>(wingX, wingY);
    let wing = length(vec2<f32>(wingUV.x * 0.35 / wingspan, wingUV.y * 2.5)) - 0.12;
    let tailUV = vec2<f32>(p.x * 2.0, p.y + 0.35);
    let tail = length(vec2<f32>(tailUV.x, max(0.0, -tailUV.y))) - 0.1 + 0.08 * sin(p.y * 20.0);
    return min(min(body, wing), tail);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let wingspan = clamp(u.zoom_params.x, 0.05, 0.5);
    let plasma = u.zoom_params.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let inDepth = textureLoad(readDepthTexture, pixel, 0).r;

    // Bass-driven domain-warped nebula
    let warp = domainWarp(uv * 2.0 + vec2<f32>(time * 0.02), time * 0.05, 0.25 + bass * 0.15);
    var nebula = fbm(warp * 3.0, 5);
    nebula += 0.5 * fbm(warp * 6.0 + bass, 4);
    let bgColor = vec3<f32>(0.08, 0.05, 0.15) * nebula * (1.0 + bass * 2.0);

    // Mids-driven chrono-glow orbit trap
    let trap = attractorTrap(uv * 1.5, time, mids);
    let chronoGlow = exp(-trap * 6.0) * (0.5 + 0.5 * mids);

    // Phoenix SDF, treble-driven edge sparkle
    var p = uv;
    p = rot(mouse.x * 2.0 + time * 0.1) * p;
    let d = sdPhoenix(p, wingspan);
    let edge = abs(d);
    let density = smoothstep(0.12, 0.0, d);
    let shell = exp(-edge * 12.0) * (1.0 + treble);
    let sparkle = exp(-edge * 30.0) * treble * 1.5;

    // Deep purple / neon cosmic palette
    let pal = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 0.33, 0.67) * TAU + time * 0.5 - trap * 2.0);
    var phoenixColor = pal * (density + shell * 0.6 + sparkle);
    phoenixColor += vec3<f32>(1.0, 0.4, 0.1) * chronoGlow * plasma;

    // Branchless mouse halo
    let mouseDist = length(uv01 - mouse);
    let mouseGlow = exp(-mouseDist * 20.0) * (0.3 + bass);
    phoenixColor += vec3<f32>(0.4, 0.8, 1.0) * mouseGlow;

    // Composite over video, then nebula behind
    var color = mix(video.rgb, phoenixColor, clamp(density + shell * 0.5, 0.0, 1.0));
    color = mix(color, bgColor, 0.35 * (1.0 - density));

    // ACES tone map + IGN dither
    color = acesToneMap(color * (1.0 + mids * 0.2));
    color += (ign(vec2<f32>(pixel)) - 0.5) / 255.0;

    // Semantic alpha: density + shell glow + chrono emission
    let alpha = clamp(density + shell * 0.4 + chronoGlow * 0.2, 0.0, 1.0);

    // Depth: phoenix in front, preserve input depth where transparent
    let depth = mix(inDepth, 0.2 + density * 0.6, clamp(density + shell * 0.5, 0.0, 1.0));

    textureStore(writeTexture, pixel, vec4<f32>(color * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(trap, d, nebula, alpha));
}