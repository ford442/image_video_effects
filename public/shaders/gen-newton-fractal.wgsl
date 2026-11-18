// ═══════════════════════════════════════════════════════════════════
//  Newton Fractal
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-27, 2026-11-18
//  Ideas: convergence-order sheen (estimated order q from successive Newton steps: quadratic glints, linear/relaxed zones shade violet with step isochrones); damped-Newton relaxation waves from clicks / held mouse reshaping the basins; Newton-flow striations (atan2 of last step inside basins); wandering-orbit dust (high orbitSecond despite convergence); basin-boundary distance-estimate filament (Green's-function DE from the accumulated orbit derivative, constant pixel width); Riemann-sheet hop count (orbit crossings of the cpower branch cut, amplitude |sin(pi n)|)
//  A packing: ACES display RGBA in A; A.a = floor(convergenceAlpha*255)/256 + reactionState*(0.999/256) (reaction-diffusion state rides in the sub-1/256 fraction of alpha)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .x = Zoom, .y = Polynomial Degree, .z = Iteration Precision, .w = Boundary Distortion

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_ROOTS: i32 = 6;
const TRAP_GATE: f32 = 0.35; // Rescue 1: step length below which an orbit counts as converged

// ── Hash & noise ──────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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

// ── Complex helpers ───────────────────────────────────────────────
fn cpower(z: vec2<f32>, n: f32) -> vec2<f32> {
    let r = length(z);
    let a = atan2(z.y, z.x);
    let rn = pow(r + 1e-6, n);
    return vec2<f32>(rn * cos(n * a), rn * sin(n * a));
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b) + 1e-8;
    return vec2<f32>((a.x * b.x + a.y * b.y) / d, (a.y * b.x - a.x * b.y) / d);
}

// Rescue 2b: roots of z^n - 1 on the principal branch of cpower sit at angles
// m * TAU / n for integers |m| <= n / 2. Order of the list: 0, 1, -1, 2, -2, 3
// (at most 6, same MAX_ROOTS). The -m twin of an exact +-pi pair is dropped.
fn rootMult(k: i32) -> f32 {
    return select(-f32(k / 2), f32((k + 1) / 2), (k & 1) == 1);
}

fn rootAlive(k: i32, n: f32) -> bool {
    let m = rootMult(k);
    let lim = abs(m) * 2.0;
    return select(lim <= n + 1e-4, lim < n - 1e-3, m < 0.0);
}

fn complexNoise(z: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
    let q = z * 3.0 + vec2<f32>(time * 0.11, -time * 0.07);
    let n1 = fbm(q, 3);
    let n2 = fbm(q + vec2<f32>(5.2, 1.3), 3);
    return scale * vec2<f32>(n1 - 0.5, n2 - 0.5);
}

// ── Tone & color ──────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ── SDF smooth boolean ────────────────────────────────────────────
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Reaction-diffusion sampling ───────────────────────────────────
// Reaction state is packed into the sub-1/256 fraction of A.a (see header).
fn unpackState(a: f32) -> f32 {
    return clamp(fract(a * 256.0) / 0.999, 0.0, 1.0);
}

