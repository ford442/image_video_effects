// ═══════════════════════════════════════════════════════════════════
//  Fractal Bioluminescence Spore-Network
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-07
// ═══════════════════════════════════════════════════════════════════
const PI=3.14159265358979323846; const TAU=6.28318530717958647692;
const PHI=1.61803398874989484820; const SQRT2=1.41421356237309504880;
const SQRT3=1.73205080756887729352; const E=2.71828182845904523536;
const LN2=0.69314718055994530941; const INV_PI=0.31830988618379067154;

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

fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * vnoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a*p.y) + c*cos(a*p.x), sin(b*p.x) + d*cos(b*p.y));
}

fn goldNoise(uv: vec2<f32>, seed: f32) -> f32 {
    return fract(sin(distance(uv * PHI, uv) * seed) * uv.x);
}

fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x);
    let seg = TAU / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}

fn map(p_in: vec3<f32>, complexity: f32, time: f32, audio_react: f32) -> f32 {
    var p = p_in;
    let iters = i32(clamp(complexity, 1.0, 10.0));
    var scale = 1.0;
    for (var i = 0; i < iters; i = i + 1) {
        p = abs(p) - vec3<f32>(1.5, 1.5, 1.5) * scale;
        let p_xy = rot2d(time * 0.1 + f32(i) * INV_PI) * vec2<f32>(p.x, p.y);
        p = vec3<f32>(p_xy.x, p_xy.y, p.z);
        let p_yz = rot2d(time * 0.15 + f32(i) * INV_PI * 0.5) * vec2<f32>(p.y, p.z);
        p = vec3<f32>(p.x, p_yz.x, p_yz.y);
        scale *= 0.8;
    }
    let ca = clifford(p.xy * 0.5, 1.8 + time*0.05, -2.1, -1.5, 2.3);
    let spore1 = length(p - vec3<f32>(ca.x, ca.y, sin(time*0.2)*0.5)) - 0.3 * scale;
    let spore2 = length(p - vec3<f32>(-ca.y, ca.x, cos(time*0.15)*0.5)) - 0.25 * scale;
    let fil = length(p.xz) - 0.05 * scale;
    var d = smin(spore1, spore2, 0.15 * scale);
    d = smin(d, fil, 0.08 * scale);
    return d;
}

fn hueShift(c: vec3<f32>, h: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_a = cos(h);
    return c * cos_a + cross(k, c) * sin(h) + k * dot(k, c) * (1.0 - cos_a);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }
    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dimensions)) / f32(dimensions.y);
    let time = u.config.x;
    let spore_density = u.zoom_params.x;
    let network_complexity = u.zoom_params.y;
    let bio_intensity = u.zoom_params.z;
    let audio_react = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouse_dist = length(uv - mouse);
    let injection = (1.0 / (1.0 + mouse_dist * 10.0)) * u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
        (vec2<f32>(id.xy) + 0.5) / vec2<f32>(dimensions), 0.0).r;

    let kUV = kaleido(uv * 1.5, 3.0 + sin(time * 0.08) * 2.0);
    let warp = warpedFBM(kUV * 2.0 + vec2<f32>(time * 0.1, time * 0.07), time) * 0.15;
    let jitter = goldNoise(uv * 100.0, time) * 0.003;
    var ro = vec3<f32>(warp + jitter, warp * 0.5 + jitter, -5.0 + time * 0.2);
    var rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0; var d = 0.0; var glow = 0.0; var energy = 0.0;
    for (var i = 0; i < 64; i = i + 1) {
        let p = ro + rd * t;
        d = map(p, network_complexity + injection * 2.0, time + bass * audio_react, audio_react);
        if (d < 0.01) {
            energy = 1.0 - f32(i) / 64.0;
            break;
        }
        t += d * 0.5;
        glow += (0.01 / (0.01 + d * d)) * spore_density;
        if (t > 20.0) { break; }
    }

    let col_base = vec3<f32>(0.05, 0.35, 0.65);
    let col_hot = vec3<f32>(1.0, 0.85, 0.15);
    let col_inj = vec3<f32>(0.15, 0.75, 0.45);

    var final_col = mix(col_base, col_hot, glow * 0.1) * glow * bio_intensity * 0.25;
    final_col += col_inj * injection * 2.0;
    final_col = final_col * (1.0 + audio_react * bass * 0.3 + treble * 0.1);

    let hueDrift = warpedFBM(uv * 2.0, time * 0.05) * PI * 0.25;
    final_col = hueShift(final_col, hueDrift + time * 0.03);

    let absorb = exp(-depth * 2.0 * LN2);
    final_col = final_col * absorb + vec3<f32>(0.02, 0.08, 0.12) * (1.0 - absorb);

    let luma = dot(final_col, vec3<f32>(0.299, 0.587, 0.114));
    let semantic_alpha = clamp(energy * 0.4 + luma * 2.0 + glow * 0.1, 0.05, 0.98);

    let outDepth = clamp(t / 20.0, 0.0, 1.0);

    textureStore(writeTexture, id.xy, vec4<f32>(final_col, semantic_alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(final_col, semantic_alpha));
}
