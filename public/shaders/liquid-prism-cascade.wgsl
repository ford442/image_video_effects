// ─────────────────────────────────────────────────────────────────────────────
//  Liquid Prism Cascade
//  Category: EFFECT
//  Complexity: HIGH
//  Visual concept: Colors separate along curved planes like light through prisms,
//    creating a layered 3-D depth illusion where each channel drifts independently.
//  Mathematical approach: Per-channel UV warping with curved dispersion vectors
//    derived from local luminance gradient + depth curvature; ripple-modulated
//    prismatic offset; HSV twist layer composited additively.
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
    zoom_params: vec4<f32>, // x=DispersionStrength, y=CurvatureScale,
                             // z=PrismTwist, w=DepthWeight
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Luminance
// ─────────────────────────────────────────────────────────────────────────────
fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ─────────────────────────────────────────────────────────────────────────────
//  2-D hash for micro-noise
// ─────────────────────────────────────────────────────────────────────────────
fn hash2f(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth value noise (2-D)
// ─────────────────────────────────────────────────────────────────────────────
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2f(i + vec2<f32>(0.0, 0.0)), hash2f(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2f(i + vec2<f32>(0.0, 1.0)), hash2f(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Prismatic dispersion offset for a given channel index (0=R, 1=G, 2=B)
//  Simulates Cauchy dispersion: shorter wavelengths bend more.
// ─────────────────────────────────────────────────────────────────────────────
fn prismOffset(channel: i32, grad: vec2<f32>, strength: f32, twist: f32, t: f32) -> vec2<f32> {
    // Wavelength weights: red bends least, blue most
    let wl = array<f32, 3>(0.6, 1.0, 1.5);
    let w = wl[channel];
    // Rotate gradient slightly per channel + time
    let angle = (f32(channel) - 1.0) * twist + t * 0.1;
    let cs = cos(angle);
    let sn = sin(angle);
    let rotGrad = vec2<f32>(cs * grad.x - sn * grad.y, sn * grad.x + cs * grad.y);
    return rotGrad * strength * w * 0.018;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Accumulate ripple displacement
// ─────────────────────────────────────────────────────────────────────────────
fn rippleDisp(uv: vec2<f32>, t: f32, rippleCount: u32) -> vec2<f32> {
    var disp = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let d = distance(uv, r.xy);
        let wave = sin(d * 40.0 - age * 6.0) * exp(-d * 5.0) * exp(-age * 1.2);
        let env = (1.0 - age / 4.0);
        if (d > 0.001) {
            disp += normalize(uv - r.xy) * wave * env * 0.012;
        }
    }
    return disp;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fractional Brownian Motion (4 octaves)
// ─────────────────────────────────────────────────────────────────────────────
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * vnoise(pp);
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spectral Cauchy dispersion coefficient for wavelength λ (nm, normalized)
//  Cauchy: n(λ) = A + B/λ²
// ─────────────────────────────────────────────────────────────────────────────
fn cauchyN(lambda: f32, A: f32, B: f32) -> f32 {
    return A + B / (lambda * lambda + 0.01);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Chromatic aberration angle from index of refraction difference
// ─────────────────────────────────────────────────────────────────────────────
fn chromaticAngle(nDiff: f32, incidence: f32) -> f32 {
    return asin(clamp(sin(incidence) / (nDiff + 1.0), -1.0, 1.0));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hue-preserving tone mapping
// ─────────────────────────────────────────────────────────────────────────────
fn toneMap(c: vec3<f32>) -> vec3<f32> {
    let lum = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let mapped = lum / (lum + 1.0);
    return c * (mapped / max(lum, 0.001));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Soft-light blend mode
// ─────────────────────────────────────────────────────────────────────────────
fn softLight(base: vec3<f32>, blend: vec3<f32>) -> vec3<f32> {
    return mix(
        2.0 * base * blend + base * base * (1.0 - 2.0 * blend),
        2.0 * base * (1.0 - blend) + sqrt(base) * (2.0 * blend - 1.0),
        step(0.5, blend)
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
    let dispStrength = u.zoom_params.x * 2.0 + 0.3;    // 0.3 – 2.3
    let curvScale    = u.zoom_params.y * 3.0 + 0.5;    // 0.5 – 3.5
    let prismTwist   = u.zoom_params.z * 3.14159;       // 0 – π
    let depthWeight  = u.zoom_params.w;                  // 0 – 1

    // ── Luminance gradient (finite differences) ───────────────────────────
    let lumC  = luma(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
    let lumR  = luma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(tx.x, 0.0), 0.0).rgb);
    let lumL  = luma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(tx.x, 0.0), 0.0).rgb);
    let lumU  = luma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, tx.y), 0.0).rgb);
    let lumD  = luma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, tx.y), 0.0).rgb);
    let lumGrad = vec2<f32>(lumR - lumL, lumU - lumD);

    // ── Depth curvature ───────────────────────────────────────────────────
    let depth  = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(tx.x * 2.0, 0.0), 0.0).r;
    let depthL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(tx.x * 2.0, 0.0), 0.0).r;
    let depthU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, tx.y * 2.0), 0.0).r;
    let depthD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, tx.y * 2.0), 0.0).r;
    let depthCurv = vec2<f32>(depthR - depthL, depthU - depthD) * curvScale;

    // Combined gradient (luminance + depth curvature)
    let grad = lumGrad + depthCurv * depthWeight;

    // ── Slow curved warp via noise ─────────────────────────────────────────
    let noiseUV   = uv * 3.5 + vec2<f32>(t * 0.04, t * 0.03);
    let noiseBend = (vnoise(noiseUV) - 0.5) * 0.007;
    let bentGrad  = grad + vec2<f32>(noiseBend, noiseBend * 0.7);

    // ── Ripple displacement ───────────────────────────────────────────────
    let ripples = rippleDisp(uv, t, u32(u.config.y));

    // ── Per-channel prismatic sampling ────────────────────────────────────
    var rgb: array<f32, 3>;
    for (var ch = 0; ch < 3; ch++) {
        let off  = prismOffset(ch, bentGrad, dispStrength, prismTwist, t);
        let sUV  = clamp(uv + off + ripples, vec2<f32>(0.0), vec2<f32>(1.0));
        let col  = textureSampleLevel(readTexture, u_sampler, sUV, 0.0);
        if (ch == 0) { rgb[0] = col.r; }
        else if (ch == 1) { rgb[1] = col.g; }
        else { rgb[2] = col.b; }
    }

    // ── Prismatic glow: add a faint additive halo in the dispersion direction
    let glowAmt = length(bentGrad) * 0.6;
    let glowR = textureSampleLevel(readTexture, u_sampler,
        clamp(uv + bentGrad * 0.03 + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let glowB = textureSampleLevel(readTexture, u_sampler,
        clamp(uv - bentGrad * 0.03 + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var outColor = vec4<f32>(
        clamp(rgb[0] + glowR * glowAmt * 0.15, 0.0, 1.0),
        clamp(rgb[1], 0.0, 1.0),
        clamp(rgb[2] + glowB * glowAmt * 0.15, 0.0, 1.0),
        1.0
    );

    // ── FBM-modulated prismatic shimmer ───────────────────────────────────
    let fbmVal  = fbm(uv * 6.0 + vec2<f32>(t * 0.02, -t * 0.015));
    let shimmer = fbmVal * 0.04 * dispStrength;
    let shimmerColor = vec3<f32>(
        shimmer * sin(t + 0.0) * 0.5 + 0.5,
        shimmer * sin(t + 2.094) * 0.5 + 0.5,
        shimmer * sin(t + 4.189) * 0.5 + 0.5
    );

    // ── Cauchy dispersion enhancement ─────────────────────────────────────
    let nR = cauchyN(0.65, 1.45, 0.01);
    let nB = cauchyN(0.45, 1.45, 0.01);
    let cauchyDisp = (nB - nR) * length(bentGrad) * dispStrength * 0.02;
    let cauchyShift = vec2<f32>(cos(t * 0.1), sin(t * 0.1)) * cauchyDisp;
    let extraR = textureSampleLevel(readTexture, u_sampler,
        clamp(uv + cauchyShift + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let extraB = textureSampleLevel(readTexture, u_sampler,
        clamp(uv - cauchyShift + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // ── Tone-mapped composite with shimmer ────────────────────────────────
    let prismFinal = toneMap(vec3<f32>(
        clamp(outColor.r * 0.85 + extraR * 0.15 + shimmerColor.r, 0.0, 1.0),
        clamp(outColor.g + shimmerColor.g, 0.0, 1.0),
        clamp(outColor.b * 0.85 + extraB * 0.15 + shimmerColor.b, 0.0, 1.0)
    ));
    outColor = vec4<f32>(softLight(outColor.rgb, prismFinal) * 0.6 + prismFinal * 0.4, 1.0);

    // ── Edge vignette darkening for depth of field feel ───────────────────
    // Smooth radial falloff keeps focal center bright while darkening corners.
    // Combined with prismatic shimmer this creates a focused-lens aesthetic.
    let edgeDist = length(uv - vec2<f32>(0.5));
    let vignette = 1.0 - smoothstep(0.35, 0.85, edgeDist) * 0.4;
    outColor = vec4<f32>(outColor.rgb * vignette, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(clamp(outColor.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
