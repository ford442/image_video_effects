// ═══════════════════════════════════════════════════════════════════
//  Astro-Mechanical Quantum-Furnace Engine — Batch 63
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: refraction through the plasma core (gears and pillar seen bent through the furnace); meshing gear train (gears turn on their axles, fold-mirrored neighbours and alternate KIFS levels counter-rotate); piston-chuff exhaust (pillar always streams and puffs 4x per gear revolution)
//  A packing: raw HDR trail RGB (pre-ACES, clamped 0..64) + semantic alpha; C read back as HDR
// ═══════════════════════════════════════════════════════════════════
// KIFS gear-train around a plasma furnace, run hot and fast:
// psychedelic exhaust spectra, riveted gear greeble, cursor magnetic
// well, held overdrive, capped click detonation rings.
// Contract: 13 bindings, ACES on display only, semantic alpha, dataTextureA
//           writeback only, exact textureLoad from dataTextureC, plasmaBuffer
//           three-band audio. The extraBuffer[133..138] spring below is INERT:
//           the engine zeroes extraBuffer[133..] every frame, so the cursor is raw.
// ----------------------------------------------------------------

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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Gear Complexity, y=Plasma Intensity, z=Refraction Index, w=Emission Threshold
    ripples: array<vec4<f32>, 50>,
};

// --- Math & Noise Helpers ---

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Inert: extraBuffer[133..255] is zeroed every frame by the engine.
const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

// Idea 2/3: one shared gear clock drives axle turn and exhaust beat
const GEAR_TURN: f32 = 1.6;        // rad/s each gear turns on its own axle
const CHUFFS_PER_REV: f32 = 4.0;   // exhaust puffs per gear revolution
const CHUFF_SPACING: f32 = 5.0;    // world units between puffs along the pillar

