// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Smear — Algorithmist Upgrade
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal, depth-aware,
//            curl-noise, domain-warp, aces-tone-map, semantic-alpha
//  Complexity: Medium
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ──────────────────────────────────────────────────
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
    for (var i: i32 = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

// ── Divergence-free velocity field ────────────────────────────────
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 3) - fbm(p - vec2<f32>(0.0, eps), 3);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 3) - fbm(p - vec2<f32>(eps, 0.0), 3);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Domain-warped organic drift ───────────────────────────────────
fn warpedDrift(uv: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(uv + vec2<f32>(0.0, time * 0.11), 3),
                      fbm(uv + vec2<f32>(5.2, 1.3) - time * 0.08, 3));
    let r = vec2<f32>(fbm(uv * 1.3 + q * 2.0 + vec2<f32>(1.7, 9.2), 2),
                      fbm(uv * 1.1 - q.yx * 2.0 + vec2<f32>(8.1, 2.8), 2));
    return (q + r * 0.5) * strength;
}

// ── Quasi-random Halton jitter ────────────────────────────────────
fn halton(i: u32, base: u32) -> f32 {
    var f = 1.0;
    var r = 0.0;
    var idx = i;
    loop {
        if (idx == 0u) { break; }
        f = f / f32(base);
        r = r + f * f32(idx % base);
        idx = idx / base;
    }
    return r;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ═══════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Depth-aware scaling
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    let depthFactor = mix(1.0, 0.3, depth);

    // Previous frame history + motion estimate from luminance gradient
    let texel = vec2<f32>(1.0) / res;
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv01, 0.0);
    let hC = luma(prev.rgb);
    let hR = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 + vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let hL = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 - vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let hU = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 + vec2<f32>(0.0, texel.y), 0.0).rgb);
    let hD = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 - vec2<f32>(0.0, texel.y), 0.0).rgb);
    let grad = vec2<f32>((hR - hL) * 0.5, (hU - hD) * 0.5);
    let motionStrength = length(grad);
    let motionDir = normalize(grad + vec2<f32>(0.0001));

    // Base time direction blended with curl-noise swirl
    let timeAngle = time * 0.5 + p4 * TAU;
    let timeDir = vec2<f32>(cos(timeAngle), sin(timeAngle));
    let curl = curl2D(uv * (2.0 + p4 * 6.0) + time * 0.1, time * 0.2);
    let flowDir = normalize(mix(timeDir, curl, 0.4 + p4 * 0.4));
    let smearDir = normalize(mix(flowDir, motionDir, smoothstep(0.0, 0.05, motionStrength)));

    // Smear length + chromatic split, audio/depth modulated
    let smearLength = mix(0.01, 0.25, p1);
    let chromaticSplit = mix(0.0, 0.05, p3) * (1.0 + mids * 0.5);
    let len = smearLength * (1.0 + bass * 0.3) * depthFactor;

    // Domain-warped drift + Halton jitter for sample dithering
    let drift = warpedDrift(uv * 3.0, time, p4 * 0.04);
    let jit = vec2<f32>(halton(global_id.x + global_id.y * 97u, 2u) - 0.5,
                        halton(global_id.x + global_id.y * 73u, 3u) - 0.5) * 0.002;

    let baseOff = uv01 + drift * len + jit;
    let offR = clamp(baseOff + smearDir * len * (1.0 + chromaticSplit), vec2<f32>(0.0), vec2<f32>(1.0));
    let offG = clamp(baseOff + smearDir * len, vec2<f32>(0.0), vec2<f32>(1.0));
    let offB = clamp(baseOff + smearDir * len * (1.0 - chromaticSplit), vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, offR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, offG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, offB, 0.0).b;
    let sampleRGB = vec3<f32>(colR, colG, colB);

    // Temporal feedback with per-channel decay variation
    let smearDecay = mix(0.3, 0.98, p2);
    let fb = clamp(smearDecay * (1.0 + bass * 0.08), 0.0, 0.995);
    let channelDecay = vec3<f32>(fb * 0.52, fb * 0.45, fb * 0.5);
    var history = mix(sampleRGB, prev.rgb, channelDecay);

    // Treble sparkle near mouse, added before feedback storage
    let sparkle = treble * 0.25 * smoothstep(0.25, 0.0, distance(uv01, mouse));
    history += vec3<f32>(sparkle);

    // Store history ping for next frame (pre-tone-map keeps trails lively)
    textureStore(dataTextureA, pixel, vec4<f32>(history, clamp(luma(history) * 1.5, 0.2, 0.95)));

    // Final color: ACES tone map + semantic alpha driven by luma and depth
    var color = acesToneMap(history * (1.0 + mids * 0.15));
    let alpha = clamp(luma(color) * 1.6, 0.25, 0.95) * mix(0.75, 1.0, 1.0 - depth * 0.35);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