fn sampleState(c: vec2<i32>, dims: vec2<i32>, fallback: f32) -> f32 {
    let inside = c.x >= 0 && c.x < dims.x && c.y >= 0 && c.y < dims.y;
    let cc = clamp(c, vec2<i32>(0), dims - vec2<i32>(1));
    return select(fallback, unpackState(textureLoad(dataTextureC, cc, 0).a), inside);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let mouse = u.zoom_config.yz;

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    // Parameters
    let zoom = mix(0.5, 5.5, p1);
    let degree = mix(3.0, 6.0, clamp(p2 + bass * 0.04, 0.0, 1.0));
    let maxIter = i32(mix(28.0, 84.0, p3));
    let tol = mix(2e-4, 1e-6, p3);
    let warpStrength = mix(0.0, 0.28, p4) + mids * 0.02;
    let perturbStrength = mix(0.0, 0.09, p4);
    let bloom = clamp(p4 + bass * 0.1, 0.0, 1.0);

    // Coordinate setup with domain warp
    let aspect = res.x / max(res.y, 1.0);
    var p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 3.5 / zoom;
    let zoomCenter = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    p = p + zoomCenter;
    p = domainWarp(p * 2.5 + vec2<f32>(time * 0.03), warpStrength, 3);

    // Root palette
    let rootColors = array<vec3<f32>, 6>(
        vec3<f32>(0.95, 0.08, 0.12),
        vec3<f32>(0.08, 0.92, 0.15),
        vec3<f32>(0.08, 0.35, 1.00),
        vec3<f32>(1.00, 0.85, 0.08),
        vec3<f32>(0.95, 0.08, 0.85),
        vec3<f32>(0.25, 0.95, 0.95)
    );

    let rootStep = TAU / degree;

    // Native idea 2: damped-Newton relaxation waves. z -= a * f/f'; a = 1 is
    // classic Newton, a != 1 (from click ripples / held mouse) turns quadratic
    // convergence linear and makes the basin boundaries breathe.
    var relax = 1.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let dist = length((uv01 - rp.xy) * vec2<f32>(aspect, 1.0));
            let band = (dist - age * 0.35) * 12.0;
            relax += exp(-band * band) * exp(-age * 1.1) * 0.55 * (1.0 + bass * 0.3);
        }
    }
    if (u.zoom_config.w > 0.5) {
        let md = length((uv01 - mouse) * vec2<f32>(aspect, 1.0));
        relax -= exp(-md * md * 18.0) * 0.4;
    }
    relax = clamp(relax, 0.45, 1.8);

    // Newton iteration with orbit trapping
    var z = p;
    var iters = 0;
    var orbitMin = 1e9;
    var orbitSecond = 1e9;
    var lastDz = vec2<f32>(0.0);
    var prevStep = 1.0;
    var convOrder = 0.0; // peak observed local convergence order
    var orbitLogDer = 0.0;              // Idea 5: log |d z_n / d z_0| along the orbit
    let rhoP = perturbStrength * 0.9;   // linear contraction floor the noise adds (|d noise / dz| / |f'|)
    var sheetHops = 0.0;                // Idea 6: branch-cut crossings of the orbit

    for (var i = 0; i < maxIter; i = i + 1) {
        let zn = cpower(z, degree);
        let znm1 = cpower(z, degree - 1.0);
        let perturb = complexNoise(z, time, perturbStrength);
        let dz = cdiv(zn - vec2<f32>(1.0, 0.0) + perturb, degree * znm1) * relax;
        let zOld = z;
        z = z - dz;
        lastDz = dz;
        iters = i;

        // ── Idea 5: orbit derivative (basin-boundary distance estimate) ──
        // Newton map N(z) = z - f/f' has N'(z) = f f'' / f'^2 = (z^n - 1)(n - 1) / (n z^n)
        // for f = z^n - 1; the damped step (relax) has derivative 1 - a + a N'.
        // Only |z_n'| is needed, so it is carried as a log-sum; the perturbation's own
        // derivative (not differentiated here) enters in quadrature as a floor rhoP.
        let nPrime = cdiv((zn - vec2<f32>(1.0, 0.0)) * (degree - 1.0), zn * degree);
        let stepDer = vec2<f32>(1.0 - relax, 0.0) + nPrime * relax;
        orbitLogDer = orbitLogDer + 0.5 * log(max(dot(stepDer, stepDer) + rhoP * rhoP, 1e-30));

        // ── Idea 6: Riemann-sheet hop bookkeeping — the step crossed the cpower branch cut
        // (negative real axis, where arg jumps from +pi to -pi).
        let hopped = (z.y * zOld.y < 0.0) && (z.x < 0.0) && (zOld.x < 0.0);
        sheetHops = sheetHops + select(0.0, 1.0, hopped);

        // Native idea 1: local convergence order q = log|dz_k| / log|dz_k-1|.
        let stepLen = length(dz);
        // Quadratic Newton climbs toward q=2 as steps shrink; damped or inexact
        // (noise-perturbed) Newton decays toward q=1, so keep the peak estimate.
        if (prevStep < 0.3 && prevStep > 1e-9 && stepLen > 1e-12 && stepLen < prevStep) {
            convOrder = max(convOrder, clamp(log(stepLen) / log(prevStep), 0.5, 3.0));
        }
        prevStep = stepLen;

        // Multi-shape orbit trap
        // Rescue 1: only the travelling part of the orbit feeds the traps. The converged
        // tail sits ON the roots, which lie on |z| = 1 and (root 0) on the real axis, so
        // HEAD's min over every step was ~0 everywhere. As a bonus the tail skips the
        // trap's atan2 / log entirely.
        if (stepLen > TRAP_GATE) {
            let r = length(z);
            let dRing = abs(r - 1.0);
            let dAxis = min(abs(z.x), abs(z.y));
            let dDiag = abs(z.x - z.y) * 0.70710678;
            let ang = atan2(z.y, z.x);
            let dSpiral = abs(fract(ang / TAU + log(r + 1e-6) * 0.25 + time * 0.03) - 0.5) * 2.0;
            let dTrap = min(min(min(dRing, dAxis), dDiag), dSpiral);

            let isMin = dTrap < orbitMin;
            orbitSecond = select(min(orbitSecond, dTrap), orbitMin, isMin);
            orbitMin = select(orbitMin, dTrap, isMin);
        }

        if (length(dz) < tol) { break; }
    }

    // Smooth iteration count
    // Rescue 3: superattracting form — the log of the error doubles every step, so the
    // fractional part is log2(log|dz| / log tol). HEAD's tol/max(|dz|,tol) was exactly 1
    // (term 0) for every converged pixel, i.e. integer bands.
    let lastLen = max(length(lastDz), 1e-12);
    let smoothIter = f32(iters) - log2(max(log(lastLen) / log(tol), 1.0));
    let iterRatio = clamp(smoothIter / f32(maxIter), 0.0, 1.0);
    let convergence = 1.0 - iterRatio;

    // Multi-root color accumulation for organic boundaries.
    // Rescue 2: the nearest root is the argmin over the live root list (HEAD's
    // fract(theta/rootStep + 0.5) is 0.5 for every converged z -> one colour for all basins).
    var accCol = vec3<f32>(0.0);
    var weightSum = 0.0;
    var bestD = 1e9;
    var nearestIdx = 0;
    for (var k = 0; k < MAX_ROOTS; k = k + 1) {
        let alive = rootAlive(k, degree);
        let ra = rootStep * rootMult(k);
        let rk = vec2<f32>(cos(ra), sin(ra));
        let dk = length(z - rk);
        let w = exp(-dk * 7.0) * f32(alive);
        accCol = accCol + rootColors[k] * w;
        weightSum = weightSum + w;
        let better = alive && dk < bestD;
        bestD = select(bestD, dk, better);
        nearestIdx = select(nearestIdx, k, better);
    }
    let blendedRoot = accCol / max(weightSum, 1e-6);
    let baseCol = mix(rootColors[nearestIdx], blendedRoot, 0.35 + p4 * 0.35);

    var color = baseCol * (1.0 - iterRatio * 0.55);

    // Orbit-trap glow
    // Rescue 4 (energy budget): the four always-on accents summed to ~+1.2 pre-ACES on a
    // ~0.4 base, so ACES clipped the frame to white. Sharper trap falloff + lower gains
    // (trap / iridescent trap / SDF halo / RD accent) make them mark orbits that really
    // pass a trap instead of washing the frame; the relative roles are unchanged.
    let trapGlow = exp(-orbitMin * (20.0 + bloom * 25.0 + treble * 8.0));
    let trapIrid = exp(-orbitSecond * (8.0 + bloom * 14.0));
    color = color + vec3<f32>(0.5, 0.7, 0.95) * trapGlow * bloom * 1.2;
    color = color + vec3<f32>(0.95, 0.45, 0.25) * trapIrid * bloom * 0.5;

    // SDF smooth-union halo around roots
    var sdf = 1e9;
    let rootRadius = 0.04 + p4 * 0.05;
    for (var k = 0; k < MAX_ROOTS; k = k + 1) {
        let alive = rootAlive(k, degree);
        let ra = rootStep * rootMult(k);
        let rk = vec2<f32>(cos(ra), sin(ra));
        // Rescue 5: the halo is measured from the START point p. At the converged z every
        // pixel sits on its root (sdf = -rootRadius), so HEAD's halo was a flat constant.
        let dk = length(p - rk) - rootRadius;
        sdf = select(sdf, smin(sdf, dk, 0.07), alive);
    }
    let sdfGlow = exp(-abs(sdf) * (5.0 + bloom * 8.0));
    color = color + vec3<f32>(0.55, 0.9, 1.0) * sdfGlow * bloom * 0.5;

    // Convergence-order sheen: quadratic (q~2) glints, linear (q~1) shades violet,
    // with isochrone contours of the smooth step count.
    let orderQ = select(convOrder, 1.0, convOrder <= 0.0); // never contracted -> treat as linear
    let linearity = 1.0 - smoothstep(1.4, 1.8, orderQ);
    let quadratic = smoothstep(1.75, 1.95, orderQ);
    let isochrone = pow(1.0 - abs(fract(smoothIter * 0.5) - 0.5) * 2.0, 10.0);
    color = color + vec3<f32>(0.45, 0.25, 0.95) * linearity * (0.22 + isochrone * 0.6) * (0.6 + p3 * 0.8) * convergence;
    color = color + vec3<f32>(1.0, 0.9, 0.7) * quadratic * isochrone * 0.18 * (1.0 + treble * 0.6);

    // Idea 1 — Newton-flow striations: argument of the last Newton step
    // paints the vector field inside each basin.
    let flowAng = atan2(lastDz.y, lastDz.x);
    let striations = pow(abs(sin(flowAng * 8.0)), 12.0) * convergence;
    color = color + vec3<f32>(0.95, 0.82, 0.48) * striations * 0.16 * (0.45 + mids * 0.55);

    // Idea 2 — wandering-orbit dust: high second trap despite convergence
    // (Julia-adjacent itineraries that only graze one trap).
    let wander = smoothstep(0.04, 0.20, orbitSecond) * convergence;
    color = color + vec3<f32>(0.62, 0.32, 1.0) * wander * 0.22 * (0.5 + treble * 0.55);

    // ── Idea 5: basin-boundary distance-estimate filament ──────────────
    // Green's function of the superattracting basin: G = 2^-n (-log|phi(z_n)|),
    // |phi| = |c| e_n with Boettcher constant |c| = (n-1)/2 and e_n ~ |c| |dz|^2.
    // |grad G| = 2^-n |z_n'| / e_n  =>  d = 2 sinh(G) / |grad G|  (Koebe-bounded).
    // The 2^n cancels against G = 2^-n L, so the estimate is evaluated in logs:
    // d = 2 L e_n sinhc(G) / |z_n'|. e_n comes from the last step (quadratic part
    // c|dz|^2 plus the noise's linear part rhoP |dz|, in quadrature).
    // Pixels that never converged ARE the boundary (d = 0). Width is measured in
    // pixels of the warped plane, so the line keeps its thickness at any zoom.
    let nSteps = f32(iters + 1);
    let cAbs = max(0.5 * (degree - 1.0), 1e-3);
    let eN = max(lastLen * sqrt(cAbs * cAbs * lastLen * lastLen + rhoP * rhoP), 1e-30);
    let bigL = max(-log(max(cAbs * eN, 1e-30)), 1e-3);
    let gPot = exp2(-nSteps) * bigL;
    let sinhc = select(sinh(min(gPot, 12.0)) / max(gPot, 1e-8), 1.0 + gPot * gPot * 0.16666667, gPot < 0.3);
    let logDe = log(2.0 * bigL * sinhc) + log(eN) - orbitLogDer;
    let deRaw = exp(clamp(logDe, -30.0, 2.0));
    let converged = length(lastDz) < tol;
    let deDist = select(0.0, deRaw, converged);
    let pxw = 8.75 / (zoom * res.y);
    let lineW = pxw * (1.0 + 1.0 * bloom);
    let filament = 1.0 - smoothstep(0.5 * lineW, 2.0 * lineW, deDist);
    color = color + vec3<f32>(1.0, 0.70, 0.26) * filament * 1.1 * (0.8 + treble * 0.5);

    // ── Idea 6: Riemann-sheet hop tint ─────────────────────────────────
    // zⁿ jumps across the cut by 2|sin(pi n)|: nothing at integer degree, maximal at
    // half-integer. Orbits that hopped sheets get the basin colours hue-rotated.
    let sheetAmp = abs(sin(PI * degree));
    let hopW = min(sheetHops, 2.0) * 0.5 * sheetAmp;
    color = mix(color, color.brg * 1.1 + vec3<f32>(0.04, 0.0, 0.08), hopW * 0.75);

    // Reaction-diffusion accent on basin boundaries
    let idims = vec2<i32>(res);
    let prevTex = textureLoad(dataTextureC, pixel, 0);
    let c0 = unpackState(prevTex.a);
    let cR = sampleState(pixel + vec2<i32>(1, 0), idims, c0);
    let cL = sampleState(pixel + vec2<i32>(-1, 0), idims, c0);
    let cT = sampleState(pixel + vec2<i32>(0, 1), idims, c0);
    let cB = sampleState(pixel + vec2<i32>(0, -1), idims, c0);
    let lap = cR + cL + cT + cB - 4.0 * c0;

    let feed = trapGlow * (1.0 - trapGlow) * 4.0;
    let rdState = clamp(c0 + 0.25 * (0.22 * lap + feed - 0.16 * c0), 0.0, 1.0);
    color = color + vec3<f32>(0.95, 0.2, 0.35) * rdState * (0.4 + bloom * 0.6) * 0.5;

    // Subtle temporal color feedback
    let prevColor = prevTex.rgb;
    color = mix(color, prevColor * 0.96, 0.03);

    // Chromatic aberration + ACES
    let caStr = 0.0025 * (1.0 + bass) + convergence * 0.001;
    color = genChromaticShift(color, uv01, caStr, time);
    color = acesToneMap(color * (1.05 + mids * 0.15));

    // Semantic alpha & depth
    let vignette = clamp(1.0 - length(uv01 - vec2<f32>(0.5)) * 1.15, 0.0, 1.0);
    let convAlpha = clamp(convergence * (1.0 - trapGlow * 0.25) * vignette, 0.0, 1.0);
    let alpha = floor(convAlpha * 255.0) / 256.0 + rdState * (0.999 / 256.0);
    let depth = convergence * (0.8 + iterRatio * 0.2);
    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, pixel, finalRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, pixel, finalRGBA);
}
