// ═══════════════════════════════════════════════════════════════════
//  Gravity Lens
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: inverted counter-image inside the Einstein radius; photon ring at the shadow edge; dark-matter sub-halo microlensing caustics
//  A packing: raw lens fields (impact b, potential, ringGlow, |deflection|) — no C reader
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=LensMass, y=RingWidth, z=Chromatic, w=DarkMatter

const TAU: f32 = 6.28318530717958647;
const SUBHALOS: i32 = 5;

// Planck blackbody temperature (1000K–20000K) → linear RGB approximation
fn blackbody(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 20000.0);
    var r: f32; var g: f32; var b: f32;
    if (t <= 6600.0) {
        r = 1.0;
        let lT = log(t / 100.0);
        g = clamp((99.47 * lT - 161.12) / 255.0, 0.0, 1.0);
        b = select(0.0, clamp((138.52 * log(max(t / 100.0 - 10.0, 1.0)) - 305.04) / 255.0, 0.0, 1.0), t > 2000.0);
    } else {
        let lt = t / 100.0 - 60.0;   // > 6 on this branch, so pow bases stay positive
        r = clamp(329.70 * pow(lt, -0.1332) / 255.0, 0.0, 1.0);
        g = clamp(288.12 * pow(lt, -0.0755) / 255.0, 0.0, 1.0);
        b = 1.0;
    }
    return vec3<f32>(r, g, b);
}

