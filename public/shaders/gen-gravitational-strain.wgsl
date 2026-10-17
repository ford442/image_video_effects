// ─────────────────────────────────────────────────────────────────────────────
//  Gravitational Strain Field
//  Category: GENERATIVE
//  Complexity: VERY HIGH
//  Mathematical approach: N gravity wells with metric tensor deformation.
//  Rays traced along geodesics via RK4 integration of dv/ds = -∇Φ.
//  Lensed image sampled from procedural star field with domain-warped nebula.
//  Tidal forces emit where |∇²Φ| is large (field gradient maxima).
//  Upgraded: 2026-10-17
//  Ideas: photon-sphere caustic at 1.5 Rs; tidal stretch of the background star field along ∇Φ; Tissot strain-ellipse lattice from the tidal Hessian; binary quadrupole wave arms that tighten as the pointer well and its partner close; tidal disruption streams (shredded-star debris spirals with Keplerian winding and a pericentre flare); Trojan dust tadpoles librating at the binary's L4/L5 points
//  A packing: potential depth, ray speed, emission energy, semantic alpha
// ─────────────────────────────────────────────────────────────────────────────
#include "_prelude.wgsl"
// zoom_params: x=WellCount(1-6), y=WellMass, z=BendStrength, w=EmissionScale

const PI:    f32 = 3.14159265358979323846;
const TAU:   f32 = 6.28318530717958647692;
const PHI:   f32 = 1.61803398874989484820;
const G_CONST: f32 = 6.674;
const E:     f32 = 2.71828182845904523536;

// ── HSV → RGB ──
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s; let h6 = fract(h) * 6.0;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if      (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + (v - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Hash / Value Noise ──
fn h1(n: f32) -> f32 { return fract(sin(n * 127.1 + 311.7) * 43758.5453123); }
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn h3(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(127.1, 311.7, 74.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y * q.z);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i+vec2<f32>(1,0)), u.x),
               mix(h2(i+vec2<f32>(0,1)), h2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn vnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(h3(i), h3(i+vec3<f32>(1,0,0)), u.x),
            mix(h3(i+vec3<f32>(0,1,0)), h3(i+vec3<f32>(1,1,0)), u.x), u.y),
        mix(mix(h3(i+vec3<f32>(0,0,1)), h3(i+vec3<f32>(1,0,1)), u.x),
            mix(h3(i+vec3<f32>(0,1,1)), h3(i+vec3<f32>(1,1,1)), u.x), u.y),
        u.z);
}

// ── Domain-Warped FBM ──
fn fbm_dw(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * vnoise(pp);
        // Domain warping: offset by previous noise value
        let warp = v * 0.3;
        pp = pp * 2.1 + vec2<f32>(1.7 + warp, 9.2 - warp) + vec2<f32>(t * 0.01, -t * 0.007);
        a *= 0.5;
    }
    return v;
}

fn fbm3_dw(p: vec3<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * vnoise3(pp);
        let warp = v * 0.25;
        pp = pp * 2.1 + vec3<f32>(1.7 + warp, 9.2 - warp, 3.1 + warp * 0.5) + vec3<f32>(t * 0.008, -t * 0.005, t * 0.003);
        a *= 0.5;
    }
    return v;
}

// ── Curl Noise (2D) ──
fn curlNoise2(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.008;
    let n1 = fbm_dw(p + vec2<f32>(eps, 0.0), t);
    let n2 = fbm_dw(p - vec2<f32>(eps, 0.0), t);
    let n3 = fbm_dw(p + vec2<f32>(0.0, eps), t);
    let n4 = fbm_dw(p - vec2<f32>(0.0, eps), t);
    return vec2<f32>(n3 - n4, n2 - n1) / (2.0 * eps);
}

