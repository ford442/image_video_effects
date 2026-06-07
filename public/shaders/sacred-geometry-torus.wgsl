// ═══════════════════════════════════════════════════════════════════
//  Sacred Geometry Torus
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, aces-tone-map, depth-aware, branchless
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
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

// ── Constants ─────────────────────────────────────────────────────
const PHI: f32 = 1.61803398875;
const TAU: f32 = 6.28318530718;
const INV_PHI: f32 = 0.61803398875;
const MAX_PHI_LAYERS: u32 = 7u;
const KNOT_TAPS: u32 = 5u;

// ── Fast math helpers ─────────────────────────────────────────────
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn fast_atan2(y: f32, x: f32) -> f32 {
    let ax = abs(x);
    let ay = abs(y);
    let a = min(ax, ay) / (max(ax, ay) + 1e-6);
    let s = a * a;
    var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
    if (ay > ax) { r = 1.5707963 - r; }
    if (x < 0.0) { r = 3.1415927 - r; }
    if (y < 0.0) { r = -r; }
    return r;
}

fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Geometric helpers ─────────────────────────────────────────────
fn nodeGlow(p: vec2<f32>, center: vec2<f32>, strength: f32) -> f32 {
    let d = p - center;
    return fast_exp(-dot(d, d) * strength);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz * 2.0 - 1.0;

    // ── Parameter extraction (uniform-driven, computed once) ──────
    let knots = mix(2.0, 12.0, u.zoom_params.x);
    let spin = mix(0.1, 2.5, u.zoom_params.y);
    let glow = mix(0.3, 2.0, u.zoom_params.z);
    let phiLayers = mix(1.0, 7.0, u.zoom_params.w);

    let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
    var p = uv * 2.0 - 1.0;
    p.x = p.x * aspect;
    p = p - mouse * 0.2;

    let r = length(p);
    let a = fast_atan2(p.y, p.x);

    // ── Early exit: sky / background pixels ───────────────────────
    if (r > 0.95) {
        let bg = vec3<f32>(0.005, 0.005, 0.01);
        textureStore(writeTexture, coord, vec4<f32>(bg, 0.0));
        textureStore(writeDepthTexture, coord, vec4<f32>(1.0, 0.0, 0.0, 1.0));
        textureStore(dataTextureA, coord, vec4<f32>(0.0));
        return;
    }

    // ── Torus knot pattern (fixed 5 taps, unrolled by compiler) ───
    var pattern = 0.0;
    for (var i = 0u; i < KNOT_TAPS; i = i + 1u) {
        let fi = f32(i);
        let k = knots + fi * 0.5;
        let pa = a + time * spin * (1.0 + bass * 0.5) + fi * TAU * INV_PHI;
        let pr = r * (3.0 + fi * PHI) - time * (0.3 + mids * 0.4);
        let weave = abs(sin(pa * k + pr));
        pattern = pattern + smoothstep(0.92, 1.0, weave) * pow(0.7, fi);
    }

    // ── Sacred ring mask ──────────────────────────────────────────
    let ring = smoothstep(0.55, 0.75, abs(r - 0.5 + mouse.x * 0.1));

    // ── Phi-harmonic nodes (branchless: always 7, soft-masked) ────
    for (var i = 0u; i < MAX_PHI_LAYERS; i = i + 1u) {
        let fi = f32(i);
        let layerMask = sat(phiLayers - fi);
        let na = a * (knots + fi) + time * spin * PHI;
        let nr = 0.25 + fi * 0.12;
        let np = vec2<f32>(cos(na), sin(na)) * nr;
        let falloff = 200.0 + treble * 150.0;
        pattern = pattern + nodeGlow(p, np, falloff) * (0.6 + fi * 0.15) * layerMask;
    }

    // ── Chromatic composition: golden / emerald / sapphire ────────
    var color = vec3<f32>(0.01, 0.01, 0.02);
    color = color + vec3<f32>(1.0, 0.78, 0.15) * pattern * glow * (1.0 + bass * 0.2);
    color = color + vec3<f32>(0.15, 0.85, 0.55) * ring * glow * (1.0 + mids * 0.15);
    color = color + vec3<f32>(0.25, 0.45, 1.0) * pattern * ring * 0.4 * (1.0 + treble * 0.2);

    // ── Temporal feedback via dataTextureC ────────────────────────
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // ── Post-process ready packaging ──────────────────────────────
    let presence = sat(pattern * 0.9 + ring * 0.5);
    let alpha = sat(0.1 + presence * 0.9);
    let depth = sat(0.9 - pattern * 0.5 - ring * 0.3);

    color = acesToneMap(color * 1.1);

    // Premultiplied alpha writeback for slot-chain compositing
    let outRGBA = vec4<f32>(color * alpha, alpha);

    textureStore(writeTexture, coord, outRGBA);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(pattern, ring, phiLayers * 0.1, alpha));
}
