// ═══════════════════════════════════════════════════════════════════
//  Volcanic Ink — Optimizer upgrade
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal-feedback,
//            LOD-scaling, blue-noise embers, unrolled neighbor blur,
//            depth-aware, chromatic-aberration, ACES-tone-map, HDR-ready
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-29
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv (0-1), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = time_created, .w = strength
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Tunable constants ─────────────────────────────────────────────
const INK_BASE: vec3<f32> = vec3<f32>(0.015, 0.008, 0.012);
const LAVA_TINT: vec3<f32> = vec3<f32>(1.25, 0.36, 0.06);
const CRACK_TINT: vec3<f32> = vec3<f32>(0.40, 0.10, 0.05);
const SMOKE_TINT: vec3<f32> = vec3<f32>(0.10, 0.09, 0.12);
const SPARK_TINT: vec3<f32> = vec3<f32>(1.00, 0.74, 0.28);
const EMBER_GRID: f32 = 120.0;
const GOLDEN_ANGLE: f32 = 2.39996322972865332;

// ── Hash / noise ──────────────────────────────────────────────────
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

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

// Cheap domain warp reused across fissure/lava layers.
fn warp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(
        valueNoise(p + vec2<f32>(t * 0.05, -t * 0.03)),
        valueNoise(p + vec2<f32>(5.2, 1.3) + vec2<f32>(-t * 0.04, t * 0.06))
    );
    return p + q * 0.30;
}

// ── Color / tone ──────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5) + time * 0.05;
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ── LOD / quality scaling ─────────────────────────────────────────
// Resolution-aware base level + user detail slider (p4) to stay inside
// the frame budget while still allowing high-end GPUs to push detail.
fn qualityLOD(shortEdge: f32, detail: f32) -> i32 {
    let base = select(3.0, select(4.0, 5.0, shortEdge > 1000.0), shortEdge > 640.0);
    return i32(clamp(base + detail, 3.0, 6.0));
}

// ── Temporal: unrolled 3x3 bilinear neighbor blur ─────────────────
// Small, separable-ish kernel. Weights sum to 1.0 and use dataTextureC
// so feedback trails stay smooth without a loop.
fn neighborBlur(uv: vec2<f32>, invRes: vec2<f32>) -> vec4<f32> {
    let dx = vec2<f32>(invRes.x, 0.0);
    let dy = vec2<f32>(0.0, invRes.y);
    var acc = vec4<f32>(0.0);

    acc += 0.0625 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-dx.x, -dy.y), 0.0);
    acc += 0.1250 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( 0.0,   -dy.y), 0.0);
    acc += 0.0625 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( dx.x, -dy.y), 0.0);

    acc += 0.1250 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-dx.x,  0.0),  0.0);
    acc += 0.2500 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( 0.0,    0.0),  0.0);
    acc += 0.1250 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( dx.x,  0.0),  0.0);

    acc += 0.0625 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-dx.x,  dy.y), 0.0);
    acc += 0.1250 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( 0.0,    dy.y), 0.0);
    acc += 0.0625 * textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( dx.x,  dy.y), 0.0);

    return acc;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let invRes = 1.0 / res;

    // Inputs
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let readDepth = textureLoad(readDepthTexture, pixel, 0).r;

    // Parameter remapping
    let fissureDensity = mix(1.0, 8.0, u.zoom_params.x);
    let magmaFlow = mix(0.1, 2.2, u.zoom_params.y);
    let soot = mix(0.0, 1.0, u.zoom_params.z);
    let emberIntensity = mix(0.2, 2.4, u.zoom_params.w);

    // LOD: resolution + user detail
    let octaves = qualityLOD(min(res.x, res.y), u.zoom_params.w);

    // ── Geometry / domain warp ──────────────────────────────────────
    var p = uv * 2.0 - 1.0;
    p.x = p.x * (res.x / max(res.y, 1.0));
    p = p + mouse * 0.25;

    let flowTime = time * magmaFlow;
    let w = warp(p * fissureDensity, flowTime);

    // ── Fissures / cracks ───────────────────────────────────────────
    let n0 = fbm(w, octaves);
    let n1 = fbm(w * 1.75 + vec2<f32>(3.1, 1.7), octaves);
    let crackDiff = abs(n0 - n1) * (1.0 + bass * 0.5);
    let cracks = smoothstep(0.62, 0.92, crackDiff);

    // ── Lava body ───────────────────────────────────────────────────
    let lavaUv = p * 2.6 + vec2<f32>(flowTime * 0.3, time * 0.17);
    let lavaField = fbm(lavaUv, octaves);
    let lava = smoothstep(0.55, 0.92, lavaField) * (1.0 - cracks * 0.7);

    // ── Smoke / soot plumes ─────────────────────────────────────────
    let smokeOctaves = max(octaves - 1, 3);
    let smokeUv = p * vec2<f32>(1.3, 2.4) - vec2<f32>(0.0, time * (0.2 + mids * 0.5));
    let smoke = fbm(smokeUv, smokeOctaves);

    // ── Blue-noise ember sparks ─────────────────────────────────────
    let grid = uv01 * EMBER_GRID;
    let cell = floor(grid);
    let local = fract(grid);
    let h = hash22(cell + vec2<f32>(time * 0.13, time * 0.07));
    let jitter = 0.5 + 0.4 * h;
    let dist2 = dot(local - jitter, local - jitter);
    let sparkMask = step(0.97 - treble * 0.03, 1.0 - sqrt(dist2));
    let twinkle = 0.5 + 0.5 * sin(time * 18.0 + hashf(cell.x + cell.y * 31.0) * 30.0);
    let emberSpark = sparkMask * twinkle * emberIntensity;

    // ── Color composition (HDR-linear, >1.0 allowed) ────────────────
    var color = INK_BASE;
    color += LAVA_TINT * lava * emberIntensity * (1.0 + bass * 0.15);
    color += CRACK_TINT * cracks * 0.55;
    color += SMOKE_TINT * smoke * soot * (1.0 + treble * 0.1);
    color += SPARK_TINT * emberSpark * (0.4 + bass);

    // ── Temporal feedback (ink persistence) ─────────────────────────
    let prevBlur = neighborBlur(uv01, invRes);
    let feedbackStrength = 0.03 + soot * 0.07 + bass * 0.015;
    let trail = mix(color, prevBlur.rgb * 0.96, feedbackStrength);

    // ── Depth / chromatic / tone / alpha ────────────────────────────
    let genDepth = clamp(0.95 - lava * 0.55 - emberSpark * 0.2 + smoke * 0.08, 0.0, 1.0);
    let depth = mix(genDepth, readDepth, 0.15);

    let caStr = 0.0025 * (1.0 + bass) + depth * 0.0015;
    color = genChromaticShift(trail, uv01, caStr, time);

    let exposure = 1.05 + mids * 0.12;
    color = acesToneMap(color * exposure);

    let presence = clamp(lava * 0.9 + cracks * 0.3 + emberSpark * 0.85, 0.0, 1.0);
    let alpha = clamp(0.15 + presence * 0.85, 0.0, 0.96);

    // ── Pipeline outputs ────────────────────────────────────────────
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
    textureStore(dataTextureB, pixel, vec4<f32>(lava, cracks, emberSpark, smoke));
}
