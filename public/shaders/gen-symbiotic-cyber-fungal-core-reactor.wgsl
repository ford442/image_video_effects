// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Cyber-Fungal Core-Reactor
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//    (mouse gravity-well core, click spore-burst from newest engine ripple,
//    bass/mids/treble + guarded FFT bins 1-8, engine-ripple nutrient rings,
//    temporal feedback memory dataTextureA/C, generated depth, semantic
//    alpha, ACES tone map)
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: reactor containment ring (precessing plasma torus + hot spot);
//    sporangia pods (breathing Worley nuclei on the gyroid); fractured core
//    shell (F2-F1 cracks leaking light through the inverted skin);
//    radiotrophic melanization (hyphae nearest the core darken to melanin
//    and re-emit absorbed dose as a bass-fed radiosynthesis ember sheen);
//    Cherenkov coolant pool (ray path through a sphere around the core
//    integrates a blue glow, brighter where the ray skims the core)
//  A packing: raw HDR trail rgb (pre-ACES) + nutrient alpha; ACES on
//    writeTexture only
//  Fixes: extraBuffer[133..138] is zeroed per frame so the spring/click
//    state never persisted -> stateless mouse + ripple-derived click age
//    (dead [133..138] writer removed 2026-10-18); pow(negative, 2.0) NaN
//    in the spore ring replaced by squaring; 2026-10-18: camera rows grew
//    downward (scene and mouse-y upside down) -> rd.y = -uv.y; inverted
//    core skin went negative under ACES (bright) -> clamped at 0
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn cellular(p: vec3<f32>) -> f32 {
    let pFloor = floor(p);
    let pFract = fract(p);
    var minDist = 1.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let cell = vec3<f32>(f32(i), f32(j), f32(k));
                let h = hash33(pFloor + cell);
                let diff = cell + h - pFract;
                let dist = length(diff);
                minDist = min(minDist, dist);
            }
        }
    }
    return minDist;
}

