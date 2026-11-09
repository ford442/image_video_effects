// ═══════════════════════════════════════════════════════════════════
//  Digital Haze — Batch 61
//  Beer-Lambert haze + hex grid overlay, iridescent scatter color,
//  sprung clear window, capped ripples, held widen, per-cell treble static.
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: re-fogging wipe memory (the wiped path and click holes condense back from the surrounding fog, via C.r); chromatic Beer–Lambert extinction (§12.2F; thick fog transmits warm, scatters cool); forward-scatter glare around source highlights (§12.2F Henyey–Greenstein, 8 taps)
//  A packing: A.x = fog mask (persisting history, read back as C.r), A.y = alpha, A.w = 1; texels (0,0) = window spring (pos.xy, vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (corner texels; their C read is masked, invisible)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Digital haze extinction coefficients
const SIGMA_T_HAZE: f32 = 1.2;          // Haze extinction (thick)
const SIGMA_T_CLEAR: f32 = 0.05;        // Clear area extinction (minimal)
// RESCUE R1: HEAD used STEP_SIZE = 0.03 as the whole ray path, so tau ≈ 0.045 and the haze
// carried ≈ 1% of the image — the effect was an identity filter and every slider was dead.
// HAZE_PATH is the slab thickness the view ray crosses (σ·path ≈ 0.8 at the default).
const HAZE_PATH: f32 = 0.55;
// Idea 2: per-channel extinction ratio (blue is scattered out first; Rayleigh λ⁻⁴ would be 0.5 : 1 : 2.2, kept milder so the iridescent veil survives).
const SIGMA_RGB: vec3<f32> = vec3<f32>(0.60, 1.00, 1.70);
const HAZE_VEIL: f32 = 0.85;            // weight of the scattered (pixelated / hex / iridescent) layer

// Window spring (RESCUE R2): HEAD kept it in extraBuffer[133..137], which is re-uploaded
// zeroed every frame, so the "sprung" window followed the raw cursor with no lag. State now
// lives in A texels (0,0)/(1,0) and is read back through C.
const SENT: f32 = 0.7371;
const SPRING_K: f32 = 40.0;             // stiffness

// Click clear-pulse shape: ~0.2 aspect-corrected radius, ~1.5s life.
const PULSE_RADIUS: f32 = 0.2;
const PULSE_DECAY: f32 = 2.0;
const PULSE_LIFE: f32 = 1.5;

// Idea 3: HG forward-scatter glare
const GLARE_G: f32 = 0.6;               // Henyey–Greenstein asymmetry (forward)
const GLARE_AMT: f32 = 2.0;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexEdge(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let q = vec2<f32>(p.x * 1.7320508 + p.y, p.y * 2.0);
  let pf = fract(q);
  let d1 = length(pf - vec2<f32>(0.5, 0.5));
  let d2 = length(pf - vec2<f32>(0.0, 1.0));
  return 1.0 - smoothstep(0.01, 0.06, min(d1, d2));
}

fn iridescentHaze(t: f32, mask: f32) -> vec3<f32> {
  let base = vec3<f32>(0.08, 0.14, 0.1);
  let irid = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (t + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.67))
  );
  return base + irid * mask * 0.35;
}

// Exact fog-mask load (C.r) with the two state texels masked as "fully fogged".
fn fogAt(c: vec2<i32>, maxC: vec2<i32>) -> f32 {
  let cc = clamp(c, vec2<i32>(0), maxC);
  let isState = (cc.y == 0) && (cc.x < 2);
  return select(textureLoad(dataTextureC, cc, 0).r, 1.0, isState);
}

// Henyey–Greenstein phase (unnormalised) for scattering angle cosine.
fn hgPhase(cosT: f32, g: f32) -> f32 {
  return (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * cosT, 1e-3), 1.5);
}

