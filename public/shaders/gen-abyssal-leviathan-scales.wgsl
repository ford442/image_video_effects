// ----------------------------------------------------------------
// Abyssal Leviathan-Scales — Batch 63
// Category: generative
// Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
// Complexity: High
// Upgraded: 2026-10-18
// Ideas: chromatic dispersion split on the thin-film sheen at grazing
//        fresnel angles; fading molt-scar crack glow on scales recently
//        crossed by a breach ring (time since the ring front passed +
//        per-cell hash); held-flare micro-ridging that sharpens keel/facet
//        frequency under the cursor while held; growth annuli + radii
//        (each scale carries its own count of crowded seasonal bands and
//        radial grooves fanning from the focus to the anterior margin);
//        lateral-line canal (one longitudinal row of pored scales whose
//        neuromasts flare as breach pressure rings pass)
// A packing: display RGBA (temporal max-hold color + semantic alpha)
// A hexagonal scale conveyor over a fissured plasma bed, driven at
// speed: psychedelic thin-film spectra, greebled scale ridging,
// cursor repulsion wake, held flare, capped click breach rings.
// Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//           exact textureLoad from dataTextureC, plasmaBuffer three-band audio.
// ----------------------------------------------------------------
#include "_prelude.wgsl"
// zoom_params: x=Scale Density, y=Plasma Intensity, z=Conveyor Speed, w=Core Heat

const TAU: f32 = 6.28318530718;

// Lateral-line canal runs along the hex column one scale-spacing left of centre.
const LATERAL_COLUMN: f32 = -1.0;

// --- UTILITY FUNCTIONS ---
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }
// Floored modulo: WGSL `%` truncates, which broke the hex lattice for x < 0.
fn modFloor(a: vec2<f32>, m: vec2<f32>) -> vec2<f32> { return a - m * floor(a / m); }
fn rot2D(a: f32) -> mat2x2<f32> { let c = cos(a); let s = sin(a); return mat2x2<f32>(c, -s, s, c); }

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u2 = f*f*(vec3<f32>(3.0)-2.0*f); let n = i.x + i.y*157.0 + 113.0*i.z;
    return mix(mix(mix(hash31(vec3<f32>(n+0.0)), hash31(vec3<f32>(n+1.0)), u2.x), mix(hash31(vec3<f32>(n+157.0)), hash31(vec3<f32>(n+158.0)), u2.x), u2.y), mix(mix(hash31(vec3<f32>(n+113.0)), hash31(vec3<f32>(n+114.0)), u2.x), mix(hash31(vec3<f32>(n+270.0)), hash31(vec3<f32>(n+271.0)), u2.x), u2.y), u2.z);
}
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0; var w = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) { f += w * noise3(pp); pp *= 2.0; w *= 0.5; }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic thin-film / plasma spectrum
fn scalePalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.15, 2.0 + drive * 1.2, 4.2 - drive * 0.8);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

// --- SDF FUNCTIONS ---
fn sdScale(p: vec3<f32>, size: vec2<f32>) -> f32 {
    let d = vec2<f32>(length(p.xz), p.y);
    return length(max(abs(d) - size, vec2<f32>(0.0))) + min(max(abs(d.x) - size.x, abs(d.y) - size.y), 0.0) - 0.1;
}

