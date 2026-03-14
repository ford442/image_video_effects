// ─────────────────────────────────────────────────────────────────────────────
//  Chromatic Phase Inversion
//  Category: EFFECT
//  Complexity: HIGH
//  Visual concept: Individual color channels are inverted by a slowly evolving
//    temporal phase, causing color to appear spatially offset from reality —
//    color "ghosts" that drift ahead or behind the true image.
//  Mathematical approach: Each channel's inversion is modulated by a
//    sinusoidal phase function with distinct frequencies; spatial offset
//    is computed from phase-gradient to keep coherence; depth controls
//    how much phase each region accumulates over time.
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
    zoom_params: vec4<f32>, // x=PhaseSpeed, y=GhostOffset, z=InversionDepth, w=SpatialCoherence
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  RGB → HSV
// ─────────────────────────────────────────────────────────────────────────────
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth noise for spatial phase field
// ─────────────────────────────────────────────────────────────────────────────
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(143.3, 311.7));
    q += dot(q, q + 37.1);
    return fract(q.x * q.y);
}
fn snoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y) * 2.0 - 1.0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Phase function: returns inversion weight ∈ [0,1] for a channel
//  phaseFreq: unique per channel; depthPhase: depth-accumulated extra phase
// ─────────────────────────────────────────────────────────────────────────────
fn invPhase(t: f32, freq: f32, depthPhase: f32, spatialPhase: f32) -> f32 {
    return sin(t * freq + depthPhase + spatialPhase) * 0.5 + 0.5;
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
        let wave = sin(dist * 30.0 - age * 5.0) * exp(-dist * 5.5) * exp(-age * 1.2);
        if (dist > 0.001) {
            d += normalize(uv - r.xy) * wave * (1.0 - age / 4.0) * 0.013;
        }
    }
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  FBM noise (3 octaves)
// ─────────────────────────────────────────────────────────────────────────────
fn fbm_cpi(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 3; i++) {
        v += a * snoise(pp);
        pp = pp * 2.0 + vec2<f32>(5.2, 1.3);
        a *= 0.5;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Optical aberration: barrel/pincushion lens distortion
// ─────────────────────────────────────────────────────────────────────────────
fn lensDistort(uv: vec2<f32>, k1: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    return 0.5 + centered * (1.0 + k1 * r2);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Temporal echo: blend current + previous phase positions
// ─────────────────────────────────────────────────────────────────────────────
fn temporalEcho(uv: vec2<f32>, off: vec2<f32>, t: f32, echoDelay: f32) -> vec2<f32> {
    let prevOff = off * cos(t * 0.5 - echoDelay);
    return mix(uv + off, uv + prevOff, 0.4);
}

// ─────────────────────────────────────────────────────────────────────────────
//  RGB → Luminance
// ─────────────────────────────────────────────────────────────────────────────
fn luma_cpi(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Scanline CRT overlay (subtle)
// ─────────────────────────────────────────────────────────────────────────────
fn scanlineOverlay(uv: vec2<f32>, resY: f32, strength: f32) -> f32 {
    let line = sin(uv.y * resY * 3.14159) * 0.5 + 0.5;
    return 1.0 - strength * (1.0 - line * line);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hue shift (rotate hue in HSV space)
// ─────────────────────────────────────────────────────────────────────────────
fn hueShift(c: vec3<f32>, shift: f32) -> vec3<f32> {
    let hsv = rgb2hsv(c);
    let h6 = fract(hsv.x + shift) * 6.0;
    let x  = hsv.y * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if      (h6 < 1.0) { rgb = vec3<f32>(hsv.y, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, hsv.y, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, hsv.y, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, hsv.y); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, hsv.y); }
    else               { rgb = vec3<f32>(hsv.y, 0.0, x); }
    return (rgb + (hsv.z - hsv.y)) * hsv.z;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res    = u.config.zw;
    let uv     = vec2<f32>(gid.xy) / res;
    let t      = u.config.x;

    // Parameters
    let phaseSpeed  = u.zoom_params.x * 1.5 + 0.2;     // 0.2 – 1.7
    let ghostOff    = u.zoom_params.y * 0.025;           // 0 – 0.025 UV units
    let invDepth    = u.zoom_params.z * 6.28318;         // phase scale from depth (0 – 2π)
    let coherence   = u.zoom_params.w * 0.8 + 0.1;      // 0.1 – 0.9 spatial mix

    // ── Depth at this pixel ───────────────────────────────────────────────
    let depth     = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthPhase = depth * invDepth;

    // ── Spatial phase field (smooth noise) ───────────────────────────────
    let noiseScale = 2.5;
    let spatialPh  = snoise(uv * noiseScale + vec2<f32>(t * 0.05, t * 0.04)) * 2.0;

    // ── Per-channel phase frequencies (detuned) ───────────────────────────
    let freqR = phaseSpeed * 0.71;
    let freqG = phaseSpeed * 1.00;
    let freqB = phaseSpeed * 1.41;

    let phR = invPhase(t, freqR, depthPhase, spatialPh * coherence);
    let phG = invPhase(t, freqG, depthPhase, spatialPh * coherence);
    let phB = invPhase(t, freqB, depthPhase, spatialPh * coherence);

    // ── Per-channel spatial offsets (ghost displacement) ─────────────────
    let angleR = t * freqR * 0.4 + depthPhase;
    let angleG = t * freqG * 0.4 + depthPhase + 2.094; // +120°
    let angleB = t * freqB * 0.4 + depthPhase + 4.189; // +240°

    let offR = vec2<f32>(cos(angleR), sin(angleR)) * ghostOff * phR;
    let offG = vec2<f32>(cos(angleG), sin(angleG)) * ghostOff * phG;
    let offB = vec2<f32>(cos(angleB), sin(angleB)) * ghostOff * phB;

    // ── Ripple ────────────────────────────────────────────────────────────
    let rDisp = rippleDisp(uv, t, u32(u.config.y));

    // ── Sample each channel from its offset UV ────────────────────────────
    let uvR = clamp(uv + offR + rDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + offG + rDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + offB + rDisp, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sampG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sampB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);

    // ── Phase inversion: lerp between original and (1-channel) ────────────
    let r = mix(sampR.r, 1.0 - sampR.r, phR * 0.7);
    let g = mix(sampG.g, 1.0 - sampG.g, phG * 0.5);
    let b = mix(sampB.b, 1.0 - sampB.b, phB * 0.9);

    // ── HSV-space saturation boost to keep colors vivid ───────────────────
    let hsv  = rgb2hsv(vec3<f32>(r, g, b));
    let satBoost = clamp(hsv.y * 1.3, 0.0, 1.0);
    // Reconstruct boosted RGB (simple saturation path)
    let gray = (r + g + b) / 3.0;
    let finalR = clamp(mix(gray, r, satBoost / max(hsv.y, 0.001)), 0.0, 1.0);
    let finalG = clamp(mix(gray, g, satBoost / max(hsv.y, 0.001)), 0.0, 1.0);
    let finalB = clamp(mix(gray, b, satBoost / max(hsv.y, 0.001)), 0.0, 1.0);

    // ── Lens distortion (channel-dependent barrel/pincushion) ─────────────
    let k1R = phR * 0.06 - 0.03;
    let k1B = phB * 0.06 - 0.03;
    let lensUVR = lensDistort(uvR, k1R);
    let lensUVB = lensDistort(uvB, k1B);
    let lensR = textureSampleLevel(readTexture, u_sampler,
        clamp(lensUVR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let lensB = textureSampleLevel(readTexture, u_sampler,
        clamp(lensUVB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // ── FBM-modulated halo ─────────────────────────────────────────────────
    let fbmHalo = fbm_cpi(uv * 4.0 + vec2<f32>(t * 0.03, -t * 0.02));
    let haloR = mix(finalR, 1.0 - finalR, fbmHalo * phR * 0.3);
    let haloG = finalG;
    let haloB = mix(finalB, 1.0 - finalB, fbmHalo * phB * 0.3);

    // ── Scanline overlay ──────────────────────────────────────────────────
    let scanline = scanlineOverlay(uv, res.y, 0.06);

    // ── Hue-shifted ghost layer ────────────────────────────────────────────
    let baseColor = vec3<f32>(haloR, haloG, haloB);
    let ghostHue  = hueShift(baseColor, phG * 0.25);
    let ghostBlend = (phR + phB) * 0.12;

    // ── Temporal echo on R and B ───────────────────────────────────────────
    let echoUVR = temporalEcho(uv, offR, t, 0.5);
    let echoUVB = temporalEcho(uv, offB, t, 0.7);
    let echoR   = textureSampleLevel(readTexture, u_sampler,
        clamp(echoUVR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let echoB   = textureSampleLevel(readTexture, u_sampler,
        clamp(echoUVB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    let outR = clamp(mix(haloR, lensR, 0.3) + echoR * 0.08 + ghostBlend * ghostHue.r, 0.0, 1.0) * scanline;
    let outG = clamp(haloG + ghostBlend * ghostHue.g, 0.0, 1.0) * scanline;
    let outB = clamp(mix(haloB, lensB, 0.3) + echoB * 0.08 + ghostBlend * ghostHue.b, 0.0, 1.0) * scanline;

    textureStore(writeTexture, gid.xy, vec4<f32>(outR, outG, outB, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
