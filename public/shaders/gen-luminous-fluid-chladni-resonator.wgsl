// ═══════════════════════════════════════════════════════════════════
//  Luminous-Fluid Chladni-Resonator
//  Category: generative
//  Features: audio-reactive, multi-mode Chladni, curl-noise fluid, Voronoi ridges
//  Complexity: Medium
//  Phase B / Algorithmist
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
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ModeN, y=ModeM, z=FluidStrength, w=Glow
  ripples: array<vec4<f32>, 50>,
};

const PI:    f32 = 3.14159265358979323846;
const TAU:   f32 = 6.28318530717958647692;
const PHI:   f32 = 1.61803398874989484820;
const SQRT3: f32 = 1.73205080756887729352;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// FBM with rotation matrix (golden-angle rotation reduces axis bias)
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var q = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(q);
        q = rot * q * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Curl noise (divergence-free) — for proper fluid velocity field
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let nx = fbm(p + vec2<f32>(0.0, eps)) - fbm(p - vec2<f32>(0.0, eps));
    let ny = fbm(p + vec2<f32>(eps, 0.0)) - fbm(p - vec2<f32>(eps, 0.0));
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// Voronoi F2-F1 (cellular ridges, like nodal lines on a vibrating plate)
fn voronoiRidge(p: vec2<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    var F1 = 1e9;
    var F2 = 1e9;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let n = vec2<f32>(f32(i), f32(j));
            let cellPt = n + vec2<f32>(hash21(ip + n), hash21(ip + n + 17.0));
            let d = length(cellPt - fp);
            if (d < F1) { F2 = F1; F1 = d; }
            else if (d < F2) { F2 = d; }
        }
    }
    return F2 - F1;
}

// Multi-mode Chladni — sum of (n,m) and dual symmetric pair
fn chladni_multi(uv: vec2<f32>, n: f32, m: f32, t: f32) -> f32 {
    let a1 = sin(n * PI * uv.x) * sin(m * PI * uv.y);
    let a2 = sin(m * PI * uv.x) * sin(n * PI * uv.y);
    let b1 = sin((n + 1.0) * PI * uv.x) * sin((m + 1.0) * PI * uv.y);
    let b2 = sin((m + 1.0) * PI * uv.x) * sin((n + 1.0) * PI * uv.y);
    let pri = cos(t) * a1 + sin(t) * a2;
    let sec = cos(t * PHI) * b1 + sin(t * PHI) * b2;
    return pri + 0.4 * sec;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(i32(id.x), i32(id.y));
    if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(coord) / res;
    let t = u.config.x * 0.5;
    let bass = plasmaBuffer[0].x;

    let param_n     = u.zoom_params.x;
    let param_m     = u.zoom_params.y;
    let param_fluid = u.zoom_params.z;
    let param_glow  = u.zoom_params.w;

    // Curl-noise displacement (divergence-free — proper fluid)
    let velocity = curl2D(uv * 5.0 + vec2<f32>(t * 0.3));
    let uv_dist  = uv + velocity * param_fluid * 0.05 * (1.0 + bass * 0.5);

    // Bass-modulated mode numbers (pseudo-resonance sweep)
    let n = param_n + bass * 2.0 * sin(t);
    let m = param_m + bass * 2.0 * cos(t * PHI);

    // Multi-mode Chladni interference field
    let c_val = chladni_multi(uv_dist * 2.0 - vec2<f32>(1.0), n, m, t * 2.0);

    // Voronoi ridges weave nodal-line cellular structure into the field
    let ridge = 1.0 - smoothstep(0.0, 0.18, voronoiRidge(uv * 8.0 + velocity * 0.2));

    // Mouse acts as standing-wave damper
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let d_mouse = distance(uv, mouse_uv);
    let damp = smoothstep(0.0, 0.2, d_mouse);

    // Beer-Lambert absorption: deeper field travel = more glow attenuation
    let depthAttn = exp(-d_mouse * 1.5);
    let final_val = abs(c_val) * damp + ridge * 0.35 * depthAttn;

    // Verlet-style temporal coherence — accumulate prior frame field for ringing
    let prior = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let settled = mix(prior, final_val, 0.35);

    // Nodal lines = where settled ≈ 0 → bright; antinodes = darker
    let intensity = smoothstep(0.18, 0.0, settled) * param_glow * (1.0 + bass);

    // Plasma palette mapped by intensity, modulated by ridge phase
    let p_idx = u32(clamp(intensity * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[p_idx % 256u].rgb;
    let col = palette * (intensity + ridge * 0.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(intensity * 0.6 + luma * 0.4 + ridge * 0.15, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    // Persist field for next-frame coherence
    textureStore(dataTextureA, coord, vec4<f32>(settled, ridge, intensity, 1.0));
}
