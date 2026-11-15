// ═══════════════════════════════════════════════════════════════════
//  Liquid Cathedral Dream
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-15
//  Ideas: leaded came panes in each window; molten glass drips below arches; pane-coloured god-ray shafts down the nave; dichroic hue shift across the pointer; seeded antique glass (trapped bubbles + reamy cord streaks); Tyndall dust motes drifting up inside the shafts
//  A packing: ACES display RGBA (C read back as melt-offset colour history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(TAU * (vec3<f32>(1.0, 0.78, 0.52) * t + vec3<f32>(0.0, 0.24, 0.55)));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

// One lattice layer of trapped glass bubbles ("seeds"): at most one bubble per lattice cell.
// Centre in [0.35, 0.65] and radius in [0.14, 0.27], so centre ± 1.3·radius stays inside the cell
// (the profile is < 0.3 % at the lattice line) — no bubble is ever sliced into a D-shape.
fn glassSeeds(gp: vec2<f32>, salt: vec2<f32>, density: f32) -> f32 {
    let gi = floor(gp);
    let gf = fract(gp);
    let h = hash21(gi + salt);
    let present = step(1.0 - density, h);
    let cen = vec2<f32>(0.35 + 0.3 * hash21(gi + salt + vec2<f32>(5.3, 1.1)), 0.35 + 0.3 * hash21(gi + salt + vec2<f32>(2.7, 8.9)));
    let r = 0.14 + 0.13 * hash21(gi + salt + vec2<f32>(9.1, 4.3));
    let d = length(gf - cen) / r;
    return present * (exp(-d * d * 4.0) + 0.6 * exp(-(d - 0.92) * (d - 0.92) * 36.0));
}

