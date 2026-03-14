// ─────────────────────────────────────────────────────────────────────────────
//  Spectral Bleed & Confinement
//  Category: EFFECT
//  Complexity: HIGH
//  Visual concept: Specific color bands leak outward from edges while being
//    electromagnetically confined by competing channels, creating glowing
//    halos that feel physically constrained — like color plasma trapped by
//    invisible magnetic fields.
//  Mathematical approach: Per-channel "bleed" is computed from luminance-edge
//    maps; each channel's spread is convolved with a directional kernel;
//    confinement is a cross-channel suppression term (R suppresses B bleed,
//    G suppresses R bleed, etc.) modulated by a slow curl-noise vector field.
// ─────────────────────────────────────────────────────────────────────────────
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
    config:      vec4<f32>, // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=unused, y=MouseX, z=MouseY, w=unused
    zoom_params: vec4<f32>, // x=BleedRadius, y=ConfinementStrength, z=CurlSpeed, w=EdgeThreshold
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth value noise
// ─────────────────────────────────────────────────────────────────────────────
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Curl-noise 2-D vector field
//  ∇⊥ of a scalar potential → divergence-free field
// ─────────────────────────────────────────────────────────────────────────────
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.002;
    let n0  = vnoise(p + vec2<f32>(eps, 0.0));
    let n1  = vnoise(p - vec2<f32>(eps, 0.0));
    let n2  = vnoise(p + vec2<f32>(0.0, eps));
    let n3  = vnoise(p - vec2<f32>(0.0, eps));
    let dNdY = (n2 - n3) / (2.0 * eps);
    let dNdX = (n0 - n1) / (2.0 * eps);
    return vec2<f32>(dNdY, -dNdX);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edge-magnitude: Sobel on single channel