// ── Worley / Voronoi Noise ──
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    var cellId = vec2<f32>(0.0);
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = neighbor + vec2<f32>(h2(i + neighbor), h2(i + neighbor + 7.31));
            let diff = neighbor + point - f;
            let d = dot(diff, diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
                cellId = i + neighbor;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    for (var z: i32 = -1; z <= 1; z++) {
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let point = neighbor + vec3<f32>(h3(i + neighbor), h3(i + neighbor + 7.31), h3(i + neighbor + 13.17));
                let diff = neighbor + point - f;
                let d = dot(diff, diff);
                if (d < minDist) {
                    secondDist = minDist;
                    minDist = d;
                } else if (d < secondDist) {
                    secondDist = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

// ── Fresnel-Schlick approximation ──
fn fresnelSchlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
    let p = 1.0 - cosTheta;
    let p5 = p * p * p * p * p;
    return f0 + (vec3<f32>(1.0) - f0) * p5;
}

// ── Beer-Lambert extinction ──
fn beerLambert(density: f32, absorption: f32) -> f32 {
    return exp(-density * absorption);
}

// ── Gravitational potential Φ at 2-D position p from N wells ──
fn gravPotential(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32) -> f32 {
    var phi = 0.0;
    for (var i = 0; i < n; i++) {
        let wpos = wells[i].xy;
        let mass = wells[i].z;
        let r    = length(p - wpos) + 0.05;
        phi     -= mass / r;
    }
    return phi;
}

// ── Gravitational gradient ∇Φ ──
fn gravGrad(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    for (var i = 0; i < n; i++) {
        let wpos = wells[i].xy;
        let mass = wells[i].z;
        let d    = p - wpos;
        let r2   = dot(d, d) + 0.0025;
        g       += d * mass / (r2 * sqrt(r2));
    }
    return -g;
}

// ── RK4 geodesic integration step ──
fn rk4Step(pos: vec2<f32>, vel: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32, bend: f32, dt: f32) -> vec4<f32> {
    let k1v = gravGrad(pos, wells, n) * bend;
    let k1p = vel;

    let p2 = pos + k1p * dt * 0.5;
    let v2 = vel + k1v * dt * 0.5;
    let k2v = gravGrad(p2, wells, n) * bend;
    let k2p = v2;

    let p3 = pos + k2p * dt * 0.5;
    let v3 = vel + k2v * dt * 0.5;
    let k3v = gravGrad(p3, wells, n) * bend;
    let k3p = v3;

    let p4 = pos + k3p * dt;
    let v4 = vel + k3v * dt;
    let k4v = gravGrad(p4, wells, n) * bend;
    let k4p = v4;

    let newPos = pos + (k1p + 2.0 * k2p + 2.0 * k3p + k4p) * dt / 6.0;
    let newVel = vel + (k1v + 2.0 * k2v + 2.0 * k3v + k4v) * dt / 6.0;
    return vec4<f32>(newPos, newVel);
}

// ── Procedural star field with domain-warped nebula ──
fn starField(uv: vec2<f32>, t: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    let scales = array<f32, 3>(40.0, 80.0, 160.0);
    for (var s = 0; s < 3; s++) {
        let sc  = scales[s];
        let cell = floor(uv * sc);
        let frac = fract(uv * sc);
        let seed = h2(cell + vec2<f32>(f32(s) * 73.1, 0.0));
        if (seed > 0.97) {
            let starPos = vec2<f32>(h2(cell + 1.0), h2(cell + 2.0));
            let dist    = length(frac - starPos);
            let twinkle = 0.7 + 0.3 * sin(t * (seed * 5.0 + 1.0) + seed * 100.0);
            let bright  = exp(-dist * sc * 0.4) * twinkle;
            let hue     = fract(seed * 3.7 + t * 0.01);
            col        += hsv2rgb(hue, 0.3 + seed * 0.4, bright * 0.8 / f32(s + 1));
        }
    }
    // Domain-warped nebula glow
    let nebUV = uv * 3.0 + vec2<f32>(t * 0.005, -t * 0.003);
    let nebWarp = fbm_dw(nebUV, t);
    let nebHue = fract(nebWarp + t * 0.01);
    let nebBright = vnoise(nebUV * 6.0 + t * 0.01) * 0.12;
    col += hsv2rgb(nebHue, 0.6, nebBright);
    // Voronoi gas clouds
    let voro = voronoi(uv * 5.0 + t * 0.002);
    let voroCloud = smoothstep(0.15, 0.0, voro.x) * 0.08;
    col += hsv2rgb(fract(t * 0.02 + voro.x), 0.4, voroCloud);
    return col;
}

// ── Tidal emission with Laplacian and curl ──
fn tidalEmission(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32, t: f32) -> vec3<f32> {
    let eps = 0.008;
    let phi  = gravPotential(p, wells, n);
    let phiR = gravPotential(p + vec2<f32>(eps, 0.0), wells, n);
    let phiL = gravPotential(p - vec2<f32>(eps, 0.0), wells, n);
    let phiU = gravPotential(p + vec2<f32>(0.0, eps), wells, n);
    let phiD = gravPotential(p - vec2<f32>(0.0, eps), wells, n);
    let laplacian = abs((phiR + phiL + phiU + phiD - 4.0 * phi) / (eps * eps));

    let gx = (phiR - phiL) / (2.0 * eps);
    let gy = (phiU - phiD) / (2.0 * eps);
    let gradMag = length(vec2<f32>(gx, gy));

    // Curl of gradient field adds turbulent emission
    let curlE = curlNoise2(p * 3.0 + t * 0.1, t);
    let curlEmission = length(curlE) * 0.5;

    let emission = clamp(laplacian * 0.03 + gradMag * 0.5 + curlEmission, 0.0, 4.0);
    let hue = fract(phi * 0.3 + t * 0.08 + gradMag * 0.1);
    return hsv2rgb(hue, 0.9, 1.0) * emission;
}

// ── Photon-sphere caustic (1.5 Rs) — distinct from Einstein ring ──
fn photonSphereGlow(p: vec2<f32>, wellPos: vec2<f32>, mass: f32) -> f32 {
    let d = length(p - wellPos);
    let rs = mass * 2.0;
    let photonR = rs * 1.5;
    let w = 0.0035 + mass * 0.0025;
    let x = (d - photonR) / max(w, 0.0001);
    return exp(-x * x) * mass * 6.0;
}

// ── Tidal Hessian ∂²Φ (xx, yy, xy) by central differences ──
fn gravHessian(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32) -> vec3<f32> {
    let e = 0.01;
    let c  = gravPotential(p, wells, n);
    let xp = gravPotential(p + vec2<f32>(e, 0.0), wells, n);
    let xm = gravPotential(p - vec2<f32>(e, 0.0), wells, n);
    let yp = gravPotential(p + vec2<f32>(0.0, e), wells, n);
    let ym = gravPotential(p - vec2<f32>(0.0, e), wells, n);
    let pp = gravPotential(p + vec2<f32>(e, e), wells, n);
    let mm = gravPotential(p - vec2<f32>(e, e), wells, n);
    let pm = gravPotential(p + vec2<f32>(e, -e), wells, n);
    let mp = gravPotential(p + vec2<f32>(-e, e), wells, n);
    return vec3<f32>((xp + xm - 2.0 * c) / (e * e),
                     (yp + ym - 2.0 * c) / (e * e),
                     (pp + mm - pm - mp) / (4.0 * e * e));
}

// ── Einstein ring glow with Fresnel falloff ──
fn einsteinRingGlow(p: vec2<f32>, wellPos: vec2<f32>, mass: f32, t: f32) -> f32 {
    let d = length(p - wellPos);
    let eRing = sqrt(mass * 0.5);
    let ringWidth = 0.008 + mass * 0.005;
    let ringDist = abs(d - eRing);
    let f = clamp(1.0 - ringDist / ringWidth, 0.0, 1.0);
    let fresnel = f * f * f;
    return fresnel * mass * 10.0;
}

// ── Accretion disk SDF ──
fn accretionDisk(p: vec2<f32>, wellPos: vec2<f32>, mass: f32, t: f32) -> f32 {
    let d = p - wellPos;
    let r = length(d);
    let angle = atan2(d.y, d.x);
    let diskInner = mass * 0.3;
    let diskOuter = mass * 1.5;
    let ringDist = abs(r - (diskInner + diskOuter) * 0.5);
    let diskWidth = (diskOuter - diskInner) * 0.5;
    let diskShape = smoothstep(diskWidth, 0.0, ringDist);
    // Spiral perturbation
    let spiral = sin(angle * 3.0 + t * 0.5 + r * 10.0) * 0.5 + 0.5;
    return diskShape * spiral * smoothstep(diskOuter + 0.1, diskInner, r);
}

// ── Main ──
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res    = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let coord = vec2<i32>(gid.xy);
    let previousState = textureLoad(dataTextureC, coord, 0);
    let uv     = vec2<f32>(gid.xy) / res;
    let t      = u.config.x;
    let mouse  = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    // Mouse Y-flip: screen-top (zoom_config.z=0) = +Y/up
    let mouseY = mouse.y;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let wellCount   = i32(u.zoom_params.x * 5.0 + 1.5);
    // Bass pumps black-hole mass — feels like the field reacts to drum hits
    let wellMass    = (u.zoom_params.y * 0.08 + 0.01) * (1.0 + bass * 0.6 + mids * 0.3);
    let bendStrength = u.zoom_params.z * 0.15 + 0.02;
    let emScale     = u.zoom_params.w * 3.0 + 0.5;

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // ── Set up gravity wells with orbital dynamics ──
    var wells: array<vec3<f32>, 6>;
    for (var i = 0; i < 6; i++) {
        let seed = f32(i) * 13.7 + t * 0.01;
        let orbitR = h1(seed) * 0.25 + 0.1;
        let orbitS = (h1(seed + 1.0) * 0.5 + 0.3) * (select(-1.0, 1.0, i32(h1(seed + 2.0) * 10.0) % 2 == 0));
        let angle  = orbitS * t * (0.5 + h1(seed + 5.0) * 0.5) + h1(seed + 3.0) * TAU;
        let wx     = cos(angle) * orbitR * aspect;
        let wy     = sin(angle) * orbitR;
        let mass   = wellMass * (h1(seed + 4.0) * 0.8 + 0.4) * (1.0 + treble * 0.2 * sin(t * 3.0 + f32(i)));
        wells[i] = vec3<f32>(wx, wy, mass);
    }
    // Mouse-controlled well with Y-flip
    let mouseWell = vec2<f32>((mouse.x - 0.5) * aspect, mouseY - 0.5);
    wells[0] = vec3<f32>(mouseWell.x, mouseWell.y, wellMass * (1.5 + mouseDown * 1.5) * (1.0 + bass * 0.5));

    // ── Ray deflection: RK4 geodesic integration ──
    var rayPos = p;
    var rayVel = vec2<f32>(0.0);
    // The lensing-quality control also scales the bounded RK4 budget.
    let steps  = 16 + i32(u.zoom_params.z * 8.0);
    let stepSz = 1.0 / f32(steps);
    var totalAbsorption = 0.0;

    for (var s = 0; s < steps; s++) {
        let rk4 = rk4Step(rayPos, rayVel, wells, wellCount, bendStrength, stepSz);
        rayPos = rk4.xy;
        rayVel = rk4.zw;
        // Accumulate Beer-Lambert extinction near wells
        for (var i = 0; i < wellCount; i++) {
            let d = length(rayPos - wells[i].xy);
            let density = wells[i].z / (d * d + 0.01);
            totalAbsorption += density * stepSz * 0.001;
        }
    }

    // ── Sample lensed star field ──
    // Idea 2 — tidal stretch: displace the sky sample along ∇Φ
    let tidalDir = gravGrad(p, wells, wellCount);
    let tidalLen = max(length(tidalDir), 0.0001);
    let tidalStretch = (tidalDir / tidalLen) * clamp(tidalLen * 0.12, 0.0, 0.05);
    // Idea 4 — binary quadrupole wave: the pointer well and its orbiting
    // partner radiate two-armed h+ strain. Arm phase follows the binary's own
    // orbital angle, and the arms tighten (higher wavenumber) as the pair
    // closes — a spatial chirp. The strain squeezes/stretches the sky sample
    // along the wave's polarisation axes.
    var gwStrain = 0.0;
    var gwCrest = 0.0;
    if (wellCount >= 2) {
        let m0 = wells[0].z;
        let m1 = wells[1].z;
        let sep = wells[1].xy - wells[0].xy;
        let sepLen = max(length(sep), 0.02);
        let bary = (wells[0].xy * m0 + wells[1].xy * m1) / max(m0 + m1, 0.0001);
        let rel = p - bary;
        let r = max(length(rel), 0.0001);
        let orbAng = atan2(sep.y, sep.x);
        let waveK = clamp(14.0 * pow(0.25 / sepLen, 1.5), 6.0, 60.0);
        let gwPhase = 2.0 * (atan2(rel.y, rel.x) - orbAng) - r * waveK;
        let envelope = smoothstep(sepLen * 0.5, sepLen * 1.2, r) / (1.0 + r * 4.0);
        let massRatio = clamp((m0 * m1) / max(wellMass * wellMass, 1e-6), 0.0, 3.0);
        gwStrain = cos(gwPhase) * envelope * massRatio * (0.4 + u.zoom_params.z * 0.6);
        let crest = clamp(cos(gwPhase), 0.0, 1.0);
        gwCrest = crest * crest * crest * crest * envelope * massRatio;
    }
    let gwDisp = gwStrain * 0.02 * vec2<f32>(p.x - wells[0].x, -(p.y - wells[0].y));
    let lensedUV = (rayPos / vec2<f32>(aspect, 1.0) + 0.5) + (tidalStretch + gwDisp) / vec2<f32>(aspect, 1.0);
    let stars    = starField(lensedUV, t);

    // ── Tidal emission ──
    let emission = tidalEmission(p, wells, wellCount, t) * emScale;

    // ── Schwarzschild-like darkening with Beer-Lambert ──
    var darkening = 1.0;
    for (var i = 0; i < wellCount; i++) {
        let d     = length(p - wells[i].xy);
        let rs    = wells[i].z * 2.0;
        darkening *= 1.0 - exp(-d * d / (rs * rs * 0.1)) * 0.85;
    }
    // Apply Beer-Lambert extinction from ray tracing
    darkening *= beerLambert(totalAbsorption, 2.0);

    // ── Ripple: temporary extra gravity wells ──
    let ripCount = min(u32(u.config.y), 50u);
    var ripEmission = vec3<f32>(0.0);
    for (var i: u32 = 0u; i < ripCount; i++) {
        let r   = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rp  = (r.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let d   = length(p - rp);
        let ring = exp(-(d - age * 0.3) * (d - age * 0.3) * 80.0) * exp(-age * 1.5);
        ripEmission += hsv2rgb(fract(age * 0.4 + bass * 0.2), 0.9, ring * 2.0 * (1.0 + bass));
    }

    // ── Compose ──
    var col = stars * darkening + emission + ripEmission;
    col += hsv2rgb(fract(0.62 + t * 0.02 + mids * 0.1), 0.55, 1.0) * gwCrest * 0.08 * emScale * darkening;

    // Idea 5 — tidal disruption streams: every ~7 s per well a star strays
    // inside the tidal radius and is shredded. Its debris winds into a single
    // spiral stream whose inner parts lap the outer ones (Keplerian winding,
    // angle offset ∝ r^-1.5) and lengthens outward with age; a short flare
    // marks the pericentre passage. Bounded: 4 s lifetime, one stream/well.
    var tdeLight = vec3<f32>(0.0);
    for (var i = 0; i < wellCount; i++) {
        let fi = f32(i);
        let period = 6.0 + h1(fi * 3.1 + 0.7) * 3.0;
        let age = fract((t + h1(fi * 5.3) * period) / period) * period;
        if (age < 4.0) {
            let wpos = wells[i].xy;
            let rsT = max(wells[i].z * 2.0, 0.005);
            let rel = p - wpos;
            let r = max(length(rel), 0.0001);
            let ang0 = h1(fi * 7.9 + floor((t + h1(fi * 5.3) * period) / period)) * TAU;
            let rPeri = rsT * 1.6;
            let rTip = rPeri + age * 0.07;
            let wind = age * 2.2 * pow(rPeri / max(r, rPeri), 1.5);
            let x = atan2(rel.y, rel.x) - ang0 - wind;
            let wrapped = x - TAU * round(x / TAU);
            let radial = smoothstep(rPeri * 0.8, rPeri * 1.2, r) * (1.0 - smoothstep(rTip * 0.8, rTip, r));
            let thick = 0.12 + 0.25 * (r - rPeri) / max(rTip - rPeri, 0.01);
            let strand = exp(-wrapped * wrapped / (thick * thick)) * radial;
            let fade = (1.0 - smoothstep(2.5, 4.0, age)) * smoothstep(0.0, 0.15, age);
            let clump = 0.6 + 0.4 * vnoise(vec2<f32>(r * 90.0 - age * 4.0, fi * 11.0));
            let fx = (r - rPeri) / rsT;
            let flare = exp(-age * 7.0) * exp(-fx * fx) * 1.8; // pericentre ring flash, outside the dark core
            let heat = clamp(1.0 - (r - rPeri) / max(rTip - rPeri, 0.01), 0.0, 1.0);
            tdeLight += mix(vec3<f32>(1.0, 0.35, 0.12), vec3<f32>(0.85, 0.9, 1.0), heat)
                * (strand * clump * fade * 0.55 + flare) * (1.0 + bass * 0.6);
        }
    }
    col += tdeLight * (0.4 + emScale * 0.4) * darkening;

    // Idea 6 — Trojan dust at L4/L5: the pointer well and its orbiting partner
    // hold two leading/trailing dust clouds at the equilateral Lagrange points,
    // stretched into tadpoles along the shared orbit and librating ±15°.
    var trojanLight = 0.0;
    if (wellCount >= 2) {
        let sepT = wells[1].xy - wells[0].xy;
        let sepLenT = max(length(sepT), 0.02);
        let dirT = sepT / sepLenT;
        for (var k = 0; k < 2; k++) {
            let sgn = select(-1.0, 1.0, k == 0);
            let lib = sgn * PI / 3.0 + 0.26 * sin(t * 0.35 + f32(k) * 2.1);
            let cl = cos(lib); let sl = sin(lib);
            let lpt = wells[0].xy + vec2<f32>(dirT.x * cl - dirT.y * sl, dirT.x * sl + dirT.y * cl) * sepLenT;
            // tadpole long axis = tangent of the circle around wells[0]
            let radial = normalize(lpt - wells[0].xy + vec2<f32>(1e-5, 0.0));
            let tang = vec2<f32>(-radial.y, radial.x);
            let lq = p - lpt;
            let along = dot(lq, tang) / (sepLenT * 0.38);
            let across = dot(lq, radial) / (sepLenT * 0.09);
            let blob = exp(-(along * along + across * across));
            let grain = vnoise(lq * 140.0 + vec2<f32>(t * 0.3, f32(k) * 17.0));
            trojanLight += blob * (0.35 + 0.65 * grain * grain);
        }
    }
    col += vec3<f32>(0.95, 0.68, 0.36) * trojanLight * (0.05 + mids * 0.05) * emScale * darkening;

    // Idea 3 — Tissot strain ellipses: a lattice of unit circles pulled back
    // through the local tidal tensor I + kH, so each ring becomes the ellipse
    // the field would stretch it into (long axis = tidal stretch direction).
    let tissotN = 14.0;
    let cellUV = p * tissotN;
    let cellC = (floor(cellUV) + 0.5) / tissotN;
    let hess = gravHessian(cellC, wells, wellCount);
    let hessMag = sqrt(hess.x * hess.x + hess.y * hess.y + 2.0 * hess.z * hess.z) + 1e-5;
    let kTidal = min(0.25 * bendStrength, 0.65 / hessMag);
    let sT = hess * kTidal;
    let local = cellUV - floor(cellUV) - 0.5;
    let q = local + vec2<f32>(sT.x * local.x + sT.z * local.y, sT.z * local.x + sT.y * local.y);
    let ringD = abs(length(q) - 0.3);
    let tissotLine = exp(-ringD * ringD * 900.0);
    let strainAmt = clamp(hessMag * kTidal, 0.0, 1.0);
    let tissotHue = fract(0.55 + (sT.x + sT.y) * 0.6 + t * 0.01);
    col += hsv2rgb(tissotHue, 0.65, 1.0) * tissotLine * (0.02 + strainAmt * 0.18) * emScale * darkening;

    // A held pointer spins a closed-form strain runner around the local well.
    let mouseDelta = p - mouseWell;
    let mouseDist = max(length(mouseDelta), 0.0001);
    let strainPhase = mouseDist * 72.0 - t * (9.0 + bass * 4.0) + atan2(mouseDelta.y, mouseDelta.x) * 5.0;
    let strainRunner = pow(0.5 + 0.5 * sin(strainPhase), 12.0) * exp(-mouseDist * 5.0) * mouseDown;
    let strainColor = hsv2rgb(fract(t * 0.08 + mouseDist * 0.6), 0.9, 1.0);
    col += strainColor * strainRunner * (1.0 + treble);

    // ── Einstein ring glows with Fresnel ──
    for (var i = 0; i < wellCount; i++) {
        let ering = einsteinRingGlow(p, wells[i].xy, wells[i].z, t);
        let eHue  = fract(f32(i) / 6.0 + t * 0.05 + 0.1 + mids * 0.1);
        col += hsv2rgb(eHue, 0.9, 1.0) * ering;
        // Idea 1 — photon-sphere caustic just outside the hole
        let photon = photonSphereGlow(p, wells[i].xy, wells[i].z);
        col += hsv2rgb(fract(eHue + 0.08), 0.55, 1.0) * photon * (0.55 + treble * 0.35);
    }

    // ── Accretion disks ──
    for (var i = 0; i < wellCount; i++) {
        let disk = accretionDisk(p, wells[i].xy, wells[i].z, t);
        let diskHue = fract(f32(i) * 0.17 + t * 0.03);
        col += hsv2rgb(diskHue, 0.7, 1.0) * disk * wellMass * 3.0;
    }

    // ── Relativistic Doppler shift ──
    let raySpeed = length(rayVel);
    let blueshift = clamp(raySpeed * 5.0, 0.0, 1.0);
    let dopplerHue = fract(t * 0.03 - blueshift * 0.15);
    col = mix(col, col * hsv2rgb(dopplerHue, 0.4, 1.0), blueshift * 0.25);

    // ── Dark matter "web" via domain-warped FBM + Voronoi ──
    let dmUV    = p * 4.0 + vec2<f32>(t * 0.007, -t * 0.005);
    let dmWeb   = fbm_dw(dmUV, t);
    let dmVoro  = voronoi(p * 2.0 + t * 0.003);
    let dmDark  = smoothstep(0.6, 1.0, dmWeb) * 0.12 + smoothstep(0.1, 0.0, dmVoro.x) * 0.06;
    let dmColor = hsv2rgb(fract(t * 0.04 + dmWeb + dmVoro.x), 0.3, dmDark);
    col = col * (1.0 - dmDark * 0.5) + dmColor;

    // ── Gravitational lensing arc highlights with Fresnel ──
    let lensArc  = raySpeed * darkening * emScale * 0.3;
    let arcAngle = atan2(rayVel.y, rayVel.x);
    let arcColor = hsv2rgb(fract(arcAngle / TAU + t * 0.05), 0.8, lensArc);
    let rsClamped = clamp(raySpeed * 2.0, 0.0, 1.0);
    let fresnelArc = rsClamped * rsClamped;
    col = col + arcColor * fresnelArc * smoothstep(0.05, 0.2, raySpeed);

    col = acesToneMap(clamp(col, vec3<f32>(0.0), vec3<f32>(6.0)) * 1.08);

    // ── Depth: normalized gravitational potential ──
    let phi = gravPotential(p, wells, wellCount);
    let rawDepth = clamp((-phi) / (wellMass * f32(wellCount) * 20.0), 0.0, 1.0);
    let depthOut = mix(previousState.r, rawDepth, 0.35 + treble * 0.1);

    // ── Alpha: emission energy + lens arc + ring intensity ──
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let emEnergy = length(emission) + length(ripEmission) + length(arcColor) + strainRunner + length(tdeLight) * 0.5;
    let alpha = clamp(0.4 + luma * 0.3 + emEnergy * 0.15 + depthOut * 0.2, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(col, alpha));
    // Persist potential field for downstream feedback shaders
    textureStore(dataTextureA, coord, vec4<f32>(depthOut, raySpeed, emEnergy, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
}
