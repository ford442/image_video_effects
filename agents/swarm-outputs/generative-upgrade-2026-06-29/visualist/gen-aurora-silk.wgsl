// ═══════════════════════════════════════════════════════════════════
//  Aurora Silk — Visualist Upgrade
//  Category: generative
//  Features: HDR, ACES, split-tone, temperature, fresnel rim, god rays,
//            caustics, volumetric fog, depth layering, audio-reactive,
//            temporal-feedback, chromatic-aberration, semantic-alpha
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Dynamic color temperature: cool shadows to warm highlights
fn colorTemperature(col: vec3<f32>, temp: f32) -> vec3<f32> {
    let warm = vec3<f32>(1.12, 1.04, 0.90);
    let cool = vec3<f32>(0.90, 0.98, 1.10);
    return col * mix(cool, warm, sat(temp * 0.5 + 0.5));
}

// Split-tone: cool shadows, warm highlights
fn splitTone(col: vec3<f32>, shadowStr: f32, highlightStr: f32) -> vec3<f32> {
    let lum = luma(col);
    let shadowTint = vec3<f32>(0.35, 0.55, 0.85) * shadowStr;
    let highlightTint = vec3<f32>(1.0, 0.78, 0.45) * highlightStr;
    let sMask = 1.0 - smoothstep(0.0, 0.30, lum);
    let hMask = smoothstep(0.50, 1.0, lum);
    return col + shadowTint * sMask + highlightTint * hMask;
}

// Fresnel rim lighting on aurora curtain edges
fn fresnelRim(p: vec2<f32>, intensity: f32) -> f32 {
    let edge = 1.0 - abs(p.x);
    return pow(max(edge, 0.0), 2.2) * intensity;
}

// Volumetric god rays descending from the top of the frame
fn godRays(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let rayUv = uv * vec2<f32>(4.0, 10.0) + vec2<f32>(time * 0.08, 0.0);
    let ray = sin(rayUv.x + sin(rayUv.y * 0.6 + time * 0.25) * 0.6);
    let fade = pow(max(1.0 - uv.y, 0.0), 1.8);
    return max(ray, 0.0) * fade * intensity;
}

// Caustic / dappled light sparkle across the curtains
fn caustics(p: vec2<f32>, time: f32) -> f32 {
    let s = sin(p.x * 7.0 + time * 0.9)
          + sin(p.y * 6.0 - time * 0.7)
          + sin((p.x + p.y) * 5.0 + time * 0.5);
    return pow(max(s * 0.33 + 0.33, 0.0), 3.0);
}

// Volumetric fog / haze layer with soft horizontal drift
fn fogLayer(uv: vec2<f32>, time: f32, density: f32) -> f32 {
    let f = fbm(uv * vec2<f32>(2.0, 0.7) + vec2<f32>(time * 0.04, 0.0), 3);
    let vertical = 1.0 - uv.y * 0.65;
    return pow(f, 2.0) * density * vertical;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // User parameters
    let bandCount = mix(2.0, 14.0, u.zoom_params.x);
    let flowSpeed = mix(0.12, 1.6, u.zoom_params.y);
    let atmosphere = mix(0.0, 1.0, u.zoom_params.z);
    let bloomAmt = mix(0.4, 2.8, u.zoom_params.w);

    // Aspect-correct centered coordinates with mouse parallax
    let aspect = res.x / max(res.y, 1.0);
    var p = uv01 * 2.0 - 1.0;
    p.x = p.x * aspect;
    p = p + mouse * vec2<f32>(0.30, 0.18);

    // Domain-warped wind for organic aurora flow
    let warp = domainWarp(p * vec2<f32>(1.1, 1.8) + vec2<f32>(time * flowSpeed * 0.1, 0.0), 0.35, 3);
    let wind = fbm(warp, 5);

    // Curtain falloff and ribbon bands
    let curtain = exp(-abs(p.x) * (1.3 + mids * 0.7));
    let ribbonWidth = mix(0.12, 0.52, u.zoom_params.z);
    let ribbons = sin((p.y + wind * 0.55) * bandCount * 6.5 + time * flowSpeed * (1.0 + bass * 1.2));
    let band = smoothstep(1.0 - ribbonWidth, 1.0, abs(ribbons));
    let shimmer = 0.5 + 0.5 * sin(time * (2.0 + treble * 12.0) + p.y * 10.0);

    // Base aurora presence (HDR, can exceed 1.0 before tone mapping)
    let presence = curtain * (band * 0.9 + wind * 0.45) * (0.9 + bass * 0.8);
    let hdrPresence = presence * (1.2 + bloomAmt);

    // Aurora palette
    var color = palette(
        wind + shimmer * 0.22 + bass * 0.06,
        vec3<f32>(0.32, 0.44, 0.56),
        vec3<f32>(0.36, 0.36, 0.48),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.10 + treble * 0.05, 0.24 + mids * 0.06)
    );

    // HDR base color + bloom threshold glow
    color = color * hdrPresence * bloomAmt;
    let bloom = max(color - vec3<f32>(0.85), vec3<f32>(0.0)) * (bloomAmt * 0.8);
    color = color + bloom;

    // Fresnel rim lighting on curtain edges
    let rim = fresnelRim(p, 0.45 + mids * 0.35) * (0.8 + treble);
    color = color + vec3<f32>(0.75, 0.88, 1.0) * rim * presence;

    // Volumetric god rays
    let rays = godRays(uv01, time, 0.25 + atmosphere * 0.55);
    color = color + vec3<f32>(0.92, 0.95, 1.0) * rays * (0.6 + treble * 0.6);

    // Caustic dappled light
    let caust = caustics(p * 1.5 + vec2<f32>(0.0, time * flowSpeed * 0.15), time);
    color = color + vec3<f32>(0.55, 0.82, 1.0) * caust * 0.15 * (1.0 + atmosphere);

    // Volumetric fog / haze integration
    let fog = fogLayer(uv01, time, 0.12 + atmosphere * 0.38);
    let fogColor = vec3<f32>(0.55, 0.62, 0.78);
    color = mix(color, fogColor, fog * (0.25 + depth * 0.2));

    // Depth layering: darker/foggier at perceived distance
    let depthLayer = 1.0 - depth * 0.35;
    color = color * depthLayer;

    // Color grading: dynamic temperature + split-tone
    let temp = sin(time * 0.15 + uv01.y * 2.5) * 0.35 + (mids - 0.5) * 0.2;
    color = colorTemperature(color, temp);
    color = splitTone(color, 0.18 + atmosphere * 0.22, 0.12 + bloomAmt * 0.08);

    // Temporal silk persistence
    let decay = 0.96 - u.zoom_params.w * 0.025;
    color = mix(color, prev.rgb * decay, 0.04 + bass * 0.015);

    // Chromatic aberration toward screen edges
    let centerDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.0001));
    let caStr = 0.002 * (1.0 + bass) + depth * 0.001;
    color = vec3<f32>(
        color.r + centerDir.x * caStr,
        color.g,
        color.b - centerDir.y * caStr * 0.5
    );

    // ACES tone map
    color = acesToneMap(color * (0.95 + mids * 0.15));

    // Semantic alpha and depth
    let alpha = sat(luma(color) * 1.4 + presence * 0.35 + fog * 0.15);
    let outDepth = sat(0.85 - presence * 0.6 - fog * 0.25);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, pixel, vec4<f32>(wind, band, shimmer, alpha));
}