var<private> g_bass: f32;
var<private> g_mids: f32;
var<private> g_treble: f32;
var<private> g_held: f32;
var<private> g_blast: f32;
var<private> g_skipCore: f32;      // Idea 1: 1 while marching the view behind the core

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic furnace spectrum — molten wheel spun by the audio
fn furnacePalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.05, 1.85 + drive * 1.3, 3.95 - drive * 1.0);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n = i.x + i.y * 157.0 + i.z * 113.0;

    let a = hash3(vec3<f32>(n)).x;
    let b = hash3(vec3<f32>(n + 1.0)).x;
    let c = hash3(vec3<f32>(n + 157.0)).x;
    let d = hash3(vec3<f32>(n + 158.0)).x;
    let e = hash3(vec3<f32>(n + 113.0)).x;
    let f1 = hash3(vec3<f32>(n + 114.0)).x;
    let g = hash3(vec3<f32>(n + 270.0)).x;
    let h = hash3(vec3<f32>(n + 271.0)).x;

    let res = mix(
        mix(mix(a, b, w.x), mix(c, d, w.x), w.y),
        mix(mix(e, f1, w.x), mix(g, h, w.x), w.y),
        w.z
    );
    return res * 2.0 - 1.0;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for(var i = 0; i < 4; i++) {
        f += amp * noise3D(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// --- SDF Scene ---

struct MapData {
    d: f32,
    mat: f32, // 0 = void/dust, 1 = gears, 2 = plasma core
    glow: f32,
    core: f32, // Idea 1: 1 when the hit is the core sphere (not the exhaust pillar)
    ang: f32   // Idea 2: local gear angle incl. axle turn (tooth phase)
}

fn coreRadiusOf(audio: f32) -> f32 {
    return 2.0 + audio * 0.6 + g_blast * 0.5;
}

fn map(p: vec3<f32>, time: f32, audio: f32, gearComplexity: f32, mouseXY: vec2<f32>) -> MapData {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;
    var isCore = 0.0;

    var pos = p;

    // Magnetic distortion well at the cursor — held deepens it
    let gravityWell = vec3<f32>(mouseXY.x * 10.0, -mouseXY.y * 10.0, 0.0);
    let distToMouse = length(pos - gravityWell);
    let warpAmt = exp(-distToMouse * 0.2) * (1.0 + g_held * 1.5 + g_blast * 1.2);
    pos += normalize(pos - gravityWell + vec3<f32>(1e-4)) * warpAmt * sin(time * 6.0);

    // Core plasma furnace (removed while Idea 1 marches the view behind it)
    let coreRadius = coreRadiusOf(audio);
    var dCore = 1000.0;
    if (g_skipCore < 0.5) {
        let coreWarp = fbm(pos * 2.0 - time * 3.0);
        dCore = length(pos) - coreRadius + coreWarp * 0.8;
    }

    // KIFS fractal gears — spin rate scales with bass and the held throttle
    var q = pos;
    let spin = time * (1.2 + g_bass * 1.6 + g_held * 1.0);
    let new_xz1 = rot(spin) * vec2<f32>(q.x, q.z);
    q.x = new_xz1.x;
    q.z = new_xz1.y;
    let new_xy = rot(spin * 0.75) * vec2<f32>(q.x, q.y);
    q.x = new_xy.x;
    q.y = new_xy.y;

    let iterations = i32(mix(2.0, 6.0, clamp(gearComplexity, 0.0, 1.0)));
    var scale = 1.0;

    for(var i = 0; i < 6; i++) {
        if (i >= iterations) { break; }
        q = abs(q) - 1.5 * pow(0.6, f32(i));

        let a = dot(q, vec3<f32>(1.0)) * 0.5;
        q -= 2.0 * min(0.0, a) * vec3<f32>(1.0);
        q = q * 1.4;
        scale *= 1.4;

        // Idea 2: alternate KIFS levels counter-rotate, deeper (smaller) trains
        // faster by the 1.4 per-level gear ratio
        let meshDir = select(1.0, -1.0, (i & 1) == 1);
        let levelTurn = meshDir * time * 0.05 * pow(1.4, f32(i));
        let new_xz2 = rot(0.2 + f32(i) * 0.05 + levelTurn) * vec2<f32>(q.x, q.z);
        q.x = new_xz2.x;
        q.z = new_xz2.y;
    }

    var dGears = sdTorus(q, vec2<f32>(3.0, 0.5)) / scale;

    // Gear greeble: cut teeth and rivet rows along the torus (geometric detail)
    // Idea 2: the tooth phase advances with the axle turn. The torus is axially
    // symmetric, so only teeth and rivets move: each gear turns in place, and the
    // abs() mirror folds hand neighbours the opposite sense -> meshing pairs.
    let gearAngle = atan2(q.z, q.x) - time * GEAR_TURN;
    let teeth = abs(sin(gearAngle * 26.0));
    let rivets = sin(gearAngle * 13.0) * sin(q.y * 22.0);
    dGears -= (teeth * 0.06 + rivets * 0.03) / scale;

    // Exhaust streams
    var pStream = pos;
    pStream.y -= time * 14.0;
    let streamNoise = fbm(pStream * 3.0);
    // Idea 3: piston-chuff exhaust — turbulence floor so the pillar streams at
    // audio=0, plus puffs fired CHUFFS_PER_REV times per gear revolution that
    // travel up the pillar (locomotive exhaust beat driven by the gear clock)
    let chuffPhase = fract(time * GEAR_TURN * CHUFFS_PER_REV / TAU - pos.y / CHUFF_SPACING);
    let chuffX = (chuffPhase - 0.5) * 5.0;
    let chuff = exp(-chuffX * chuffX);
    let dStreams = length(pos.xz) - 0.5 - (0.25 + audio) * streamNoise * 2.2 - chuff * 0.55;

    dGears = max(dGears, -(length(pos) - coreRadius - 0.5)); // carve the core cavity

    if (dCore < dGears && dCore < dStreams) {
        d = dCore;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dCore), 2.0);
        isCore = 1.0;
    } else if (dGears < dStreams) {
        d = dGears;
        mat = 1.0;
    } else {
        d = dStreams;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dStreams), 2.0);
    }

    return MapData(d * 0.6, mat, glow, isCore, gearAngle); // safe step
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio, complexity, mouse).d;
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, complexity, mouse).d - d,
        map(p + e.yxy, time, audio, complexity, mouse).d - d,
        map(p + e.yyx, time, audio, complexity, mouse).d - d
    );
    return normalize(n);
}

// --- Shading (HEAD arithmetic, factored so Idea 1 can shade the refracted view) ---

// Metallic brass shading, spectrally graded. Returns (rgb, fresnel).
fn shadeBrass(p: vec3<f32>, n: vec3<f32>, rd: vec3<f32>, hue: f32, refIndex: f32, iterFrac: f32, gearAng: f32) -> vec4<f32> {
    let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
    let diff = max(dot(n, lightDir), 0.0);
    let refl = reflect(rd, n);
    let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);
    let fre = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

    let baseColor = mix(vec3<f32>(0.8, 0.6, 0.2), furnacePalette(hue, g_mids), 0.45);
    let envWarp = fbm(refl * max(refIndex, 0.01));

    var col = baseColor * diff * 0.6 + vec3<f32>(1.0) * spec * 0.4 + baseColor * envWarp * 0.2;
    col += furnacePalette(hue + 0.3, g_treble) * fre * 0.7;

    // Tooth/rivet banding — surfaces the carved gear greeble
    // Idea 2: read the local (turning) gear angle so the stripes ride the teeth
    let band = 0.5 + 0.5 * sin(gearAng * 26.0);
    col *= 0.82 + band * 0.36;

    let ao = clamp(1.0 - iterFrac, 0.0, 1.0);
    col *= ao;
    return vec4<f32>(col, fre);
}

