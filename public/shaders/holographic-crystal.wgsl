// ═══════════════════════════════════════════════════════════════════
//  Holographic Crystal
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, anti-moire
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
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;
const HOLO_R_SHIFT: f32 = 0.0;
const HOLO_G_SHIFT: f32 = 2.09439510239;
const HOLO_B_SHIFT: f32 = 4.18879020479;
const FACET_ID_OFFSET: f32 = 1.73;

// ── Helpers ───────────────────────────────────────────────────────
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Anti-moire LOD: compute approximate screen-space frequency attenuation
fn moireAttenuate(dims: vec2<u32>, freq: f32) -> f32 {
    let minRes = min(f32(dims.x), f32(dims.y));
    let lod = clamp(log2(freq * 250.0 / minRes), 0.0, 3.0);
    return exp2(-lod);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    // ═══ CHUNK: bass_env smoothing (replaces raw-bass strobing) ═══
    let prevBass = extraBuffer[0];
    let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
    extraBuffer[0] = smoothBass;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz * 2.0 - 1.0;

    // ── Uniform params ────────────────────────────────────────────
    let facets = mix(3.0, 16.0, u.zoom_params.x);
    let tilt = mix(0.0, 1.0, u.zoom_params.y);
    let interference = mix(0.1, 2.0, u.zoom_params.z);
    let dispersion = mix(0.1, 1.5, u.zoom_params.w);

    let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
    var p = uv * 2.0 - 1.0;
    p.x = p.x * aspect;

    let tiltAngle = tilt * 0.8 + mouse.x * 0.3;
    let ct = cos(tiltAngle);
    let st = sin(tiltAngle);
    let tp = vec2<f32>(ct * p.x - st * p.y, st * p.x + ct * p.y);

    let crystalShape = max(abs(tp.x), abs(tp.y));

    // ── Early exit for background pixels ──────────────────────────
    if (crystalShape > 0.55) {
        let bg = vec3<f32>(0.005, 0.005, 0.015);
        textureStore(writeTexture, coord, vec4<f32>(bg, 0.0));
        textureStore(writeDepthTexture, coord, vec4<f32>(1.0, 0.0, 0.0, 1.0));
        textureStore(dataTextureA, coord, vec4<f32>(0.0));
        return;
    }

    // ── Facet structure ───────────────────────────────────────────
    let crystalR = crystalShape * facets;
    let crystalEdge = fract(crystalR);
    let facetId = floor(crystalR);
    let edgeGlow = smoothstep(0.85, 1.0, crystalEdge) + smoothstep(0.0, 0.15, crystalEdge);

    // ── Chromatic holographic phase ───────────────────────────────
    let holoPhase = crystalR * PI + time * (0.5 + smoothBass * 0.8) + facetId * FACET_ID_OFFSET;
    let holoR = 0.5 + 0.5 * sin(holoPhase + HOLO_R_SHIFT + treble * 0.3);
    let holoG = 0.5 + 0.5 * sin(holoPhase + HOLO_G_SHIFT + mids * 0.25);
    let holoB = 0.5 + 0.5 * sin(holoPhase + HOLO_B_SHIFT + smoothBass * 0.2);
    let holoRGB = vec3<f32>(holoR * 1.1, holoG, holoB * 0.95);

    // ── Interior and moire with anti-alias attenuation ────────────
    let interior = smoothstep(0.5, 0.0, crystalShape);
    let moireFade = moireAttenuate(dims, 40.0);
    let moire = sin(tp.x * 40.0 * moireFade + time) *
                sin(tp.y * 40.0 * moireFade - time * 0.7) * interior;

    // ── Chromatic composition ─────────────────────────────────────
    var color = vec3<f32>(0.01, 0.01, 0.02);
    color = color + holoRGB * edgeGlow * interference * (1.0 + treble * 0.15);
    color = color + vec3<f32>(0.6, 0.85, 1.0) * moire * dispersion * (1.0 + mids * 0.1);
    color = color + vec3<f32>(0.9, 0.75, 1.0) * interior * 0.15;

    // ── Temporal feedback ─────────────────────────────────────────
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, prev.rgb * 0.9, 0.025 + smoothBass * 0.01);

    // ── Post-process ready packaging ──────────────────────────────
    let presence = sat(edgeGlow * 0.8 + interior * 0.3);
    let alpha = sat(0.08 + presence * 0.92);
    let depth = sat(0.9 - edgeGlow * 0.5 - interior * 0.3);

    color = acesToneMap(color * 1.1);

    let outRGBA = vec4<f32>(color * alpha, alpha);

    textureStore(writeTexture, coord, outRGBA);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(edgeGlow, moire, interior, alpha));
}