fn hash11(n: f32) -> f32 {
    return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Point-lens equation β = θ − θE²/θ, evaluated in aspect space around the lens.
// Outside θE this is the primary image (pulled toward the lens, never off-frame);
// inside θE β flips sign, which is the inverted counter-image.
fn lensSource(lp: vec2<f32>, delta: vec2<f32>, b: f32, thetaE: f32, micro: vec2<f32>) -> vec2<f32> {
    let bSafe = max(b, 1e-4);
    let beta = delta * (1.0 - thetaE * thetaE / (bSafe * bSafe)) - micro;
    return lp + beta;
}

fn toUV(pAspect: vec2<f32>, aspect: f32) -> vec2<f32> {
    return clamp(vec2<f32>(pAspect.x / aspect, pAspect.y), vec2<f32>(0.001), vec2<f32>(0.999));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv      = vec2<f32>(global_id.xy) / resolution;
    let time    = u.config.x;
    let aspect  = resolution.x / resolution.y;
    let bass    = plasmaBuffer[0].x;
    let mids    = plasmaBuffer[0].y;

    // Lens positioned at mouse; default to centre
    var lensPos = u.zoom_config.yz;
    if (lensPos.x <= 0.0 && lensPos.y <= 0.0) { lensPos = vec2<f32>(0.5, 0.5); }

    // Parameters
    let lensMass  = mix(0.002, 0.09, u.zoom_params.x) * (1.0 + bass * 0.35);
    let ringWidth = mix(0.002, 0.025, u.zoom_params.y);
    let chromatic = u.zoom_params.z;
    let darkParam = u.zoom_params.w;

    // Aspect-corrected impact parameter
    let p  = vec2<f32>(uv.x * aspect, uv.y);
    let lp = vec2<f32>(lensPos.x * aspect, lensPos.y);
    let delta = p - lp;
    let b     = length(delta);
    let bDir  = select(vec2<f32>(1.0, 0.0), delta / max(b, 1e-4), b > 0.0001);

    // Schwarzschild quantities
    let rs           = lensMass;                  // Schwarzschild radius (normalised screen units)
    let photonSphere = rs * 1.5;                  // Photon orbit
    let einsteinR    = sqrt(rs * 0.5);            // Einstein ring radius θE

    // Idea 3: dark-matter sub-halo microlensing — a few hashed clumps orbit on
    // the halo; each is a tiny point lens (θk²/d) whose own micro Einstein ring
    // is a shimmering caustic.
    let haloR = einsteinR * 2.5;
    var micro = vec2<f32>(0.0);
    var caustic = 0.0;
    for (var k: i32 = 0; k < SUBHALOS; k = k + 1) {
        let fk = f32(k);
        let ang = hash11(fk) * TAU + time * (0.04 + 0.05 * hash11(fk + 7.0)) * select(-1.0, 1.0, k % 2 == 0);
        let rad = haloR * (0.55 + 0.7 * hash11(fk + 13.0));
        let cpos = lp + vec2<f32>(cos(ang), sin(ang)) * rad;
        let thetaK = einsteinR * darkParam * (0.10 + 0.06 * hash11(fk + 29.0)) * (1.0 + 0.25 * sin(time * 1.3 + fk * 2.1));
        let dk = p - cpos;
        let dl = length(dk);
        let dSafe = max(dl, thetaK * 0.3 + 1e-4);
        micro = micro + dk / dSafe * (thetaK * thetaK / dSafe);
        let cw = max(thetaK * 0.25, 1e-4);
        caustic = caustic + exp(-(dl - thetaK) * (dl - thetaK) / (cw * cw));
    }

    // Floor fix: point-lens deflection α = θE²/b (HEAD had an extra 1/b, so most
    // of the frame sampled clamped edges). Chromatic = 0 is neutral RGB.
    let thetaR = einsteinR * (1.0 - chromatic * 0.03);
    let thetaG = einsteinR;
    let thetaB = einsteinR * (1.0 + chromatic * 0.05);
    let deflectMag = einsteinR * einsteinR / max(b, 1e-4);

    let sR = textureSampleLevel(readTexture, u_sampler, toUV(lensSource(lp, delta, b, thetaR, micro), aspect), 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, toUV(lensSource(lp, delta, b, thetaG, micro), aspect), 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, toUV(lensSource(lp, delta, b, thetaB, micro), aspect), 0.0);
    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Idea 1: secondary counter-image — inside θE the lens equation flips β, so
    // this region shows the inverted second image of what sits behind the hole.
    // The counter-image is demagnified, so it carries less flux: dim it gently
    // and the Einstein ring becomes a seam between two copies of the photo.
    let inner = 1.0 - smoothstep(einsteinR * 0.92, einsteinR, b);
    color = color * mix(1.0, 0.72, inner);

    // Gravitational redshift: deeper in potential → warmer colour temperature
    let potential = rs / max(b, rs * 0.1);
    let redshift  = clamp(potential * 2.0, 0.0, 1.0);
    let T_apparent = mix(8500.0, 2400.0, redshift);
    let bbShift    = blackbody(T_apparent);
    color = mix(color, color * bbShift, redshift * 0.65);

    // Einstein ring glow — constructive interference of all lensed light paths
    let ringDist = abs(b - einsteinR);
    let ringGlow = exp(-ringDist * ringDist / (ringWidth * ringWidth)) * (0.9 + mids * 0.6);
    color += blackbody(mix(12000.0, 5500.0, darkParam)) * ringGlow * 2.8;

    // Accretion disk arc: angular variation around ring (delta is already aspect space)
    let phi      = atan2(delta.y, delta.x);
    let diskMod  = 0.5 + 0.5 * cos(phi * 3.0 + time * 0.5 + bass * 2.0);
    color += blackbody(16000.0) * ringGlow * diskMod * 0.6;

    // Dark-matter / lensing halo beyond Einstein ring
    let halo    = darkParam * exp(-b * b / (haloR * haloR)) * 0.18;
    color += vec3<f32>(0.25, 0.08, 0.5) * halo;
    color += vec3<f32>(0.75, 0.85, 1.0) * min(caustic, 2.0) * darkParam * 0.35;

    // Black-hole shadow: photon sphere swallows light
    let shadow  = smoothstep(photonSphere * 0.8, photonSphere * 1.2, b);
    color *= shadow;

    // Idea 2: photon ring — light that orbits once before escaping piles into a
    // razor-thin, very bright band hugging the shadow edge.
    let prR    = photonSphere * 1.2;
    let prW    = max(ringWidth * 0.3, rs * 0.04 + 0.0008);
    let prD    = b - prR;
    let photon = exp(-prD * prD / (prW * prW));
    let skyLum = dot(sG.rgb, vec3<f32>(0.299, 0.587, 0.114));
    color += blackbody(mix(9000.0, 6000.0, redshift)) * photon * (1.6 + 1.2 * skyLum);

    // Depth modulation: nearby objects lens slightly more
    let depth      = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    color = mix(color * 0.6, color, depth * 0.5 + 0.5);

    let display = aces(max(color, vec3<f32>(0.0)));
    // Semantic alpha: opaque shadow (it absorbs), photo alpha elsewhere, glow adds coverage.
    let alpha = clamp(max(sG.a, 1.0 - shadow) + ringGlow * 0.3 + photon * 0.5, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(display, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(b, potential, ringGlow, deflectMag));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
        vec4<f32>(clamp(1.0 - b / max(einsteinR * 2.0, 0.001), 0.0, 1.0), 0.0, 0.0, 0.0));
}