// Quantum plasma core — white-hot centre bleeding into the spectrum
fn shadePlasma(hue: f32) -> vec3<f32> {
    return mix(vec3<f32>(1.0), furnacePalette(hue + 0.5, 1.0 + g_bass), 0.45) * (1.5 + g_bass * 0.8);
}

// Deep space nebula void
fn nebula(rd: vec3<f32>, time: f32) -> vec3<f32> {
    let starNoise = fbm(rd * 50.0 + time * 0.4);
    var col = mix(vec3<f32>(0.0), furnacePalette(fract(time * 0.03), g_mids) * 0.2, fbm(rd * 5.0 - time * 0.2) * 0.5 + 0.5);
    col += vec3<f32>(1.0) * pow(max(starNoise - 0.8, 0.0) * 5.0, 3.0);
    return col;
}

fn surfaceHue(p: vec3<f32>, time: f32, blast: f32) -> f32 {
    return fract(length(p) * 0.1 + time * (0.2 + g_mids * 0.8) + blast * 0.4);
}

// --- Main Compute ---

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }

    let coord = vec2<i32>(id.xy);
    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv01 = fragCoord / res;
    let uv = (fragCoord - 0.5 * res) / res.y;
    let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);

    let time = u.config.x;
    g_skipCore = 0.0;

    // Three-band audio — plasmaBuffer, never config.y (that is rippleCount)
    g_bass = plasmaBuffer[0].x;
    g_mids = plasmaBuffer[0].y;
    g_treble = plasmaBuffer[0].z;
    let audio = g_bass * 0.6 + g_mids * 0.3 + g_treble * 0.2;

    // UI Sliders
    let gearComplexity = u.zoom_params.x;
    let plasmaIntensity = u.zoom_params.y;
    let refIndex = u.zoom_params.z;
    let emissionThresh = u.zoom_params.w;

    let rawMouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    // ── spring cursor (extraBuffer[133..138]) — INERT: the engine zeroes this
    //    range every frame, so SPRING_INIT reads 0 and smoothMouse == rawMouse ──
    var smoothMouse = rawMouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    }
    if (hasSpring && id.x == 0u && id.y == 0u) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
        if (extraBuffer[SPRING_INIT] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
            let omega = 9.5;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[SPRING_X] = springPos.x;
        extraBuffer[SPRING_Y] = springPos.y;
        extraBuffer[SPRING_VX] = springVel.x;
        extraBuffer[SPRING_VY] = springVel.y;
        extraBuffer[SPRING_T] = time;
        extraBuffer[SPRING_INIT] = 1.0;
        smoothMouse = springPos;
    }
    // Mouse UV is 0..1 top-down; map straight to centred coords (no resolution divide)
    let mouseNorm = smoothMouse * 2.0 - 1.0;

    // ── click detonation rings (capped, bounded) ───────────────────────
    var blast = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.2) {
            let front = abs(length((uv01 - rp.xy) * aspect) - age * 1.0);
            blast = max(blast, exp(-front * 30.0) * (1.0 - age / 1.2));
        }
    }
    blast = min(blast, 1.0);
    g_blast = blast;

    // Camera — orbits fast, cursor tilts it, held pulls in
    var ro = vec3<f32>(0.0, 0.0, 12.0 - g_held * 2.0 + blast * 1.5);
    let orbit = rot(time * (0.35 + g_bass * 0.7) + (smoothMouse.x - 0.5) * 1.6) * ro.xz;
    ro.x = orbit.x;
    ro.z = orbit.y;
    ro.y = (0.5 - smoothMouse.y) * 6.0;

    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch
    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var hitCore = 0.0;
    var hitAng = 0.0;
    var totalGlow = 0.0;
    var iter = 0;

    for(var i = 0; i < 120; i++) {
        iter = i;
        let p = ro + rd * t;
        let resData = map(p, time, audio, gearComplexity, mouseNorm);
        d = resData.d;
        mat = resData.mat;
        hitCore = resData.core;
        hitAng = resData.ang;

        if (resData.mat == 2.0) {
            totalGlow += resData.glow * 0.05 * plasmaIntensity;
        }

        if (d < 0.001 || t > 30.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var fre = 0.0;

    if (t < 30.0) {
        let p = ro + rd * t;
        let n = getNormal(p, time, audio, gearComplexity, mouseNorm);
        let hue = surfaceHue(p, time, blast);

        if (mat == 1.0) {
            let sb = shadeBrass(p, n, rd, hue, refIndex, f32(iter) / 120.0, hitAng);
            col = sb.rgb;
            fre = sb.w;
        } else if (mat == 2.0) {
            let coreCol = shadePlasma(hue);
            col = coreCol;

            if (hitCore > 0.5) {
                // Idea 1: refraction through the plasma core. Enter through the
                // fbm-bumped surface (heat shimmer), cross the core sphere, bend
                // again on exit, then re-march the machine with the core removed.
                let ior = max(refIndex, 1.0);
                var rdIn = refract(rd, n, 1.0 / ior);
                if (dot(rdIn, rdIn) < 1e-4) { rdIn = rd; }
                rdIn = normalize(rdIn);

                let rc = coreRadiusOf(audio);
                let b = dot(p, rdIn);
                let c = dot(p, p) - rc * rc;
                let tExit = max(-b + sqrt(max(b * b - c, 0.0)), 0.0);
                let pExit = p + rdIn * tExit;
                let nExit = normalize(pExit + vec3<f32>(1e-4));
                var rdOut = refract(rdIn, -nExit, ior);
                // No TIR beat here (not this effect's idea): pass the internal ray on
                if (dot(rdOut, rdOut) < 1e-4) { rdOut = rdIn; }
                rdOut = normalize(rdOut);

                g_skipCore = 1.0;
                let ro2 = pExit + rdOut * 0.02;
                var t2 = 0.0;
                var mat2 = 0.0;
                var ang2 = 0.0;
                var iter2 = 0;
                var hit2 = false;
                for (var j = 0; j < 64; j++) {
                    iter2 = j;
                    let r2 = map(ro2 + rdOut * t2, time, audio, gearComplexity, mouseNorm);
                    mat2 = r2.mat;
                    ang2 = r2.ang;
                    if (r2.d < 0.002) { hit2 = true; break; }
                    if (t2 > 30.0) { break; }
                    t2 += r2.d;
                }

                var behind = nebula(rdOut, time);
                if (hit2) {
                    let p2 = ro2 + rdOut * t2;
                    let hue2 = surfaceHue(p2, time, blast);
                    if (mat2 == 1.0) {
                        let n2 = getNormal(p2, time, audio, gearComplexity, mouseNorm);
                        behind = shadeBrass(p2, n2, rdOut, hue2, refIndex, f32(iter2) / 64.0, ang2).rgb;
                    } else {
                        behind = shadePlasma(hue2);
                    }
                }
                g_skipCore = 0.0;

                // Seen through incandescent plasma: heat-tinted, composited by
                // facing ratio only — the limb stays opaque white-hot
                let heat = mix(vec3<f32>(1.0), furnacePalette(hue + 0.5, 1.0 + g_bass), 0.45) * 1.3;
                let facing = max(dot(n, -rd), 0.0);
                let window = 0.42 * facing * facing;
                col = mix(coreCol, behind * heat, window);
            }
        }
    } else {
        col = nebula(rd, time);
    }

    // Volumetric exhaust glow
    let glowColor = furnacePalette(fract(time * 0.25 + totalGlow * 0.3), 1.0 + g_treble);
    col += glowColor * totalGlow * step(emissionThresh, totalGlow);

    // Detonation flash + cursor magnetic halo
    col += furnacePalette(fract(time * 1.1), 1.0) * blast * 1.5;
    let cursorDist = length((uv01 - smoothMouse) * aspect);
    col += furnacePalette(fract(time * 0.45 + cursorDist), g_bass) * exp(-cursorDist * 7.5) * (0.12 + g_held * 0.5);

    // Cinematic vignette
    col *= 1.0 - smoothstep(0.5, 1.5, length(uv));

    // ── temporal motion blur — exact load from dataTextureC, no filtering ─
    // C holds last frame's raw HDR (A packing below), so the blend stays in HDR
    // and ACES is applied exactly once (HEAD tone-mapped the trail twice).
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(prev.rgb * 0.94, col, 0.45 + g_bass * 0.15);
    let hdrTrail = clamp(col, vec3<f32>(0.0), vec3<f32>(64.0));

    let display = acesToneMap(hdrTrail * (1.1 + g_mids * 0.25));

    // Semantic alpha: machine presence + furnace emission
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.0, 0.45 + fre * 0.3, t < 30.0)
        + luma * 0.45 + min(totalGlow, 2.0) * 0.15 + blast * 0.3,
        0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrTrail, alpha));

    // Depth: near = 1, miss/far = 0 (HEAD wrote miss = 1.0)
    let depth = select(0.0, clamp(1.0 - t / 30.0, 0.005, 1.0), t < 30.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