fn luma3(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let coord = vec2<i32>(gid.xy);
    let maxC = vec2<i32>(dims) - vec2<i32>(1);
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = u.zoom_config.w > 0.5;

    // ═══════════════════════════════════════════════════════════════
    //  Sprung Clear Window
    //  The raw mouse is the spring TARGET; the clear window follows a
    //  critically-damped spring so the wipe lags the cursor. Every
    //  thread integrates one deterministic step from the stored state
    //  (A texels (0,0)/(1,0) via C); the two corner threads persist it.
    //  Sentinel invalid (first frame / shader switch) → start on the
    //  cursor with the whole pane fogged.
    // ═══════════════════════════════════════════════════════════════
    let rawMouse = u.zoom_config.yz;
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let stateOk = abs(st1.w - SENT) < 0.001;
    let sdt = clamp(fract(time - st1.x), 0.001, 0.05);   // fract(time) is stored: A can be rgba16float
    var springPos = select(rawMouse, st0.xy, stateOk);
    var springVel = select(vec2<f32>(0.0), st0.zw, stateOk);
    let springC = 2.0 * sqrt(SPRING_K);   // critical damping coefficient
    let springAccel = (rawMouse - springPos) * SPRING_K - springVel * springC;
    springVel += springAccel * sdt;
    springPos += springVel * sdt;
    let mouse = springPos;

    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params; bass pulses the haze density, mids vary the noise texture
    let pixelStrength = u.zoom_params.x * 100.0 + 10.0;
    let clearRadius = (u.zoom_params.y * 0.4 + 0.05) * select(1.0, 1.3, held);
    let noiseAmt = u.zoom_params.z * (1.0 + mids * 0.4);

    var windowMask = smoothstep(clearRadius, clearRadius + 0.2, dist);

    // ── Click clear pulses ──────────────────────────────────────────
    // Each live ripple punches a temporary clear hole at its click
    // point: the mask is reduced by exp(-age * 2.0) inside an
    // aspect-corrected ~0.2 radius for ~1.5s, so clicks wipe the fog.
    var clearPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < PULSE_LIFE) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let hole = smoothstep(PULSE_RADIUS, 0.0, rDist) * exp(-age * PULSE_DECAY);
            clearPulse = max(clearPulse, hole);
        }
    }
    windowMask = windowMask * (1.0 - clearPulse);

    // ── Idea 1: re-fogging wipe memory ──────────────────────────────
    // Fogged glass does not stay wiped: condensation creeps back in from the surrounding
    // fog. The fog mask persists in C.r; it regrows at a slow base rate everywhere and
    // faster right beside fog (the creep term reads 4 taps at ~3% of the frame height).
    // The instantaneous window/click mask is a ceiling, so the cursor (and a click hole)
    // clears glass at once, and what it leaves behind re-fogs over a few seconds.
    // (HEAD's mix(…, 0.08) hysteresis forgot the wipe within ~1 frame.)
    let fogPrev = select(1.0, fogAt(coord, maxC), stateOk);
    let rr = i32(max(3.0, dims.y * 0.03));
    let fogNear = max(
        max(select(1.0, fogAt(coord + vec2<i32>(rr, 0), maxC), stateOk), select(1.0, fogAt(coord - vec2<i32>(rr, 0), maxC), stateOk)),
        max(select(1.0, fogAt(coord + vec2<i32>(0, rr), maxC), stateOk), select(1.0, fogAt(coord - vec2<i32>(0, rr), maxC), stateOk)));
    let creep = max(fogNear - fogPrev, 0.0);
    let refog = fogPrev + sdt * (0.12 + 2.5 * creep);
    let mask = clamp(min(windowMask, refog), 0.0, 1.0);

    // Dynamic Pixelation
    let gridSize = vec2<f32>(pixelStrength * aspect, pixelStrength);
    let quantizedUV = floor(uv * gridSize) / gridSize;

    // Add digital noise to the quantized UV
    let seed = quantizedUV + vec2<f32>(time * 0.1, time * 0.05);
    var noiseVal = (hash(seed) - 0.5) * noiseAmt * 0.05;

    // ── Per-cell treble static (RESCUE R3) ──────────────────────────
    // HEAD read plasmaBuffer[1..8] per cell, which is never uploaded (always 0). The live
    // treble band now drives the static, gated per cell by that cell's own hash so the
    // pixel-cells flicker unevenly with the highs.
    let cellHash = hash(floor(uv * gridSize));
    noiseVal = noiseVal * (1.0 + treble * cellHash * 0.9);

    let hazeUV = clamp(quantizedUV + noiseVal, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample colors
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let colHaze = textureSampleLevel(readTexture, u_sampler, hazeUV, 0.0).rgb;

    let hexScale = 14.0 + pixelStrength * 0.08;
    let hex = hexEdge(uv, hexScale) * mask * (0.12 + mids * 0.08);
    let hazeTint = iridescentHaze(time * 0.06 + dist * 2.0 + hash(uv) * 0.5, mask);

    // ── Idea 3: forward-scatter glare (§12.2F Henyey–Greenstein) ────
    // Haze scatters light forward, so bright source pixels glow through it. Eight taps in two
    // rings gather highlights; each ring's weight is the HG phase at the scatter angle
    // atan(12·ρ) the tap's offset ρ (in frame heights) subtends, so glare falls off the way a
    // forward-scattering medium's does. It rides the (1−T) veil below, so the clear window and
    // thin haze stay free of it.
    var glare = vec3<f32>(0.0);
    var glareW = 0.0;
    for (var ring = 0; ring < 2; ring = ring + 1) {
        let rho = select(0.03, 0.09, ring == 1);
        let cosT = cos(atan(rho * 12.0));
        let wPhase = hgPhase(cosT, GLARE_G);
        for (var k = 0; k < 4; k = k + 1) {
            let ang = (f32(k) + 0.5 * f32(ring)) * 1.5707963;
            let off = vec2<f32>(cos(ang) / aspect, sin(ang)) * rho;
            let tap = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            glare += tap * max(luma3(tap) - 0.6, 0.0) * wPhase;
            glareW += wPhase;
        }
    }
    glare = glare / max(glareW, 1e-3) * GLARE_AMT;

    let finalHaze = colHaze + hazeTint + vec3<f32>(hex * 0.35, hex * 0.55, hex * 0.4) + glare;

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Fog Calculation
    // ═══════════════════════════════════════════════════════════════

    // Calculate optical depth based on mask (haze density); bass pulses fog thickness
    var hazeDensity = (mask * SIGMA_T_HAZE + (1.0 - mask) * SIGMA_T_CLEAR) * (1.0 + bass * 0.5);

    // 'Haze Density' slider is live: 0.4x..1.6x extinction around the
    // default (0.5 -> exactly 1.0 of the base extinction).
    hazeDensity *= mix(0.4, 1.6, u.zoom_params.w);

    // Optical depth through the haze slab
    let opticalDepth = hazeDensity * HAZE_PATH * (1.0 + noiseAmt * 0.5);

    // ── Idea 2: chromatic Beer–Lambert (§12.2F) ──────────────────────
    // T = exp(-τ·σ_rgb): blue is extinguished first, so thick fog transmits the photo warm
    // and its in-scattered veil (1−T) is cool. Scalar T (used for alpha) is the green channel.
    let transmittance = exp(-opticalDepth * SIGMA_RGB);
    let tLum = transmittance.y;

    let hazeColor = iridescentHaze(time * 0.04 + noiseAmt, mask);
    let inScattered = hazeColor * mask * (1.0 - transmittance) * (1.0 + hex * 0.5);

    // Volumetric composition
    // Final = in_scattered + transmitted_clear * T + transmitted_haze * (1-T)
    let transmittedClear = colClear * transmittance;
    let transmittedHaze = finalHaze * (1.0 - transmittance) * HAZE_VEIL;

    let finalColor = acesToneMap(max(inScattered + transmittedClear + transmittedHaze, vec3<f32>(0.0)));
    let alpha = clamp(1.0 - tLum + mask * 0.15, 0.0, 1.0);
    let depthVal = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));

    // A: fog history (+ alpha); the two corner texels carry the window spring state.
    var aOut = vec4<f32>(mask, alpha, 0.0, 1.0);
    if (coord.y == 0 && coord.x == 0) { aOut = vec4<f32>(springPos, springVel); }
    if (coord.y == 0 && coord.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
    textureStore(dataTextureA, coord, aOut);
}
