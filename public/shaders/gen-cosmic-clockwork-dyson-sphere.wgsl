// ═══════════════════════════════════════════════════════════════════════════════
//  Cosmic-Clockwork Dyson-Sphere
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-27
//  Ideas: Voronoi plasma conduits fed by the core; Beer-Lambert chromatic transmittance through the plasma; core as the light source (brass f0, radial lattice shadows)
//  A packing: ACES display RGBA (C read as display history, blended after tone-map)
//  A camera orbits a 5-fold KIFS brass lattice of boxes, tori and struts carved
//  around a Voronoi-roughened plasma core. Domain-warped FBM weathering,
//  Fresnel-Schlick brass, stepped clockwork rotation, click shock gear ticks.
// ═══════════════════════════════════════════════════════════════════════════════

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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Mechanical Complexity, y=Clock Speed, z=Plasma Intensity, w=Gear Ratio
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749894;

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
    let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
    let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
    let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
    let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
    let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
    let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
    return vec4<f32>(controlled, color.a);
}

// ── Hash / Noise ──
fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1 + 311.7) * 43758.5453123); }
fn hash2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(127.1, 311.7, 74.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y * q.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i+vec2<f32>(1,0)), u.x),
               mix(hash2(i+vec2<f32>(0,1)), hash2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn vnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i), hash3(i+vec3<f32>(1,0,0)), u.x),
            mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
        mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
            mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y),
        u.z);
}

// ── Domain-Warped FBM ──
fn fbm_dw2(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * vnoise2(pp);
        let warp = v * 0.3;
        pp = pp * 2.1 + vec2<f32>(1.7 + warp, 9.2 - warp) + vec2<f32>(t * 0.01, -t * 0.007);
        a *= 0.5;
    }
    return v;
}

fn fbm_dw3(p: vec3<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * vnoise3(pp);
        let warp = v * 0.25;
        pp = pp * 2.1 + vec3<f32>(1.7 + warp, 9.2 - warp, 3.1 + warp * 0.5) + vec3<f32>(t * 0.008, -t * 0.005, t * 0.003);
        a *= 0.5;
    }
    return v;
}

// ── Voronoi / Worley Noise ──
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    for (var z: i32 = -1; z <= 1; z++) {
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let point = neighbor + vec3<f32>(hash3(i + neighbor), hash3(i + neighbor + 7.31), hash3(i + neighbor + 13.17));
                // Fix: `point` already includes `neighbor`; HEAD added it twice
                // (points at 2*nb+h), so F1/F2 jumped at every integer cell
                // face and F2-F1 borders almost never formed.
                let diff = point - f;
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

// ── Rotation Matrices ──
fn rotX(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ── SDF Primitives ──
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}
fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = vec2<f32>(length(p.xz), p.y);
    return length(max(d - vec2<f32>(r, h), vec2<f32>(0.0))) + min(max(d.x - r, d.y - h), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// ── Fresnel-Schlick ──
fn fresnelSchlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0);
}

// ── Beer-Lambert ──
fn beerLambert(density: f32, absorption: f32) -> f32 {
    return exp(-density * absorption);
}