// One layer of floating dust motes: soft Gaussians that rise (screen +y is down, so the lattice
// scrolls with +t) and wobble continuously — no per-frame hashing, so no strobing. Centre + wobble
// stays in [0.27, 0.73] so the Gaussian is < 1.3 % at the lattice line; the cell index is wrapped
// at 64 so hash arguments stay small however long the piece runs.
fn dustMotes(wp: vec2<f32>, t: f32, scale: f32, speed: f32, salt: f32) -> f32 {
    let gp = vec2<f32>(wp.x * scale, wp.y * scale + t * speed);
    let gif = floor(gp);
    let gf = fract(gp);
    let gi = gif - 64.0 * floor(gif / 64.0);
    let h = hash21(gi + vec2<f32>(salt, salt * 1.7));
    let cen = vec2<f32>(0.35 + 0.3 * hash21(gi + vec2<f32>(7.1 + salt, 3.3)), 0.35 + 0.3 * hash21(gi + vec2<f32>(1.9, 9.2 + salt)))
            + vec2<f32>(sin(t * 0.6 + h * 40.0), cos(t * 0.5 + h * 31.0)) * 0.08;
    let d = length(gf - cen);
    return step(0.62, h) * exp(-d * d * 60.0) * (0.55 + 0.45 * sin(t * 1.7 + h * 50.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let spireDensity = u.zoom_params.x;
    let meltSpeed = u.zoom_params.y;
    let refraction = u.zoom_params.z;
    let stainedHue = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (4.0 + spireDensity * 4.0)) * u.zoom_config.w;
    let dragDirection = mouseDelta / mouseDistance;
    p -= dragDirection * dragMask * (0.05 + refraction * 0.16);

    let flowTime = time * (0.25 + meltSpeed * 1.8 + audio.y * 0.18);
    let melt = vec2<f32>(
        sin(p.y * 8.0 + flowTime * 1.3) + sin(p.y * 17.0 - flowTime),
        cos(p.x * 10.0 - flowTime * 0.8)
    ) * (0.015 + refraction * 0.065);
    let q = p + melt;
    let columns = 3.0 + floor(spireDensity * 9.0);
    let cellX = fract((q.x + 1.0) * columns * 0.5) - 0.5;
    let tierY = fract((q.y + flowTime * 0.08) * (3.0 + spireDensity * 3.0)) - 0.5;
    let archRadius = length(vec2<f32>(cellX * 1.25, max(tierY, 0.0) * 0.9));
    let arch = exp(-abs(archRadius - (0.27 + sin(flowTime + q.x * 4.0) * 0.035)) * (35.0 + spireDensity * 35.0));
    let spire = exp(-abs(cellX) * (28.0 + spireDensity * 34.0)) * smoothstep(0.5, -0.15, tierY);
    let window = smoothstep(0.43, 0.05, archRadius) * smoothstep(-0.45, 0.20, tierY);
    let glassPulse = 0.5 + 0.5 * sin(q.y * 19.0 - flowTime * 4.0 + cellX * 8.0);
    let roseAngle = atan2(tierY, cellX);
    let roseRadius = length(vec2<f32>(cellX, tierY));
    let roseTracery = pow(0.5 + 0.5 * cos(roseAngle * (6.0 + floor(spireDensity * 6.0)) + flowTime), 12.0) *
        exp(-abs(roseRadius - 0.24) * (32.0 + refraction * 28.0));
    let floorCaustic = pow(0.5 + 0.5 * sin(q.x * 28.0 + q.y * 11.0 - flowTime * 5.0), 16.0) * smoothstep(0.35, -0.42, tierY);

    // Idea 1: lead cames — radial + ring came lines split each window into panes, each pane its own hue.
    let columnId = floor((q.x + 1.0) * columns * 0.5);
    let tierId = floor((q.y + flowTime * 0.08) * (3.0 + spireDensity * 3.0));
    let paneCount = 4.0 + floor(spireDensity * 4.0);
    let paneCoord = (roseAngle / TAU + 0.5) * paneCount;
    let radialCameDist = abs(fract(paneCoord + 0.5) - 0.5) * roseRadius * TAU / paneCount;
    let ringCameDist = abs(roseRadius - 0.15);
    let cameDist = min(radialCameDist, ringCameDist);
    let came = (1.0 - smoothstep(0.005, 0.014 + refraction * 0.006, cameDist)) * window;
    let outerRing = step(0.15, roseRadius);
    let paneId = floor(paneCoord) + outerRing * paneCount;
    let paneHue = (hash21(vec2<f32>(paneId + columnId * 13.0, tierId * 7.0)) - 0.5) * 0.35;

    // Idea 2: molten glass drips — hashed drips hang past each arch edge, lengthening with melt and bass.
    let dripSlotCoord = (cellX + 0.5) * 4.0;
    let dripHash = hash21(vec2<f32>(columnId * 3.1 + floor(dripSlotCoord), tierId * 1.7));
    let dripLocalX = (fract(dripSlotCoord) - 0.5) * 0.25;
    let dripStart = 0.27;
    let dripLength = (0.04 + dripHash * 0.14) * (0.35 + meltSpeed * 0.9) * (1.0 + audio.x * 0.4)
        * (0.75 + 0.25 * sin(flowTime * 0.7 + dripHash * TAU));
    let dripAlong = clamp((tierY - dripStart) / max(dripLength, 0.001), 0.0, 1.0);
    let dripActive = step(dripStart, tierY) * step(tierY, dripStart + dripLength) * step(abs(cellX), 0.34);
    let dripWidth = mix(0.018, 0.004, dripAlong);
    let drip = (1.0 - smoothstep(dripWidth * 0.5, dripWidth, abs(dripLocalX))) * dripActive;
    let bead = exp(-length(vec2<f32>(dripLocalX, tierY - dripStart - dripLength)) * 70.0) * step(abs(cellX), 0.34);

    // Idea 3: god-ray shafts — slanted light falls from the windows into the nave, each shaft tinted by the
    // pane it passes through; strongest just under the arches, thinning toward the floor, lifted by mids.
    let shaftCoord = cellX + tierY * 0.45;
    let shaftBand = pow(0.5 + 0.5 * cos(shaftCoord * TAU * 3.0 + columnId * 2.1 + flowTime * 0.15), 5.0);
    let shaftFade = smoothstep(-0.55, 0.05, tierY) * smoothstep(0.5, 0.0, tierY) * (1.0 - window * 0.7);
    let shaftHue = (hash21(vec2<f32>(floor(shaftCoord * 3.0 + columnId * 3.1), tierId * 5.3)) - 0.5) * 0.35;
    let shaft = shaftBand * shaftFade * (0.3 + audio.y * 0.5) * (0.5 + refraction * 0.8);

    // Idea 4: dichroic shift — the glass changes colour with viewing angle; panes slide toward the complement
    // as the pointer crosses the window (zero shift when the pointer sits at centre).
    let dichroic = clamp((q.x - mouseP.x) * 0.5, -0.35, 0.35) * (0.5 + refraction);

    // ── Idea 5 (card idea 1): seeded antique glass (native: pot-metal glass) ──
    // Old cathedral glass carries trapped bubbles ("seeds") that flash as pinpoints when a shaft of
    // light crosses them, and long reamy cord streaks that run along the melt direction (x keeps only 30 %
    // of the melt shear, so they stay straight streaks instead of sheared mottling) and
    // modulate how much light each part of the pane passes. Bubbles live in cell-local glass
    // coordinates (world scale, so they stay round) and ride the melt because q is melt-warped.
    let glassW = vec2<f32>(cellX * (2.0 / columns), tierY / (3.0 + spireDensity * 3.0));
    // tierId grows ~0.45/s at the saved defaults; unwrapped, tierId·31·311.7 reaches f32-ulp 0.5 inside the
    // sin() after ~17 min. Wrap it (identity for tierId in [-8, 56), i.e. the first ~2 min).
    let tierW = tierId - 64.0 * floor((tierId + 8.0) / 64.0);
    let glassSalt = vec2<f32>(columnId * 17.0, tierW * 31.0);
    var seedGlint = 0.0;
    var reamMod = 0.0;
    if (window > 0.003) {   // glass detail only matters inside a window
    seedGlint = (glassSeeds(glassW * 34.0, glassSalt, 0.30) + 1.2 * glassSeeds(glassW * 15.0 + vec2<f32>(3.7, 1.3), glassSalt + vec2<f32>(11.0, 5.0), 0.12)) * window;
    reamMod = (smoothstep(0.22, 0.78, vnoise(vec2<f32>((p.x + melt.x * 0.3) * 52.0 + columnId * 3.7 + sin(q.y * 5.0 + flowTime * 0.3) * 0.3, q.y * 2.8 + flowTime * 0.10))) - 0.5) * 1.3 * window;
    }

    // ── Idea 6 (card idea 2): Tyndall dust motes in the shafts (native: lit nave air) ──
    // Dust hanging in the nave scatters the god-rays: sparse soft motes drift upward and are only
    // visible while they sit inside a shaft band (two parallax layers, continuous drift).
    let moteFade = smoothstep(0.04, 0.45, shaftBand) * smoothstep(-0.55, 0.05, tierY) * smoothstep(0.5, 0.0, tierY);
    var moteAmt = 0.0;
    if (moteFade > 0.002) {   // motes only show inside a shaft band
    moteAmt = (dustMotes(p, time, 22.0, 0.35, 0.0) + 1.5 * dustMotes(p + vec2<f32>(0.37, 0.11), time, 11.0, 0.18, 4.0)) * moteFade;
    }

    var clickRose = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.2) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(delta) - age * (0.16 + meltSpeed * 0.14));
            let petals = 0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 8.0 + age * 4.0);
            clickRose += (1.0 - smoothstep(0.0, 0.028, ring)) * petals * (1.0 - age / 3.2);
        }
    }

    let hue = stainedHue + cellX * 0.7 + tierY * 0.35 + flowTime * 0.06;
    var hdr = palette(hue + paneHue + dichroic + reamMod * 0.25) * window * (1.0 + reamMod) * (1.0 - came * 0.88) * (0.5 + glassPulse * 1.4 + audio.z);
    hdr += vec3<f32>(0.32, 0.28, 0.24) * came * glassPulse * 0.35;
    hdr += palette(hue + paneHue) * (drip * 0.9 + bead * 2.4) * (0.7 + audio.x);
    hdr += palette(hue + shaftHue + dichroic) * shaft * 1.1;
    hdr += mix(palette(hue + paneHue + dichroic), vec3<f32>(1.0), 0.6) * seedGlint * (0.9 + 1.8 * shaftBand) * 1.5;
    hdr += mix(vec3<f32>(1.0, 0.92, 0.75), palette(hue + shaftHue + dichroic), 0.4) * moteAmt * (3.0 + audio.y * 1.5);
    hdr += palette(hue + 0.57) * floorCaustic * (drip + bead) * 0.8;
    hdr += palette(hue + 0.32) * (arch * 1.8 + spire * 0.8) * (0.8 + audio.x);
    hdr += palette(hue + 0.57) * (roseTracery * 1.35 + floorCaustic * 0.45) * (0.6 + audio.y);
    hdr += palette(hue + clickRose * 0.4) * clickRose * 2.0;
    hdr += vec3<f32>(1.0, 0.35, 0.75) * dragMask * (0.5 + refraction * 1.5);
    let historyUV = clamp(uv + vec2<f32>(melt.x / max(aspect, 0.001), 0.004 + meltSpeed * 0.007), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + refraction * 0.20 + dragMask * 0.12, 0.0, 0.42));
    let structure = clamp(max(arch, spire) + window * 0.45 + roseTracery * 0.35 + clickRose * 0.5 + came * 0.3 + drip * 0.5 + bead * 0.6 + shaft * 0.25 + seedGlint * 0.15 + moteAmt * 0.25, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr), clamp(0.16 + structure * 0.82, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.12 + structure * 0.78, 0.0, 0.95), 0.0, 0.0, 0.0));
}
