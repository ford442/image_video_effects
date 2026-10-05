// ═══════════════════════════════════════════════════════════════
//  Iridescent Oil Slick - Thin-film interference simulation
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal-persistence, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: spectral Newton series (8-wavelength film, black film); finger push with memory; Marangoni cell ridges + bass thickening
//  A packing: rgb = display RGB (pre-ACES), a = 4 + finger-push disturbance 0..1 (raw, sentinel offset; C alpha outside [4,5] reads as 0)
//  Description: Creates mesmerizing oil-on-water interference patterns
//               with flowing organic motion and rainbow color shifts.
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Simplex noise functions for organic flow
fn mod289_3(x: vec3<f32>) -> vec3<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn mod289_4(x: vec4<f32>) -> vec4<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec4<f32>) -> vec4<f32> { return mod289_4(((x * 34.0) + 1.0) * x); }
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * r; }

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0 / 6.0, 1.0 / 3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);
    
    var i = floor(v + dot(v, C.yyy));
    let x0 = v - i + dot(i, C.xxx);
    
    var g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);
    
    let x1 = x0 - i1 + C.xxx;
    let x2 = x0 - i2 + C.yyy;
    let x3 = x0 - D.yyy;
    
    i = mod289_3(i);
    var p = permute(permute(permute(
        i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));
    
    let n_ = 0.142857142857;
    let ns = n_ * D.wyz - D.xzx;
    
    let j = p - 49.0 * floor(p * ns.z * ns.z);
    
    let x_ = floor(j * ns.z);
    let y_ = floor(j - 7.0 * x_);
    
    let x = x_ *ns.x + ns.yyyy;
    let y = y_ *ns.x + ns.yyyy;
    var h = 1.0 - abs(x) - abs(y);
    
    let b0 = vec4<f32>(x.xy, y.xy);
    let b1 = vec4<f32>(x.zw, y.zw);
    
    let s0 = floor(b0) * 2.0 + 1.0;
    let s1 = floor(b1) * 2.0 + 1.0;
    let sh = -step(h, vec4<f32>(0.0));
    
    let a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    let a1 = b1.xzyw + s1.xzyw * sh.zzww;
    
    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);
    
    let norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 = p0 * norm.x;
    p1 = p1 * norm.y;
    p2 = p2 * norm.z;
    p3 = p3 * norm.w;
    
    var m = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m*m, vec4<f32>(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// FBM for organic thickness variation
fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < 5; i++) {
        value += amplitude * snoise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Thin-film interference - calculates iridescent colors based on film thickness.
// Idea 1: Spectral Newton series. HEAD's phase model (4π·n·d·cosθt / λ), but integrated
// over 8 wavelengths 380–720 nm through a smooth wavelength→RGB response instead of three
// cosines. The air→oil reflection carries a π shift, so reflectance is 0.5 − 0.5·cos(δ):
// a film thinning toward 0 nm goes BLACK, the first order runs silver → gold → magenta →
// blue, and thick film averages out across the spectrum into pastels.
fn gauss_w(x: f32, mu: f32, sigma: f32) -> f32 {
    let d = (x - mu) / sigma;
    return exp(-0.5 * d * d);
}

fn wavelengthRGB(lambda: f32) -> vec3<f32> {
    return vec3<f32>(
        gauss_w(lambda, 605.0, 42.0) + 0.30 * gauss_w(lambda, 440.0, 22.0),
        gauss_w(lambda, 545.0, 45.0),
        gauss_w(lambda, 450.0, 35.0));
}

fn thinFilmInterference(thickness: f32, viewAngle: f32) -> vec3<f32> {
    // Refractive indices
    let nFilm = 1.33; // Water/oil
    let nAir = 1.0;

    // Optical path (nm) — HEAD's expression; clamp the root so a wide view angle can't NaN.
    let cosT = sqrt(max(1.0 - (nAir/nFilm) * (nAir/nFilm) * viewAngle * viewAngle, 0.0));
    let phase = 4.0 * 3.14159 * nFilm * max(thickness, 0.0) * cosT;

    var acc = vec3<f32>(0.0);
    var wsum = vec3<f32>(0.0);
    for (var k: i32 = 0; k < 8; k++) {
        let lambda = 380.0 + f32(k) * (340.0 / 7.0);
        let w = wavelengthRGB(lambda);
        let refl = 0.5 - 0.5 * cos(phase / lambda);
        acc += w * refl;
        wsum += w;
    }
    // A flat spectrum (refl = 1) normalises to white.
    return acc / max(wsum, vec3<f32>(1e-4));
}

// Rotate UV for kaleidoscope effect
fn rotateUV(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

// Hexagonal pattern for oil bubble cells
fn hexPattern(uv: vec2<f32>) -> f32 {
    var r = vec2<f32>(1.0, 1.732);
    var h = r * 0.5;
    
    var p = uv;
    
    let a = vec2<f32>(dot(p, r), p.y);
    var b = vec2<f32>(dot(p, r - h * 2.0), p.y);
    
    let ai = floor(a);
    let bi = floor(b);
    
    var v = vec2<f32>(0.0);
    var m = 1.0;
    
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let o = vec2<f32>(f32(i), f32(j));
            let d = length(a - ai - o);
            if (d < m) {
                m = d;
                v = ai + o;
            }
        }
    }
    
    return m;
}