// Worley F1 / F2 / id of the nearest feature point (ideas 2 and 3)
fn worley(p: vec3<f32>) -> vec3<f32> {
    let pFloor = floor(p);
    let pFract = fract(p);
    var f1 = 8.0;
    var f2 = 8.0;
    var id = 0.0;
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let cell = vec3<f32>(f32(i), f32(j), f32(k));
                let h = hash33(pFloor + cell);
                let dist = length(cell + h - pFract);
                if (dist < f1) {
                    f2 = f1;
                    f1 = dist;
                    id = h.x;
                } else if (dist < f2) {
                    f2 = dist;
                }
            }
        }
    }
    return vec3<f32>(f1, f2, id);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i = 0; i < 4; i++) {
        f += cellular(pos) * amp;
        pos *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Frame context: input-reactivity state shared by the distance field
struct ReactorCtx {
    time: f32,
    core_pos: vec3<f32>,
    bass: f32,
    mids: f32,
    treble: f32,
    fft_lo: f32,
    fft_hi: f32,
    pulse: f32,      // click spore-burst energy (bounded 0..1)
    pulse_age: f32,  // seconds since click (scaled time)
    mutate: f32,     // hold-to-mutate surge (mouseDown)
};

fn map(p: vec3<f32>, c: ReactorCtx) -> f32 {
    let core_density = u.zoom_params.x;
    let mycelium_spread = u.zoom_params.y;
    let quantum_noise = u.zoom_params.z;

    var pos = p;

    // Core singularity at the gravity-well attractor (bass growth pulse)
    let core_radius = 0.5 * core_density * (1.0 + c.bass * 0.18);
    let d_core = length(pos - c.core_pos) - core_radius;

    // Gyroid structure for mycelium (mids morph the lattice phase)
    pos *= 1.5;
    pos += c.mids * vec3<f32>(0.35, 0.21, 0.42);
    var d_gyroid = dot(sin(pos), cos(pos.zxy)) - 0.1;

    // Quantum noise modification (mutation surges while mouse held)
    let noise = fbm(pos * 2.0 + c.time * (0.1 + c.mutate * 0.5)) * quantum_noise;
    d_gyroid += noise;

    // Attraction to core
    let dist_to_core = length(p - c.core_pos);
    let pull = smoothstep(2.0, 0.0, dist_to_core);
    d_gyroid -= pull * 0.5;

    // Click spore-burst: expanding shockwave swells the mycelium outward
    let ringX = (dist_to_core - c.pulse_age * 2.2) * 3.0;
    let ring = exp(-(ringX * ringX)); // squared (pow of a negative base is NaN)
    d_gyroid -= ring * c.pulse * 0.45;

    // Blend core and mycelium
    let d_mycelium = d_gyroid * 0.5 / (1.0 + mycelium_spread);

    return min(d_core, d_mycelium);
}

fn getNormal(p: vec3<f32>, c: ReactorCtx) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, c) - map(p - e.xyy, c),
        map(p + e.yxy, c) - map(p - e.yxy, c),
        map(p + e.yyx, c) - map(p - e.yyx, c)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.zw);
    let coord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }
    let px = vec2<i32>(global_id.xy);

    let uv = (coord - 0.5 * dimensions) / min(dimensions.x, dimensions.y);
    let uv01 = coord / dimensions;
    let tRaw = u.config.x;
    let time = tRaw * u.zoom_params.w; // Temporal Shift slider (live)

    // Real audio (canonical source)
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouseDown = u.zoom_config.w;

    let sbLen = arrayLength(&extraBuffer);
    let rawMouse = u.zoom_config.yz;
    // extraBuffer[133..138] is zeroed every frame by the engine, so a spring
    // there never persists: read the mouse directly and derive the click age
    // from the newest engine ripple (age = time - ripple.z; never ripple.w).
    let sm = rawMouse;
    var clickAge = 1.0e4;
    let clickCount = min(u32(u.config.y), 50u);
    for (var ci = 0u; ci < clickCount; ci++) {
        let cage = tRaw - u.ripples[ci].z;
        if (cage > 0.0) {
            clickAge = min(clickAge, cage);
        }
    }

    // Gravity-well attractor + slow autonomous drift: the core hunts nutrients
    let drift = vec2<f32>(sin(time * 0.23), cos(time * 0.17)) * 0.04 * (1.0 + mids * 0.5);
    let core_uv = sm + drift;
    let core_pos = vec3<f32>((core_uv.x - 0.5) * 5.0, -(core_uv.y - 0.5) * 5.0, 0.0);

    // Click spore-burst energy (bounded, decaying)
    let pulse_age = min(clickAge, 60.0);
    let pulse = select(0.0, exp(-pulse_age * 1.4), clickAge < 60.0);
    let mutate = step(0.5, mouseDown);

    // ── Guarded FFT bands (engine bins 1-8 at extraBuffer[6..13], read-only) ──
    var fft_lo = 0.0;
    var fft_hi = 0.0;
    if (sbLen > 13u) {
        fft_lo = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) * 0.3333;
        fft_hi = (extraBuffer[11] + extraBuffer[12] + extraBuffer[13]) * 0.3333;
    }

    let ctx = ReactorCtx(time, core_pos, bass, mids, treble, fft_lo, fft_hi, pulse, pulse_age, mutate);

    var ro = vec3<f32>(0.0, 0.0, -4.0);
    var rd = normalize(vec3<f32>(uv.x, -uv.y, 1.0)); // rows grow down; world +y = screen up

    // Slight camera rotation
    let rotMatrix = rot(time * 0.1);
    ro = vec3<f32>(rotMatrix * ro.xz, ro.y).xzy;
    rd = vec3<f32>(rotMatrix * rd.xz, rd.y).xzy;

    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;
    var hit = false;

    // IDEA 1: reactor containment ring — precessing plasma torus around the core
    let coreR = 0.5 * u.zoom_params.x;
    let ringAxis = normalize(vec3<f32>(0.55 * sin(time * 0.21), 1.0, 0.55 * cos(time * 0.17)));
    let ringB1 = normalize(cross(ringAxis, vec3<f32>(0.0, 0.0, 1.0)));
    let ringB2 = cross(ringAxis, ringB1);
    let ringMajor = coreR * 1.9 + 0.15;
    let ringMinor = 0.05 + 0.04 * coreR;
    var ringGlow = 0.0;
    // IDEA 5: Cherenkov coolant pool radius (scales with the core)
    let poolR = coreR * 2.6 + 0.45;
    var cherenkov = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, ctx);

        // Volumetric glow accumulation (treble sparkle emission rate)
        glow += (0.01 + fft_hi * 0.004) / (0.01 + abs(d));

        // IDEA 1: integrate the ring along the ray (stops at the core, so the
        // core occludes the far side); a hot spot orbits the ring
        let rq = p - core_pos;
        let rh = dot(rq, ringAxis);
        let rPlanar = rq - ringAxis * rh;
        let dRing = length(vec2<f32>(length(rPlanar) - ringMajor, rh)) - ringMinor;
        let rw = exp(-(dRing * dRing) * 40.0);
        if (rw > 0.01) {
            let ang = atan2(dot(rPlanar, ringB2), dot(rPlanar, ringB1));
            let hs = max(cos(ang - time * 1.3), 0.0);
            let hs2 = hs * hs;
            ringGlow += rw * (0.35 + 1.4 * hs2 * hs2) * clamp(d, 0.01, 0.25);
        }

        // IDEA 5: Cherenkov coolant — integrate the step length spent inside the
        // pool sphere; emission rises toward the core (dose ~ 1/r^2, capped)
        let pr = length(rq);
        if (pr < poolR) {
            let inner = 1.0 - pr / poolR;
            cherenkov += clamp(d, 0.005, 0.2) * inner * inner * (1.0 + 2.5 / (1.0 + 12.0 * max(pr - coreR, 0.0)));
        }

        if (d < 0.001 || t > 10.0) {
            if (d < 0.001) {
                hit = true;
                let n = getNormal(p, ctx);
                let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
                let diff = max(dot(n, l), 0.0);

                // Color mapping
                let dist_to_core = length(p - core_pos);
                let mycelium_color = mix(vec3<f32>(0.1, 0.8, 0.9), vec3<f32>(0.8, 0.1, 0.6), clamp(p.z * 0.5 + 0.5, 0.0, 1.0));
                let deep_crevice = vec3<f32>(0.2, 0.0, 0.4);

                var base_col = mix(deep_crevice, mycelium_color, diff);

                // Audio reactive spore emission (treble shimmer + FFT sparkle)
                base_col += vec3<f32>(0.1, 1.0, 0.5) * (treble * 0.12 + fft_hi * 0.25) * cellular(p * 5.0);
                // Bass growth pulse warms the mycelium veins
                base_col += vec3<f32>(0.5, 0.15, 0.05) * bass * 0.12 * cellular(p * 2.5 + 7.0);
                // Spore-burst ring flash sweeping the surface
                let ringX = (dist_to_core - pulse_age * 2.2) * 3.0;
                let ring = exp(-(ringX * ringX));
                base_col += vec3<f32>(0.6, 1.0, 0.8) * ring * pulse * 0.8;

                let coreSkin = dist_to_core < u.zoom_params.x * 0.55;

                // IDEA 4: radiotrophic melanization — hyphae inside the dose zone
                // darken to melanin; the pigment harvests the core's radiation and
                // re-emits it as an ember sheen on core-facing surfaces (bass feeds)
                if (!coreSkin) {
                    let doseR = coreR * 2.0 + 0.5;
                    let mel = smoothstep(doseR, coreR * 0.9, dist_to_core);
                    let toCore = normalize(core_pos - p);
                    let facing = max(dot(n, toCore), 0.0);
                    let grain = cellular(p * 7.0 + 3.1);
                    base_col = mix(base_col, vec3<f32>(0.07, 0.035, 0.02) * (0.6 + grain), mel * 0.7);
                    let ember = mel * facing * facing * (0.55 + bass * 0.6) * (0.6 + 0.4 * sin(time * 2.3 + grain * 9.0));
                    base_col += vec3<f32>(1.0, 0.42, 0.08) * ember;
                }

                // IDEA 2: sporangia pods — Worley nuclei on the gyroid swell and
                // breathe on per-cell phases (mycelium only, not the core skin)
                if (!coreSkin) {
                    let pw = worley(p * 3.0 + vec3<f32>(0.0, 0.0, time * 0.05));
                    let pod = smoothstep(0.30, 0.07, pw.x);
                    let breath = 0.5 + 0.5 * sin(time * 1.7 + pw.z * TAU);
                    let nucleus = smoothstep(0.12, 0.0, pw.x);
                    base_col += (vec3<f32>(0.55, 1.0, 0.3) * pod + vec3<f32>(1.0, 0.95, 0.7) * nucleus)
                        * (0.3 + 0.7 * breath) * 0.8;
                }

                // Negative color space near singularity
                if (coreSkin) {
                    base_col = max(1.0 - base_col, vec3<f32>(0.0)); // ACES maps negatives bright
                    base_col *= vec3<f32>(1.0, 0.5, 0.2); // Chromatic aberration effect

                    // IDEA 3: fractured core shell — Worley F2-F1 cracks leak
                    // hot light through the inverted skin, flickering per fragment
                    let cq = (p - core_pos) / max(coreR, 0.05);
                    let cw = worley(cq * 2.6 + vec3<f32>(0.0, 0.0, time * 0.06));
                    let crack = smoothstep(0.14, 0.0, cw.y - cw.x);
                    let flick = 0.5 + 0.5 * sin(time * 3.1 + cw.z * TAU);
                    base_col += vec3<f32>(1.0, 0.72, 0.35) * crack * (0.9 + 1.3 * flick);
                }

                col = base_col;
            }
            break;
        }
        t += d;
    }

    // Apply glow (bass-fed core luminescence)
    col += vec3<f32>(0.05, 0.4, 0.5) * glow * (0.04 + bass * 0.015);

    // Engine ripple shockwaves: nutrient rings that feed the bloom
    var rippleGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = tRaw - rp.z;
        if (age > 0.0) {
            let rr = age * 0.6;
            let rd2 = abs(distance(uv01, rp.xy) - rr);
            rippleGlow += exp(-rd2 * 30.0) * exp(-age * 1.5);
        }
    }
    col += vec3<f32>(0.2, 0.9, 0.7) * rippleGlow * 0.35;

    // Subsurface scattering approximation (cheap distance based fog)
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), 1.0 - exp(-0.1 * t));

    // IDEA 5: Cherenkov blue, under the ring (treble shimmer, no phase jumps)
    col += vec3<f32>(0.12, 0.42, 1.0) * cherenkov * (0.4 + treble * 0.15);

    // IDEA 1: containment ring added after the fog so it stays vivid
    col += vec3<f32>(1.0, 0.55, 0.2) * ringGlow * 2.2;

    // ── Temporal feedback memory: growth self-organizes along its history ──
    let prev = textureLoad(dataTextureC, px, 0); // non-filtering history read
    let decay = 0.90 + u.zoom_params.y * 0.06;   // Mycelium Spread = trail persistence
    var trail = prev.rgb * decay + max(col, vec3<f32>(0.0)) * (0.22 + bass * 0.08);
    trail = min(trail, vec3<f32>(3.0));
    let nutrient = clamp(mix(prev.a, glow * 0.05 + rippleGlow, 0.12), 0.0, 1.0);
    textureStore(dataTextureA, px, vec4<f32>(trail, nutrient));

    // History steers the live frame: established channels bioluminesce
    let hist = clamp(prev.a, 0.0, 1.0);
    col += prev.rgb * 0.10 * (0.4 + mids * 0.6);
    col += vec3<f32>(0.05, 0.25, 0.2) * hist * fft_lo * 0.3;

    col = acesToneMap(col * (0.95 + mids * 0.15));

    // Generated depth: raymarched hit distance (relief), miss = far plane
    let depth = select(1.0, clamp(t / 10.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Semantic alpha: reactor luminance density
    let alpha = clamp(luma(col) * 1.1 + glow * 0.004 + ringGlow * 0.3 + cherenkov * 0.25 + rippleGlow * 0.2, 0.06, 1.0);
    textureStore(writeTexture, px, vec4<f32>(col, alpha));
}