var<private> g_time: f32;
var<private> g_audio: vec3<f32>;
var<private> g_mouse: vec2<f32>;
var<private> g_mouseWorld: vec2<f32>;
var<private> g_held: f32;
var<private> g_breach: f32;

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let scaleDensity = max(1.0, u.zoom_params.x);
    let breathingSpeed = u.zoom_params.z;
    let spacing = 10.0 / scaleDensity;

    // Hexagonal grid setup on XZ plane
    let grid = vec2<f32>(1.0, 1.7320508) * spacing;
    let h1 = modFloor(p.xz, grid) - grid * 0.5;
    let h2 = modFloor(p.xz + grid * 0.5, grid) - grid * 0.5;
    var cellPos = h1;
    var cellId = floor(p.xz / grid);
    if (length(h1) > length(h2)) {
        cellPos = h2;
        cellId = floor((p.xz + grid * 0.5) / grid) + 0.5;
    }

    var q = p;
    q.x = cellPos.x;
    q.z = cellPos.y;

    // Fast conveyor wave: rows snap over in bursts, breach events accelerate them
    let fbmVal = fbm(vec3<f32>(cellId.x, cellId.y, g_time * breathingSpeed * 0.9));
    let rowSpeed = 8.5 + breathingSpeed * 4.0 + g_audio.x * 3.5 + g_breach * 6.0;
    let rowWave = sin(cellId.y * 1.7 - g_time * rowSpeed);
    let localTime = g_time * breathingSpeed * 3.5 + fbmVal * 6.28 + rowWave * 0.8;

    var lift = sin(localTime) * 0.2 + 0.2 + max(rowWave, 0.0) * (0.22 + g_audio.x * 0.16);
    var tilt = cos(localTime) * 0.3 + rowWave * 0.28;

    // Mouse repulsion — the cursor shoves scales open ahead of it
    let distToMouse = length(p.xz - g_mouseWorld);
    // Hover nudges about one scale; holding throws the full wake open.
    let repel = 1.0 - smoothstep(0.0, mix(1.8, 7.5, g_held), distToMouse);
    lift += repel * mix(0.35, 2.7, g_held);
    tilt += repel * mix(0.4, 2.3, g_held);

    q.y -= lift;
    let rM = rot2D(tilt);
    let tmp = rM * vec2<f32>(q.y, q.z);
    q.y = tmp.x;
    q.z = tmp.y;

    // Scale SDF with concentric keel ridging (geometric detail)
    let size = vec2<f32>(spacing * 0.45, 0.05);
    var dScale = sdScale(q, size);
    // Held-flare micro-ridging: sharper, taller keel/facet frequency under the
    // held cursor, using the repulsion field already computed above.
    let ridgeBoost = 1.0 + repel * g_held * 1.8;
    let keel = sin(length(q.xz) * 34.0 * ridgeBoost - g_time * 5.0) * 0.006 * ridgeBoost;
    let facets = sin(atan2(q.z, q.x) * 12.0 * ridgeBoost) * 0.004 * ridgeBoost;
    dScale -= keel + facets;

    // Plasma bed, domain-warped and fissured
    let plasmaWarp = fbm(p * 0.5 + vec3<f32>(g_time * 1.6, 0.0, -g_time * 7.5));
    let fissure = pow(abs(sin(p.x * 2.4 + p.z * 1.2 - g_time * (14.0 + g_audio.z * 4.0))), 12.0);
    let dPlasma = p.y + 1.0 - plasmaWarp * 0.5 - fissure * (0.08 + g_audio.y * 0.1);

    if (dScale < dPlasma) {
        return vec2<f32>(dScale * 0.6, 1.0);
    }
    return vec2<f32>(dPlasma * 0.6, 2.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let coord = vec2<i32>(id.xy);
    // y up: texture rows grow downward, so flip (HEAD rendered the floor at the top).
    var uv = (fragCoord * 2.0 - dims) / dims.y * vec2<f32>(1.0, -1.0);
    let dataUV = fragCoord / dims;
    let aspectFix = vec2<f32>(dims.x / max(dims.y, 1.0), 1.0);
    g_time = u.config.x;
    g_audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let rawMouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    // extraBuffer is re-uploaded every frame, so the old spring never held state.
    let smoothMouse = rawMouse;
    g_mouse = (smoothMouse - 0.5) * 2.0;

    // ── click breaches race down the conveyor (capped, bounded) ─────────
    // Molt scars are measured from the time since each ring front crossed
    // this pixel (the old A-alpha decay fed back on its own semantic alpha
    // and never let go).
    var breach = 0.0;
    var scar = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let ringSpeed = 1.1 + u.zoom_params.z * 0.3;
    for (var r = 0u; r < rippleCount; r++) {
        let ripple = u.ripples[r];
        let age = g_time - ripple.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let dist = length((dataUV - ripple.xy) * aspectFix);
        let front = abs(dist - age * ringSpeed);
        breach += exp(-front * 55.0) * max(1.0 - age * 0.5, 0.0);
        let since = age - dist / ringSpeed;
        scar += select(0.0, exp(-since * 2.5), since > 0.0);
    }
    breach = min(breach, 1.5);
    g_breach = breach;

    // Camera — the conveyor runs fast, audio and held throttle it further
    let runSpeed = 6.5 + u.zoom_params.z * 2.2 + g_audio.x * 1.6 + g_held * 2.5;
    var ro = vec3<f32>(0.0, 5.0, g_time * runSpeed);
    let ta = ro + vec3<f32>(g_mouse.x * 0.6, -1.0 + g_mouse.y * 0.3, 1.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // The cursor's ray meets the scale field ahead of the camera (HEAD scrolled
    // the wake at 3.4/s while the camera ran at ~9/s, so it fell behind view).
    let mUv = (smoothMouse * 2.0 - 1.0) * vec2<f32>(dims.x / max(dims.y, 1.0), -1.0);
    let rdM = normalize(mUv.x * uu + mUv.y * vv + 1.5 * ww);
    let tGround = ro.y / max(-rdM.y, 0.12);
    g_mouseWorld = ro.xz + rdM.xz * tGround;

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var glow = 0.0;
    let maxT = 30.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (m == 2.0) {
            glow += min(0.12, 0.004 / (0.01 + abs(d)));
        }
        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var fres = 0.0;
    let plasmaIntensity = u.zoom_params.y;
    let coreHeat = u.zoom_params.w;
    let audioPulse = 1.0 + g_audio.x * 1.5;

    let prev = textureLoad(dataTextureC, coord, 0);
    let scarEnergy = clamp(max(scar, breach), 0.0, 1.5);

    if (t < maxT) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        if (m == 1.0) {
            // Oily metallic scale — thin-film interference pushed into full spectrum
            let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let h = normalize(l + v);
            let ndotl = max(dot(n, l), 0.0);
            let ndoth = max(dot(n, h), 0.0);
            fres = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            let filmT = fres * 2.4 + g_time * (0.25 + g_audio.z * 0.9) + p.z * 0.05;
            // Chromatic dispersion: split the thin-film phase per channel,
            // scaled by fresnel so grazing angles separate like real oil-slick
            // spectra instead of one locked-phase cosine palette.
            let dispersion = fres * 0.35;
            let sheen = vec3<f32>(
                scalePalette(filmT - dispersion, g_audio.y * 1.4).x,
                scalePalette(filmT, g_audio.y * 1.4).y,
                scalePalette(filmT + dispersion, g_audio.y * 1.4).z
            );
            let diff = vec3<f32>(0.05, 0.05, 0.06) * ndotl;
            let spec = sheen * pow(ndoth, 32.0) * 0.85;

            col = diff + spec + sheen * fres * 0.55;

            // Scale-local frame of the hit (same hex lattice as map()).
            let spacingL = 10.0 / max(1.0, u.zoom_params.x);
            let gridL = vec2<f32>(1.0, 1.7320508) * spacingL;
            let k1 = modFloor(p.xz, gridL) - gridL * 0.5;
            let k2 = modFloor(p.xz + gridL * 0.5, gridL) - gridL * 0.5;
            let local = select(k1, k2, length(k1) > length(k2));
            let center = p.xz - local;
            let rN = length(local) / (spacingL * 0.45);
            // Both hex sub-lattices put centres on multiples of half a cell, so
            // the rounded index is exact per scale (no flicker at large z).
            let cellIndex = round(center / (gridL * 0.5));
            let cellAge = hash21(cellIndex);

            // Keel ridging shading — reads the carved geometry back as highlight bands
            let ridge = 0.5 + 0.5 * sin(length(local) * 34.0 - g_time * 5.0);
            col *= 0.82 + ridge * 0.36;

            // ── Idea: growth annuli + radii ──
            // A scale grows by adding rings at its margin; slow seasons crowd
            // them into darker annuli, and radii grooves fan from the focus to
            // the anterior (oncoming) margin. Older scales carry more annuli.
            let annuli = 2.0 + floor(cellAge * 4.0);
            let crowd = pow(0.5 + 0.5 * cos(TAU * (rN * annuli + cellAge)), 6.0);
            let theta = atan2(local.x, -local.y);
            let radiiMask = pow(abs(cos(theta * 4.5)), 40.0)
                * smoothstep(0.15, 0.35, rN) * step(abs(theta), 1.2);
            let growth = smoothstep(1.05, 0.9, rN);
            col *= 1.0 - growth * (crowd * 0.45 + radiiMask * 0.55);
            col += sheen * crowd * growth * fres * 0.25;

            // ── Idea: lateral-line canal ──
            // One longitudinal row of scales is pierced by the canal: a pore at
            // each scale's focus joined by a raised tube. Its neuromasts sense
            // pressure, so they flare as breach rings and bass pass over them.
            let inLine = 1.0 - smoothstep(0.08, 0.12, abs(center.x / spacingL - LATERAL_COLUMN));
            let tube = (1.0 - smoothstep(0.035, 0.06, abs(local.x) / spacingL)) * growth;
            let poreR = rN / 0.16;
            let pore = 1.0 - smoothstep(0.7, 1.0, poreR);
            let poreRim = exp(-(poreR - 1.0) * (poreR - 1.0) * 18.0);
            let sense = 0.25 + g_audio.x * 0.5 + scarEnergy * 1.6 + g_breach * 1.5;
            col = mix(col, col * 0.55 + vec3<f32>(0.04, 0.05, 0.06), tube * inLine * 0.6);
            col *= 1.0 - pore * inLine * 0.9;
            col += scalePalette(filmT + 0.6, 1.0) * poreRim * inLine * sense;

            // Plasma bleed from below
            let plasmaProximity = exp(-p.y * 2.0);
            col += scalePalette(filmT + 0.45, 1.0) * plasmaProximity * 0.35 * plasmaIntensity * audioPulse;

            // Molt scar: a scale recently crossed by a breach ring keeps a
            // fading glowing crack, timed from when the ring front crossed
            // the pixel (stateless) and varied per scale by the lattice hash.
            let cellHashScar = cellAge;
            let scarGlow = scarEnergy * ridge * mix(0.6, 1.4, cellHashScar);
            col += scalePalette(filmT + 0.15, 1.0) * scarGlow * 0.7;

        } else if (m == 2.0) {
            // Quantum fusion core — fast runners across the fissures
            let runner = pow(abs(sin(p.z * 3.0 - g_time * 22.0 + p.x)), 16.0);
            let heat = (fbm(p * 2.0 - vec3<f32>(0.0, 0.0, g_time * 12.0)) + runner * 0.55) * coreHeat;
            let hue = fract(heat * 0.6 + g_time * (0.2 + g_audio.y * 0.7));
            col = scalePalette(hue, g_audio.z * 1.5) * heat * audioPulse * plasmaIntensity;
            col += scalePalette(hue + 0.4, 1.0) * pow(heat, 3.0) * audioPulse * plasmaIntensity;
        }
    }

    // Volumetric glow, spectrally graded
    col += scalePalette(g_time * 0.3 + glow * 0.2, g_audio.x) * min(glow, 4.0) * 0.1 * plasmaIntensity * audioPulse * coreHeat;

    // Background fade (fog)
    col = mix(col, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-t * 0.05));

    // Breach flash + cursor wake halo
    col += scalePalette(g_time * 0.8, 1.0) * breach * 1.2;
    let cursorDist = length((dataUV - smoothMouse) * aspectFix);
    col += scalePalette(g_time * 0.5 + cursorDist, g_audio.y) * exp(-cursorDist * 8.0) * (0.12 + g_held * 0.5);

    col = acesToneMap(col * (1.1 + g_audio.y * 0.25));

    // Semantic alpha: surface presence + plasma energy + persistent molt scar
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(
        select(0.85, 0.9 + fres * 0.1, t < maxT)
        + luma * 0.45 + min(glow, 2.0) * 0.15 + scarEnergy * 0.3,
        0.0, 1.0);

    // Exact previous frame (loaded above) keeps a decaying max-hold trail in A.
    let temporal = clamp(max(col, prev.rgb * 0.9), vec3<f32>(0.0), vec3<f32>(5.0));
    let depth = select(1.0, clamp(t / maxT, 0.0, 0.995), t < maxT);

    textureStore(dataTextureA, coord, vec4<f32>(temporal, alpha));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