// ── Scene Map with Enhanced KIFS + Gear Details ──
// Returns (scene distance, core distance). The core distance is the same
// Voronoi-perturbed sphere the march used to recompute every step; it is now
// computed once here and reused (27-cell voronoi3 per step saved).
fn mapFull(pos: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> vec2<f32> {
    var p = pos;
    var d = 1000.0;

    // Core Singularity with Voronoi perturbation
    let voro = voronoi3(p * 2.0 + t * 0.1);
    let dCore = length(p) - 0.5 * (1.0 + voro.x * 0.15);

    // KIFS Folds with temporal variation
    let kifsTime = t * 0.1;
    for (var i = 0; i < 5; i++) {
        p = abs(p);
        let offset = gearRatio * 1.5 + 0.1 * sin(kifsTime + f32(i) * 1.7);
        p = p - vec3<f32>(offset, gearRatio * 0.5, offset);
        p = p * rotY(complex * 2.0 + kifsTime * 0.2);
        p = p * rotZ(complex * 1.5 + kifsTime * 0.15);
        p = p * rotX(complex * 0.5 + sin(kifsTime * 0.3) * 0.1);
    }

    // Main box structure with noise detail
    let noiseDetail = fbm_dw3(p * 3.0, t) * 0.05;
    let box = sdBox(p, vec3<f32>(0.2 + noiseDetail, 1.0 + noiseDetail, 0.2 + noiseDetail));

    // Gear rings (toroidal)
    let gearRing1 = sdTorus(p * rotY(t * 0.2), vec2<f32>(1.2 + gearRatio, 0.08));
    let gearRing2 = sdTorus(p * rotZ(t * 0.15), vec2<f32>(0.8 + gearRatio * 0.5, 0.06));
    let gearRing3 = sdTorus(p * rotX(t * 0.1), vec2<f32>(0.5 + gearRatio * 0.3, 0.04));

    // Cylindrical struts
    let strut = sdCylinder(p * rotZ(PI * 0.25), 0.5, 0.03);

    // Combine all structures
    d = min(d, box);
    d = min(d, gearRing1);
    d = min(d, gearRing2);
    d = min(d, gearRing3);
    d = min(d, strut);

    // Remove geometry too close to singularity (event horizon mask)
    d = max(d, -dCore + 0.05);

    return vec2<f32>(d, dCore);
}

fn map(pos: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> f32 {
    return mapFull(pos, complex, gearRatio, t).x;
}

// ── Normal calculation with higher precision ──
fn calcNormal(p: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> vec3<f32> {
    let e = vec2<f32>(0.0005, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, complex, gearRatio, t) - map(p - e.xyy, complex, gearRatio, t),
        map(p + e.yxy, complex, gearRatio, t) - map(p - e.yxy, complex, gearRatio, t),
        map(p + e.yyx, complex, gearRatio, t) - map(p - e.yyx, complex, gearRatio, t)
    ));
}

// ── Ambient Occlusion ──
fn calcAO(p: vec3<f32>, n: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> f32 {
    var ao = 0.0;
    for (var i = 1; i <= 4; i++) {
        let d = f32(i) * 0.05;
        ao += (d - map(p + n * d, complex, gearRatio, t)) / d;
    }
    return clamp(1.0 - ao * 0.25, 0.0, 1.0);
}

// ── Plasma color with spectral shift ──
fn getPlasmaColor(intensity: f32, t: f32) -> vec3<f32> {
    let c = clamp(intensity, 0.0, 1.0);
    let shift = sin(t * 0.5) * 0.1;
    return mix(
        vec3<f32>(0.1 + shift, 0.0, 0.8 - shift),
        vec3<f32>(1.0, 0.9 + shift, 0.2),
        c
    );
}

// Idea 2: plasma medium density around the core — 1 inside the singularity,
// falling off over the same 1.0 shell the HEAD volumetric glow used.
fn plasmaDensity(dCore: f32) -> f32 {
    return exp(-max(dCore, 0.0) * 3.0) * (1.0 - smoothstep(0.7, 1.0, dCore));
}

// Idea 2: per-channel extinction — blue is absorbed first, so light that
// crosses more plasma arrives redder (the core reddens what lies behind it).
const PLASMA_SIGMA: vec3<f32> = vec3<f32>(0.55, 0.85, 1.35);

// Idea 3: soft shadow toward the core. The lattice shells cast radial shadows
// outward from the singularity. map() is carved around the core, so the ray
// ends unoccluded once it reaches the event-horizon mask.
fn coreShadow(ro: vec3<f32>, rd: vec3<f32>, maxT: f32, complex: f32, gearRatio: f32, t: f32) -> f32 {
    var res = 1.0;
    var s = 0.03;
    for (var i = 0; i < 14; i++) {
        if (s >= maxT) { break; }
        let h = map(ro + rd * s, complex, gearRatio, t);
        res = min(res, 8.0 * h / s);
        if (res < 0.01) { break; }
        s += clamp(h, 0.02, 0.3);
    }
    return clamp(res, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let uv = (vec2<f32>(coords) - vec2<f32>(res) * 0.5) / f32(res.y);

    // Uniforms mapping
    let complex = u.zoom_params.x;  // Mechanical Complexity
    let clockSpd = u.zoom_params.y; // Clock Speed
    let plasmaInt = u.zoom_params.z; // Plasma Intensity
    let gearRatio = u.zoom_params.w; // Gear Ratio

    let time = u.config.x * clockSpd;
    let audio = plasmaBuffer[0].x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let uv01 = (vec2<f32>(coords) + 0.5) / vec2<f32>(res);
    let aspect = f32(res.x) / max(f32(res.y), 1.0);
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(delta) - age * (0.14 + clockSpd * 0.12));
            shock += (1.0 - smoothstep(0.0, 0.026, ring)) * (1.0 - age / 3.0);
        }
    }
    shock = min(shock, 2.0);

    // Snapping Rotation (stepped time + audio kick)
    let steppedTime = floor(time) + smoothstep(0.8, 1.0, fract(time)) * 1.0;
    let rotAngle = steppedTime * 0.5 + audio * 2.0 + bass * 0.5 + shock * 0.45;

    // Mouse orbit (x = yaw, y = pitch). HEAD called this a "Y-flip" but it
    // never negated anything; behaviour kept as-is, the false claim removed.
    let mousePos = (u.zoom_config.yz * 2.0 - vec2<f32>(1.0, 1.0)) * 3.14;
    let mouseYFlipped = vec2<f32>(mousePos.x, mousePos.y);

    // Camera Setup
    var ro = vec3<f32>(0.0, 0.0, 5.0 - held * 0.75);
    ro = ro * rotX(mouseYFlipped.y) * rotY(mouseYFlipped.x + rotAngle * 0.1);

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.0 * ww);

    // Raymarching with volumetric integration
    var t = 0.0;
    var p = ro;
    var coreDist = 1000.0;
    var hit = false;
    var volAccum = 0.0;
    let plasmaDrive = plasmaInt * (1.0 + audio);

    // Idea 2: Beer-Lambert transmittance + emission integrated along the ray.
    var trans = vec3<f32>(1.0);
    var inscatter = vec3<f32>(0.0);
    // Fix: the orbit (radius 5, 4.25 held) passes through the KIFS reach (~8),
    // so at default sliders ~6% of camera poses start INSIDE brass and the
    // whole frame became one flat hit at t=0. Skip the solid the camera is in
    // (a near-clip) before sphere tracing starts.
    var escaping = true;

    for (var i = 0; i < 120; i++) {
        p = ro + rd * t;
        let md = mapFull(p, complex, gearRatio, time);
        let d = md.x;

        // Track closest distance to core singularity (reused from mapFull)
        let dCore = md.y;
        coreDist = min(coreDist, dCore);

        if (escaping) {
            if (d < 0.0) {
                t += max(-d, 0.02);
                continue;
            }
            escaping = false;
        }

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 30.0) { break; }

        // Inside the plasma shell the step is capped so the medium is sampled
        // (the core is carved out of map(), so d alone would leap across it).
        var dt = max(d, 0.001);
        if (dCore < 1.0) { dt = min(dt, 0.1); }

        // Idea 2: emission is hot (yellow) where the plasma is dense and
        // violet at the fringe; each channel is extinguished at its own rate.
        let rho = plasmaDensity(dCore) * plasmaDrive;
        if (rho > 1e-4) {
            let emit = getPlasmaColor(rho * 1.4, time) * rho * 1.6;
            inscatter += trans * emit * dt;
            trans *= exp(-PLASMA_SIGMA * rho * 2.2 * dt);
        }

        t += dt;
    }

    var color = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p, complex, gearRatio, time);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let refl = reflect(rd, n);
        let spec = pow(max(dot(refl, lightDir), 0.0), 64.0);

        // Metallic Brass with Fresnel
        let baseColor = vec3<f32>(0.8, 0.6, 0.2);
        // Idea 3: real brass f0 (HEAD labelled a steel-grey 0.56 "Brass F0"),
        // so both the key and the core highlights come back gold-tinted.
        let f0 = vec3<f32>(0.91, 0.76, 0.40);
        let cosTheta = max(dot(-rd, n), 0.0);
        let fresnel = fresnelSchlick(cosTheta, f0);

        color = baseColor * diff + fresnel * spec * 2.0;

        // Idea 3: the plasma core is a light source. Brass is lit from the
        // direction of the singularity, with inverse-square falloff, radial
        // lattice shadows, and the core light reddened by the plasma it
        // crosses on the way out (analytic optical depth of plasmaDensity).
        let rC = length(p);
        let toCore = -p / max(rC, 1e-3);
        let coreDiff = max(dot(n, toCore), 0.0);
        if (coreDiff > 0.0 && plasmaDrive > 0.0) {
            let shell = max(rC - 0.5, 0.0);
            let tauC = plasmaDrive * 2.2 * (1.0 - exp(-3.0 * min(shell, 1.0))) / 3.0;
            let coreTrans = exp(-PLASMA_SIGMA * tauC);
            let falloff = 1.0 / (1.0 + 0.4 * shell * shell);
            let shadow = coreShadow(p + n * 0.004, toCore, shell, complex, gearRatio, time);
            let coreSpec = pow(max(dot(refl, toCore), 0.0), 24.0);
            let coreLight = getPlasmaColor(0.85, time) * coreTrans * falloff * shadow * plasmaDrive * 3.0;
            color += (baseColor * coreDiff + fresnel * coreSpec * 1.5) * coreLight;
        }

        // Ambient Occlusion with enhanced detail
        let ao = calcAO(p, n, complex, gearRatio, time);
        color = color * ao;

        // Surface detail from Voronoi
        let voro = voronoi3(p * 5.0 + time * 0.05);
        let surfaceDetail = smoothstep(0.05, 0.0, voro.x) * 0.15;
        color += vec3<f32>(0.9, 0.7, 0.3) * surfaceDetail * ao;

        // Domain-warped noise for weathering
        let weather = fbm_dw3(p * 8.0, time);
        color = mix(color, color * 0.7, weather * 0.3);

        // Idea 1: plasma conduits — the F2-F1 borders of the same Voronoi
        // cells (F2 was computed and never read) are glowing seams carrying
        // plasma out from the core: pulses travel outward along the radius,
        // and the feed dims with distance from the singularity.
        let seam = voro.y - voro.x;
        let conduit = (1.0 - smoothstep(0.0, 0.04, seam)) + 0.25 * (1.0 - smoothstep(0.0, 0.12, seam));
        let pulse = 0.5 + 0.5 * sin(rC * 9.0 - time * 4.0);
        let feed = exp(-max(rC - 0.5, 0.0) * 0.45);
        let conduitHeat = clamp(feed * (0.35 + 0.65 * pulse), 0.0, 1.0);
        let conduitGlow = conduit * (0.3 + 0.7 * pulse) * (0.4 + 0.6 * feed) * plasmaDrive * 3.2;
        color += getPlasmaColor(conduitHeat, time) * conduitGlow * mix(0.6, 1.0, ao);

        // Idea 2: brass seen through the plasma is dimmed and reddened.
        color *= trans;
    }

    // Volumetric Glow (Plasma Core) with Beer-Lambert
    if (coreDist < 1.5) {
        let glowStrength = clamp(1.0 - coreDist / 1.5, 0.0, 1.0) * plasmaInt * (1.0 + audio);
        let plasmaCol = getPlasmaColor(glowStrength, time);
        // Fix: HEAD fed a negative coreDist (rays through the core) into exp(),
        // a gain of up to ~7x that clipped the core to flat white.
        let extinction = beerLambert(max(coreDist, 0.0) * 2.0, 1.5 + bass * 0.5);
        color += plasmaCol * glowStrength * 2.0 * extinction;
    }
    // Idea 2: integrated plasma emission replaces the per-step volAccum sum.
    color += inscatter;
    volAccum = 1.0 - dot(trans, vec3<f32>(1.0 / 3.0)); // plasma opacity along the ray

    // Audio-reactive bloom on hit surfaces
    if (hit && bass > 0.3) {
        let bloom = bass * 0.2 * exp(-t * 0.1);
        color += vec3<f32>(1.0, 0.8, 0.3) * bloom;
    }

    let gearTick = pow(0.5 + 0.5 * cos(atan2(uv.y, uv.x) * (8.0 + floor(complex * 12.0)) - time * 7.0), 20.0);
    color += vec3<f32>(1.0, 0.48, 0.08) * gearTick * shock * (0.3 + treble * 0.6);
    color += vec3<f32>(0.25, 0.65, 1.0) * held * exp(-length(uv) * 5.0) * (0.2 + mids * 0.4);

    // ACES filmic display mapping, then exact previous-frame feedback.
    // Fix: A holds ACES display colour, so C is blended in display space
    // (HEAD mixed display C into HDR and tone-mapped it a second time).
    color = acesToneMap(color * 1.2);
    let prev = textureLoad(dataTextureC, coords, 0);
    color = mix(color, prev.rgb * 0.94, 0.05 + bass * 0.02);

    let _luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha = clamp(_luma * 0.55 + select(0.04, 0.42, hit) + volAccum * 0.5 + shock * 0.25, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(color, _alpha));
    // Fix: real march depth (near = 1, miss = 0). HEAD clamped the centred
    // uv into 0..1 and passed the input depth through.
    let _depth = select(0.0, clamp(1.0 - t / 30.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coords, vec4<f32>(_depth, 0.0, 0.0, 0.0));
    // Write to dataTextureA for temporal feedback
    textureStore(dataTextureA, coords, vec4<f32>(color, _alpha));
}