// ─────────────────────────────────────────────────────────────────────────────
fn sobelEdge(uv: vec2<f32>, tx: vec2<f32>, ch: i32) -> f32 {
    fn sc(off: vec2<f32>, c: i32) -> f32 {
        let s = textureSampleLevel(readTexture, u_sampler,
                    clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        if (c == 0) { return s.r; }
        else if (c == 1) { return s.g; }
        return s.b;
    }
    let gx = -sc(vec2<f32>(-tx.x,  tx.y), ch) + sc(vec2<f32>(tx.x,  tx.y), ch)
             -sc(vec2<f32>(-tx.x, 0.0), ch) * 2.0 + sc(vec2<f32>(tx.x, 0.0), ch) * 2.0
             -sc(vec2<f32>(-tx.x, -tx.y), ch) + sc(vec2<f32>(tx.x, -tx.y), ch);
    let gy = sc(vec2<f32>(-tx.x, tx.y), ch) + sc(vec2<f32>(0.0, tx.y), ch) * 2.0 + sc(vec2<f32>(tx.x, tx.y), ch)
             -sc(vec2<f32>(-tx.x, -tx.y), ch) - sc(vec2<f32>(0.0, -tx.y), ch) * 2.0 - sc(vec2<f32>(tx.x, -tx.y), ch);
    return length(vec2<f32>(gx, gy)) * 0.125;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Directional bleed: sample average of channel along curl-field direction
// ─────────────────────────────────────────────────────────────────────────────
fn channelBleed(uv: vec2<f32>, dir: vec2<f32>, radius: f32, ch: i32) -> f32 {
    var accum = 0.0;
    let steps = 6;
    for (var s = 1; s <= steps; s++) {
        let off  = dir * radius * f32(s) / f32(steps);
        let suv  = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
        let samp = textureSampleLevel(readTexture, u_sampler, suv, 0.0);
        let w    = 1.0 - f32(s) / f32(steps + 1);
        if (ch == 0) { accum += samp.r * w; }
        else if (ch == 1) { accum += samp.g * w; }
        else { accum += samp.b * w; }
    }
    return accum * 2.0 / f32(steps);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ripple accumulation
// ─────────────────────────────────────────────────────────────────────────────
fn rippleDisp(uv: vec2<f32>, t: f32, cnt: u32) -> vec2<f32> {
    var d = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < cnt; i++) {
        let r   = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let dist = distance(uv, r.xy);
        let wave = sin(dist * 32.0 - age * 5.5) * exp(-dist * 5.0) * exp(-age * 1.3);
        if (dist > 0.001) { d += normalize(uv - r.xy) * wave * (1.0 - age / 4.0) * 0.012; }
    }
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  FBM curl noise (2 octaves)
// ─────────────────────────────────────────────────────────────────────────────
fn curlFBM(p: vec2<f32>) -> vec2<f32> {
    var c = curlNoise(p);
    c    += curlNoise(p * 2.0 + vec2<f32>(1.7, 3.1)) * 0.5;
    return normalize(c + vec2<f32>(0.001));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Electromagnetic field strength (channel interference pattern)
// ─────────────────────────────────────────────────────────────────────────────
fn emFieldStrength(p: vec2<f32>, t: f32, freq: f32) -> f32 {
    return sin(p.x * freq + t) * cos(p.y * freq * 0.87 - t * 1.1) * 0.5 + 0.5;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spectral line broadening (convolution approximation)
// ─────────────────────────────────────────────────────────────────────────────
fn spectralBroadening(uv: vec2<f32>, dir: vec2<f32>, radius: f32, ch: i32) -> f32 {
    var accum = 0.0;
    var wSum  = 0.0;
    let steps = 5;
    for (var s = -steps; s <= steps; s++) {
        let off = dir * radius * f32(s) / f32(steps);
        let suv = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
        let samp = textureSampleLevel(readTexture, u_sampler, suv, 0.0);
        let w = exp(-f32(s * s) * 0.4);
        wSum += w;
        if (ch == 0) { accum += samp.r * w; }
        else if (ch == 1) { accum += samp.g * w; }
        else { accum += samp.b * w; }
    }
    return accum / max(wSum, 0.001);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Plasma confinement potential (Lorentz-like cross-product force)
// ─────────────────────────────────────────────────────────────────────────────
fn lorentzConfinement(bleedR: f32, bleedG: f32, bleedB: f32, strength: f32) -> vec3<f32> {
    // v × B cross product in color space: R deflects G, G deflects B, B deflects R
    return vec3<f32>(
        exp(-bleedG * bleedB * strength),
        exp(-bleedB * bleedR * strength),
        exp(-bleedR * bleedG * strength)
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    let uv    = vec2<f32>(gid.xy) / res;
    let t     = u.config.x;
    let tx    = 1.0 / res;

    // Parameters
    let bleedRadius   = u.zoom_params.x * 0.025 + 0.004; // 0.004 – 0.029
    let confinement   = u.zoom_params.y * 2.0 + 0.5;     // 0.5 – 2.5
    let curlSpeed     = u.zoom_params.z * 0.4 + 0.05;    // 0.05 – 0.45
    let edgeThresh    = u.zoom_params.w * 0.3 + 0.02;    // 0.02 – 0.32

    // ── Curl-noise field ──────────────────────────────────────────────────
    let curlUV  = uv * 2.5 + vec2<f32>(t * curlSpeed, t * curlSpeed * 0.6);
    let curl    = normalize(curlNoise(curlUV) + vec2<f32>(0.001));

    // ── Per-channel bleed directions (120° apart, modulated by curl) ──────
    let a0 = atan2(curl.y, curl.x);
    let dirR = vec2<f32>(cos(a0),               sin(a0));
    let dirG = vec2<f32>(cos(a0 + 2.094),       sin(a0 + 2.094));
    let dirB = vec2<f32>(cos(a0 + 4.189),       sin(a0 + 4.189));

    // ── Edge masks ───────────────────────────────────────────────────────
    let edgeR = smoothstep(edgeThresh * 0.5, edgeThresh, sobelEdge(uv, tx, 0));
    let edgeG = smoothstep(edgeThresh * 0.5, edgeThresh, sobelEdge(uv, tx, 1));
    let edgeB = smoothstep(edgeThresh * 0.5, edgeThresh, sobelEdge(uv, tx, 2));

    // ── Compute bleed amounts per channel ─────────────────────────────────
    let bleedR = channelBleed(uv + rippleDisp(uv, t, u32(u.config.y)), dirR, bleedRadius, 0) * edgeR;
    let bleedG = channelBleed(uv + rippleDisp(uv, t, u32(u.config.y)), dirG, bleedRadius, 1) * edgeG;
    let bleedB = channelBleed(uv + rippleDisp(uv, t, u32(u.config.y)), dirB, bleedRadius, 2) * edgeB;

    // ── Original color ────────────────────────────────────────────────────
    let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // ── Composite: original + confined bleed halo ─────────────────────────
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── FBM curl for richer bleed direction ───────────────────────────────
    let curlFBMUV = uv * 3.0 + vec2<f32>(t * curlSpeed * 0.7, t * curlSpeed * 0.5);
    let curlF = curlFBM(curlFBMUV);
    let a0fbm = atan2(curlF.y, curlF.x);
    let dirRF = vec2<f32>(cos(a0fbm),               sin(a0fbm));
    let dirGF = vec2<f32>(cos(a0fbm + 2.094),       sin(a0fbm + 2.094));
    let dirBF = vec2<f32>(cos(a0fbm + 4.189),       sin(a0fbm + 4.189));

    // ── Spectral broadening (Gaussian-convolved bleed) ─────────────────────
    let broadR = spectralBroadening(uv, dirRF, bleedRadius * 0.6, 0) * edgeR;
    let broadG = spectralBroadening(uv, dirGF, bleedRadius * 0.6, 1) * edgeG;
    let broadB = spectralBroadening(uv, dirBF, bleedRadius * 0.6, 2) * edgeB;

    // ── EM field modulation ────────────────────────────────────────────────
    let emR = emFieldStrength(uv * 8.0, t, 4.0) * edgeR;
    let emG = emFieldStrength(uv * 8.0 + vec2<f32>(2.1, 0.0), t, 5.0) * edgeG;
    let emB = emFieldStrength(uv * 8.0 + vec2<f32>(0.0, 3.3), t, 3.7) * edgeB;

    // ── Lorentz confinement (plasma physics-inspired) ──────────────────────
    let lorentz = lorentzConfinement(bleedR + broadR, bleedG + broadG, bleedB + broadB, confinement);

    // ── Confinement: each channel suppresses the next channel's bleed ─────
    let confR = exp(-bleedG * confinement) * lorentz.r;
    let confG = exp(-bleedB * confinement) * lorentz.g;
    let confB = exp(-bleedR * confinement) * lorentz.b;

    let depthBoost = 0.5 + depth * 0.8;

    let r = clamp(orig.r + (bleedR + broadR * 0.5) * confR * depthBoost + emR * bleedRadius * 0.3, 0.0, 1.0);
    let g = clamp(orig.g + (bleedG + broadG * 0.5) * confG * depthBoost + emG * bleedRadius * 0.3, 0.0, 1.0);
    let b = clamp(orig.b + (bleedB + broadB * 0.5) * confB * depthBoost + emB * bleedRadius * 0.3, 0.0, 1.0);

    // ── Saturation boost: keep bleed vivid against original ───────────────
    // Amplify chroma slightly to counter the washing effect of bleed accumulation
    let lum   = r * 0.2126 + g * 0.7152 + b * 0.0722;
    let satBoost = 1.0 + confinement * 0.08;
    let outR  = clamp(mix(lum, r, satBoost), 0.0, 1.0);
    let outG  = clamp(mix(lum, g, satBoost), 0.0, 1.0);
    let outB  = clamp(mix(lum, b, satBoost), 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(outR, outG, outB, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
