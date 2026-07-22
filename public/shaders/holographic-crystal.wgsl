// ═══════════════════════════════════════════════════════════════════
//  Holographic Crystal
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, anti-moire,
//            worley-facet-normals, treble-glint, phase-dither
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
//  Optimized: 2026-07-22 (swarm Optimizer pass: per-pixel phase dither,
//             worley-perturbed facet catch-light, treble-driven edge glints,
//             dispersion slider rewired to true chromatic phase spread)
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
  config: vec4<f32>,        // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,   // .x = time, .yz = mouse_uv (0-1), .w = mouse_down
  zoom_params: vec4<f32>,   // .xyzw = facets / tilt / interference / dispersion
  ripples: array<vec4<f32>, 50>,
};

// ── Constants ─────────────────────────────────────────────────────
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;
const HOLO_R_SHIFT: f32 = 0.0;
const HOLO_G_SHIFT: f32 = 2.09439510239;   // 2*PI/3 base chromatic offset
const HOLO_B_SHIFT: f32 = 4.18879020479;   // 4*PI/3 base chromatic offset
const FACET_ID_OFFSET: f32 = 1.73;
const DITHER_AMP: f32 = 0.9;               // phase dither amplitude (radians)
const WORLEY_FREQ: f32 = 2.6;              // low-freq facet-normal field scale
const GLINT_GAIN: f32 = 1.35;              // treble glint master gain

// ── Hashes (canonical forms) ──────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// ── Worley F1 field (3x3 neighborhood, low-frequency) ────────────
// Used to perturb per-facet normals so facets catch light unevenly,
// like cut glass instead of uniform stamped planes.
fn worley(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var d = 8.0;
    for (var gy = -1; gy <= 1; gy++) {
        for (var gx = -1; gx <= 1; gx++) {
            let g = vec2<f32>(f32(gx), f32(gy));
            let o = hash22(i + g);
            d = min(d, length(g + o - f));
        }
    }
    return d;
}

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
    let prevBass = extraBuffer[133];
    let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
    if (gid.x == 0u && gid.y == 0u) {
      extraBuffer[133] = smoothBass;
    }
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz * 2.0 - 1.0;

    // ── Uniform params (saved-preset contract: ids/defaults fixed) ──
    // facets       -> facet ring density
    // tilt         -> lattice tilt angle + facet catch-light orientation
    // interference -> holographic edge-fringe amplitude
    // dispersion   -> chromatic phase spread between R/G/B channels
    let facets = mix(3.0, 16.0, u.zoom_params.x);
    let tilt = mix(0.0, 1.0, u.zoom_params.y);
    let interference = mix(0.1, 2.0, u.zoom_params.z);
    let dispersion = mix(0.1, 1.5, u.zoom_params.w);

    let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
    var p = uv * 2.0 - 1.0;
    p.x = p.x * aspect;

    // Tilt slider drives the lattice rotation; mouse adds a fine nudge.
    let tiltAngle = tilt * 1.1 + mouse.x * 0.3;
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

    // ── Worley facet-normal perturbation ──────────────────────────
    // Two decorrelated low-frequency worley taps form a pseudo-normal
    // per facet; dotting with a light direction makes facets catch
    // light unevenly like cut glass. Tilt slider reorients the light.
    let wDrift = vec2<f32>(time * 0.04, -time * 0.03);
    let wA = worley(tp * WORLEY_FREQ + wDrift);
    let wB = worley(tp * WORLEY_FREQ + vec2<f32>(3.7, 9.1) - wDrift.yx);
    let facetNormal = vec2<f32>(wA, wB) - vec2<f32>(0.45);
    let lightAngle = 0.9 + tilt * 1.4 + mouse.y * 0.4;
    let lightDir = vec2<f32>(cos(lightAngle), sin(lightAngle));
    let facetCatch = sat(dot(normalize(facetNormal + vec2<f32>(0.001)), lightDir));
    let facetShade = mix(0.55, 1.45, facetCatch * facetCatch);

    // ── Chromatic holographic phase (with per-pixel dither) ───────
    // Per-pixel hash dither breaks up residual banding/aliasing on the
    // high-frequency interference fringes (anti-moire insurance).
    let dither = (hash21(vec2<f32>(gid.xy)) - 0.5) * DITHER_AMP;
    // Dispersion slider spreads the R/G/B phase offsets around green:
    // low dispersion = near-monochrome fringes, high = full rainbow.
    let rgbSpread = HOLO_G_SHIFT * dispersion;
    let holoPhase = crystalR * PI + time * (0.5 + smoothBass * 0.8) +
                    facetId * FACET_ID_OFFSET + dither;
    let holoR = 0.5 + 0.5 * sin(holoPhase + HOLO_R_SHIFT * dispersion + treble * 0.3);
    let holoG = 0.5 + 0.5 * sin(holoPhase + rgbSpread + mids * 0.25);
    let holoB = 0.5 + 0.5 * sin(holoPhase + HOLO_B_SHIFT * dispersion + smoothBass * 0.2);
    let holoRGB = vec3<f32>(holoR * 1.1, holoG, holoB * 0.95) * facetShade;

    // ── Interior and moire with anti-alias attenuation ────────────
    let interior = smoothstep(0.5, 0.0, crystalShape);
    let moireFade = moireAttenuate(dims, 40.0);
    let moire = sin(tp.x * 40.0 * moireFade + time + dither) *
                sin(tp.y * 40.0 * moireFade - time * 0.7) * interior;

    // ── Treble facet glint ────────────────────────────────────────
    // Razor-sharp sparkle highlights riding the facet edges, twinkling
    // per facet over time and pumping with the treble band. Masked hard
    // by facet-edge proximity so interiors stay smooth.
    let glintTwinkle = 0.5 + 0.5 * sin(time * 6.0 + facetId * 7.13 +
                                       hashf(facetId + 0.5) * TAU);
    let glintMask = pow(sat(edgeGlow), 12.0);
    let glint = glintMask * pow(glintTwinkle, 24.0) * (0.25 + treble * 1.6);

    // ── Chromatic composition ─────────────────────────────────────
    var color = vec3<f32>(0.01, 0.01, 0.02);
    color = color + holoRGB * edgeGlow * interference * (1.0 + treble * 0.15);
    color = color + vec3<f32>(0.6, 0.85, 1.0) * moire * dispersion * (1.0 + mids * 0.1);
    color = color + vec3<f32>(0.9, 0.75, 1.0) * interior * 0.15 * facetShade;
    color = color + vec3<f32>(1.0, 0.97, 0.88) * glint * GLINT_GAIN;

    // ── Temporal feedback ─────────────────────────────────────────
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, prev.rgb * 0.9, 0.025 + smoothBass * 0.01);

    // ── Post-process ready packaging ──────────────────────────────
    let presence = sat(edgeGlow * 0.8 + interior * 0.3 + glint * 0.6);
    let alpha = sat(0.08 + presence * 0.92);
    let depth = sat(0.9 - edgeGlow * 0.5 - interior * 0.3 - glint * 0.2);

    color = acesToneMap(color * 1.1);

    let outRGBA = vec4<f32>(color * alpha, alpha);

    textureStore(writeTexture, coord, outRGBA);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(edgeGlow, moire, interior, alpha));
}