// Idea 3 helper: distance to the nearest cell wall of hexPattern's lattice (F2 − F1 in the
// same skewed space), so walls are thin lines rather than the blobs a single F1 gives.
fn hexWall(uv: vec2<f32>) -> f32 {
    let r = vec2<f32>(1.0, 1.732);
    let a = vec2<f32>(dot(uv, r), uv.y);
    let ai = floor(a);
    var f1 = 8.0;
    var f2 = 8.0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let d = length(a - ai - vec2<f32>(f32(i), f32(j)));
            if (d < f1) { f2 = f1; f1 = d; }
            else if (d < f2) { f2 = d; }
        }
    }
    return f2 - f1;
}

// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PUSH_SENTINEL: f32 = 4.0;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let bass = plasmaBuffer[0].x;

    // Parameters
    let filmScale = mix(2.0, 8.0, u.zoom_params.x);      // Film thickness scale
    let flowSpeed = mix(0.1, 0.8, u.zoom_params.y);       // Animation speed
    let turbulence = mix(0.5, 3.0, u.zoom_params.z);      // Noise intensity
    let colorShift = u.zoom_params.w * 6.28318;           // Hue rotation

    // Aspect ratio correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // Mouse interaction - create ripples/disturbances
    let mousePos = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(p - mousePos);
    let mouseInfluence = exp(-mouseDist * 3.0) * 0.5;

    // Animated flow coordinates
    let flowNoise = vec2<f32>(
        snoise(vec3<f32>(p * 2.0, time * flowSpeed * 0.3)),
        snoise(vec3<f32>(p * 2.0 + 100.0, time * flowSpeed * 0.3))
    );
    var flowUV = p * filmScale + flowNoise * turbulence;

    // Add swirling motion
    let swirlAngle = time * flowSpeed * 0.2 + mouseInfluence * 2.0;
    flowUV = rotateUV(flowUV, swirlAngle);

    // Generate film thickness using FBM
    let thicknessBase = fbm(vec3<f32>(flowUV, time * flowSpeed * 0.1));
    let thicknessDetail = snoise(vec3<f32>(flowUV * 3.0, time * flowSpeed)) * 0.3;
    let thickness = (thicknessBase + thicknessDetail) * 0.5 + 0.5;

    // Add hexagonal cell variation for bubble effect
    let hex = hexPattern(flowUV * 2.0);
    let cellVariation = smoothstep(0.3, 0.0, hex) * 0.2;

    // Idea 3: Marangoni cells — surface-tension flow piles oil up against the cell walls,
    // so each wall is a thickness ridge that carries its own interference bands.
    let wall = 1.0 - smoothstep(0.0, 0.16, hexWall(flowUV * 2.0));
    let ridge = wall * 0.22;

    // Final thickness with all contributions; bass slightly thickens the film.
    let finalThickness = (thickness * (1.0 + cellVariation) + mouseInfluence * 0.3 + ridge) * (1.0 + bass * 0.15);

    // Idea 2: Finger push with memory. Holding the mouse pushes the oil outward: a
    // black-film disc under the finger and a thickened rainbow rim. The disturbance lives
    // in A.a, decays, and drifts with the flow (exact C load at the upstream texel).
    let dimsC = vec2<i32>(textureDimensions(dataTextureC));
    let drift = flowNoise * flowSpeed * 0.0025;
    // Texel-centre + floor: truncating gid/res*dims - drift biased every tiny positive drift
    // (and float round-down at zero drift) to the previous texel → 1 px/frame creep.
    let upPix = (uv + 0.5 / resolution - drift) * vec2<f32>(dimsC);
    let upCoord = clamp(vec2<i32>(floor(upPix)), vec2<i32>(0), dimsC - vec2<i32>(1));
    let prevRaw = textureLoad(dataTextureC, upCoord, 0).a - PUSH_SENTINEL;
    // All-zero C (first frame) or another shader's alpha after a switch decode as no push.
    let prevPush = select(0.0, prevRaw, (prevRaw >= 0.0) && (prevRaw <= 1.0));
    let fingerR = 0.06;
    let disc = select(0.0, smoothstep(fingerR, fingerR * 0.35, mouseDist), mouseDown);
    let push = clamp(max(prevPush * 0.992, disc), 0.0, 1.0);
    let blackFilm = smoothstep(0.55, 0.95, push);
    let rim = 4.0 * push * (1.0 - push);

    // Calculate view angle (simplified - assume looking from above with slight tilt)
    let viewAngle = length(p) * 0.3;

    // Get iridescent color from thin-film interference (Idea 1: spectral, black film at 0 nm)
    let filmNm = (finalThickness * 500.0 + 100.0) * (1.0 - blackFilm) + rim * 220.0;
    let film = thinFilmInterference(filmNm, viewAngle);
    let filmLuma = dot(film, vec3<f32>(0.299, 0.587, 0.114));
    // The spectral average is less saturated than three pure cosines; restore some vividness.
    var color = max(mix(vec3<f32>(filmLuma), film, 1.35), vec3<f32>(0.0));

    // Apply color shift
    let hueRotation = colorShift + time * flowSpeed * 0.1;
    let cosH = cos(hueRotation);
    let sinH = sin(hueRotation);
    let hueMatrix = mat3x3<f32>(
        vec3<f32>(0.299 + 0.701 * cosH + 0.168 * sinH, 0.587 - 0.587 * cosH + 0.330 * sinH, 0.114 - 0.114 * cosH - 0.497 * sinH),
        vec3<f32>(0.299 - 0.299 * cosH - 0.328 * sinH, 0.587 + 0.413 * cosH + 0.035 * sinH, 0.114 - 0.114 * cosH + 0.292 * sinH),
        vec3<f32>(0.299 - 0.300 * cosH + 1.250 * sinH, 0.587 - 0.588 * cosH - 1.050 * sinH, 0.114 + 0.886 * cosH - 0.203 * sinH)
    );
    color = hueMatrix * color;

    // Add specular highlight for wet/oily look
    let highlightPos = rotateUV(p, time * flowSpeed * 0.1) * 2.0;
    let highlight = pow(max(0.0, 1.0 - length(highlightPos)), 3.0) * 0.3;
    color += vec3<f32>(highlight);

    // Add subtle vignette
    let vignette = 1.0 - length(p) * 0.4;
    color *= vignette;

    // Boost contrast and saturation.
    // Floor fix: the hue matrix produces negatives and pow(negative, 0.8) is NaN — clamp first.
    color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(0.8));
    color = color * 1.2;

    // A: display RGB (pre-ACES) + raw finger-push disturbance for next frame.
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, PUSH_SENTINEL + push));

    // Output: ACES display (exposure keeps HEAD's clamp-era brightness); alpha = film
    // reflectance coverage — black film transmits, so it reads as partly transparent.
    let alpha = mix(0.6, 1.0, smoothstep(0.02, 0.3, filmLuma));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces_tonemap(color * 1.35), alpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
