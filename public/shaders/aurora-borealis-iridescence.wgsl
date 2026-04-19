// ═══════════════════════════════════════════════════════════════════
//  aurora-borealis-iridescence
//  Category: advanced-hybrid
//  Features: aurora-ribbons, thin-film-interference, curl-noise
//  Complexity: Very High
//  Chunks From: aurora_borealis.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Northern lights with flowing ribbon curves enhanced by thin-film
//  iridescence. Each aurora ribbon shimmers with soap-bubble and
//  oil-slick interference colors driven by ribbon intensity and
//  animated turbulence, creating a spectral dance in the night sky.
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

// ═══ CHUNK: hash (from aurora_borealis.wgsl) ═══
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    return fract((q.x + q.y) * q.z);
}

// ═══ CHUNK: curl noise (from aurora_borealis.wgsl) ═══
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n = hash3(vec3<f32>(p, time * 0.1));
    let nx = hash3(vec3<f32>(p + vec2<f32>(eps, 0.0), time * 0.1));
    let ny = hash3(vec3<f32>(p + vec2<f32>(0.0, eps), time * 0.1));
    return vec2<f32>(ny - n, n - nx) / eps;
}

// ═══ CHUNK: aurora ribbon (from aurora_borealis.wgsl) ═══
fn auroraRibbon(x: f32, t: f32, ribbonId: f32) -> vec2<f32> {
    let freq1 = 1.0 + ribbonId * 0.5;
    let freq2 = 2.0 + ribbonId * 0.3;
    let y1 = sin(x * freq1 * PI * 2.0 + t * 0.3) * 0.15;
    let y2 = sin(x * freq2 * PI * 2.0 + t * 0.5 + ribbonId) * 0.1;
    return vec2<f32>(x, 0.5 + y1 + y2);
}

// ═══ CHUNK: aurora color (from aurora_borealis.wgsl) ═══
fn auroraColor(height: f32, intensity: f32) -> vec3<f32> {
    let green = vec3<f32>(0.2, 0.9, 0.4);
    let red = vec3<f32>(0.9, 0.3, 0.2);
    let purple = vec3<f32>(0.6, 0.2, 0.8);
    var color: vec3<f32>;
    if (height < 0.3) {
        color = green;
    } else if (height < 0.6) {
        color = mix(green, red, (height - 0.3) / 0.3);
    } else {
        color = mix(red, purple, (height - 0.6) / 0.4);
    }
    return color * intensity;
}

// ═══ CHUNK: stars (from aurora_borealis.wgsl) ═══
fn stars(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let starUV = uv * 100.0;
    let starHash = hash2(floor(starUV));
    let star = step(0.99, starHash);
    let twinkle = sin(time * 3.0 + starHash * 10.0) * 0.5 + 0.5;
    return vec3<f32>(star * twinkle);
}

// ═══ CHUNK: thin-film interference (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (f32(coord.x) >= res.x || f32(coord.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Parameters
    let numRibbons = i32(3.0 + u.zoom_params.x * 5.0);
    let flowSpeed = 0.2 + u.zoom_params.y * 0.5;
    let ribbonWidth = 0.02 + u.zoom_params.z * 0.05;
    let glowIntensity = 0.5 + u.zoom_params.w;

    let filmIOR = mix(1.2, 2.4, u.zoom_params.z);
    let iridIntensity = mix(0.3, 1.2, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;

    // Night sky background
    let nightSky = vec3<f32>(0.02, 0.03, 0.08);
    let starField = stars(uv, time);
    var accumRGB = nightSky + starField * 0.5;
    var accumAlpha = 0.0;

    let mouseInfluence = smoothstep(0.5, 0.0, length(uv - mousePos));

    // Draw aurora ribbons
    for (var i: i32 = 0; i < numRibbons; i = i + 1) {
        let fi = f32(i);
        let ribbonBase = auroraRibbon(uv.x, time * flowSpeed, fi);
        let curl = curlNoise(vec2<f32>(uv.x * 2.0, time * 0.2), time);
        var ribbonPos = ribbonBase + curl * 0.1 * (1.0 + audioPulse);
        let toMouse = mousePos - ribbonPos;
        ribbonPos += toMouse * mouseInfluence * 0.2;

        let dist = abs(uv.y - ribbonPos.y);
        let ribbonShape = smoothstep(ribbonWidth * (1.0 + fi * 0.3), 0.0, dist);

        let intensity = (sin(uv.x * 10.0 + fi + time) * 0.5 + 0.5) *
                        (1.0 + audioPulse * sin(time * 5.0 + fi));

        let height = (uv.y - 0.3) / 0.4;
        let color = auroraColor(height, intensity * glowIntensity);

        let glow = smoothstep(ribbonWidth * 3.0, ribbonWidth, dist) * glowIntensity * 0.5;

        // ═══ Thin-film iridescence on ribbon ═══
        let toCenter = uv - vec2<f32>(0.5);
        let viewDist = length(toCenter);
        let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));

        let noiseVal = hash2(uv * 12.0 + time * 0.1 + fi) * 0.5
                     + hash2(uv * 25.0 - time * 0.15 + fi * 2.0) * 0.25;
        let filmThicknessBase = mix(300.0, 700.0, intensity);
        var thickness = filmThicknessBase * (0.7 + ribbonShape * 0.6 + noiseVal * 0.3);

        let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;

        // Fresnel blend
        let fresnel = pow(1.0 - cosTheta, 3.0);
        let blendedColor = mix(color, iridescent, fresnel * 0.6 * ribbonShape);

        let contribution = blendedColor * (ribbonShape + glow);
        let alpha = ribbonShape * 0.8 + glow * 0.3;

        accumRGB += contribution * (1.0 - accumAlpha);
        accumAlpha = min(accumAlpha + alpha, 1.0);
    }

    // Horizontal curtain effect
    let curtain = sin(uv.y * 50.0 + time * 0.3) * 0.5 + 0.5;
    accumRGB *= 0.8 + curtain * 0.2;

    // Tone mapping
    accumRGB = accumRGB / (1.0 + accumRGB * 0.3);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;

    textureStore(writeTexture, coord, vec4<f32>(accumRGB * vignette, accumAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(accumAlpha, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(accumRGB, accumAlpha));
}
