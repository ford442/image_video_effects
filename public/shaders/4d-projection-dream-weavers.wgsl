// ═══════════════════════════════════════════════════════════════════
//  4D Projection Dream Weavers
//  Category: generative
//  Features: 4d-fractal, smooth-navigation, mouse-4d-control, audio-parameter, dream-like,
//            temporal-persistence, chromatic-dimension-separation, bass-detail, upgraded-rgba,
//            aces-tone-map, spring-damper-4d-navigation, worley-dream-dust, dimension-tint
//  Complexity: High
//  Chunks From: 4D noise projection techniques
//  Created: 2026-05-31
//  Upgraded: 2026-06-06, 2026-07-22 (Algorithmist: spring-damper nav, worley dust, palette tint), 2026-11-08
//  Ideas: XW/YW hyper-rotation of the sampling slice (dust rides it); 4D perspective divide 1/(D-w') with w-depth fog; per-channel dispersion along w (alive at silence)
//  A packing: HDR linear colour (pre-ACES) trail; texels (0,0) spring state and (1,0) sentinel are state, not colour
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Spring state lives in A texels (extraBuffer[133..] is re-zeroed every frame by the engine):
//   texel (0,0) = (z, z-vel, w, w-vel)      texel (1,0) = (fract(lastTime), 0, 0, STATE_TAG)
const STATE_TAG: f32 = 0.7371;

// RESCUE: the old hash fed a vec4 whose w lane was always 0 and produced a visible 45-degree
// diamond lattice in every frame. This is the standard sine-free 3D hash.
fn hash13(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.zyx + 31.32);
    return fract((q.x + q.y) * q.z);
}

// RESCUE: the old lattice hashed only i.xyz, so w never entered and the "4D" noise was 3D.
// Two 3D lattices at floor(w) and floor(w)+1 (decorrelated by a w-dependent hash offset),
// blended with the smoothstep of fract(w).
fn lattice3(i: vec3<f32>, u: vec3<f32>, wOff: vec3<f32>) -> f32 {
    let a = hash13(i + wOff);
    let b = hash13(i + vec3<f32>(1.0, 0.0, 0.0) + wOff);
    let c = hash13(i + vec3<f32>(0.0, 1.0, 0.0) + wOff);
    let d = hash13(i + vec3<f32>(1.0, 1.0, 0.0) + wOff);
    let e = hash13(i + vec3<f32>(0.0, 0.0, 1.0) + wOff);
    let f2 = hash13(i + vec3<f32>(1.0, 0.0, 1.0) + wOff);
    let g = hash13(i + vec3<f32>(0.0, 1.0, 1.0) + wOff);
    let h = hash13(i + vec3<f32>(1.0, 1.0, 1.0) + wOff);
    return mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, f2, u.x), mix(g, h, u.x), u.y),
        u.z
    );
}

fn noise4D(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let wStep = vec3<f32>(13.37, 29.51, 7.13);
    let lo = lattice3(i.xyz, u.xyz, i.w * wStep);
    let hi = lattice3(i.xyz, u.xyz, (i.w + 1.0) * wStep);
    return mix(lo, hi, u.w);
}

// Worley (cellular) F1 distance over a 3D domain, used for dream-dust sparkles
// suspended in the projected 3D slice of 4-space.
fn worley3D(p: vec3<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    var f1 = 8.0;
    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            for (var z = -1; z <= 1; z++) {
                let cell = vec3<f32>(f32(x), f32(y), f32(z));
                let jitter = vec3<f32>(
                    hash13(ip + cell),
                    hash13(ip + cell + vec3<f32>(17.17, 31.31, 47.47)),
                    hash13(ip + cell + vec3<f32>(59.59, 71.71, 83.83))
                );
                let d = cell + jitter - fp;
                f1 = min(f1, dot(d, d));
            }
        }
    }
    return sqrt(f1);
}

// Cosine palette: classic a + b*cos(TAU*(c*t + d)) dimension-tint generator.
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}

// Exact-texel bilinear read of the colour trail. A texels (0,0)/(1,0) hold spring state,
// so any tap that lands on them is moved to (2,0).
fn trailTexel(p: vec2<i32>) -> vec3<f32> {
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    var q = clamp(p, vec2<i32>(0), dims - vec2<i32>(1));
    q.x = select(q.x, 2, (q.y == 0) && (q.x < 2));
    return textureLoad(dataTextureC, q, 0).rgb;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let pix = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let tAbs = u.config.x;
    let time = tAbs * 0.2;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Sliders wired to real algorithm constants (saved-preset contract) ──
    let pScale = clamp(u.zoom_params.x, 0.0, 1.0);       // Base Scale
    let pSpeed = clamp(u.zoom_params.y, 0.0, 1.0);       // Temporal Speed
    let pDetail = clamp(u.zoom_params.z, 0.0, 1.0);      // Fractal Detail
    let pMouse = clamp(u.zoom_params.w, 0.0, 1.0);       // 4D Mouse Sensitivity

    let mouse = u.zoom_config.yz;

    // ── Spring-damper smoothing of the 4D slice coordinates ─────────────
    // RESCUE: state used to live in extraBuffer[133..136] (re-zeroed every frame, dt was the
    // click count) so z,w never left 0. Now: A texel (0,0) = (z, vz, w, vw), texel (1,0) =
    // (fract(lastTime), 0, 0, STATE_TAG). Every thread integrates the same step from the same
    // C texels; threads (0,0)/(1,0) write the new state. fract(time) keeps f16 A precise.
    let mouseRange = mix(1.5, 6.0, pMouse);
    let targetZ = (mouse.y - 0.5) * mouseRange;
    let targetW = (mouse.x - 0.5) * mouseRange;
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let haveState = abs(st1.w - STATE_TAG) < 0.001;
    var dtRaw = fract(tAbs) - st1.x;
    dtRaw += select(0.0, 1.0, dtRaw < 0.0);
    let dt = clamp(dtRaw, 0.001, 0.05);
    var z = select(targetZ, st0.x, haveState);
    var vz = select(0.0, st0.y, haveState);
    var w = select(targetW, st0.z, haveState);
    var vw = select(0.0, st0.w, haveState);
    let stiffness = mix(6.0, 18.0, pMouse);      // snappier at high sensitivity
    let damping = 1.8 * sqrt(stiffness);         // ~0.9 of critical
    vz += ((targetZ - z) * stiffness - vz * damping) * dt;
    vw += ((targetW - w) * stiffness - vw * damping) * dt;
    z += vz * dt;
    w += vw * dt;

    // Sliders drive the actual 4D field constants, audio adds modulation.
    let scale = mix(1.0, 3.2, pScale) + mids * 1.4;
    let speedSlider = mix(0.15, 1.4, pSpeed);
    // RESCUE: bass used to scale the RATE inside `time * speed`, so every beat re-shuffled the
    // field by (time * dBass) units. Bass is now a bounded phase kick instead.
    let drift = time * speedSlider + bass * 0.6;
    let detail = mix(0.35, 1.6, pDetail) + treble * 1.2;

    // ── Idea 1: XW / YW hyper-rotation of the sampling slice ───────────────
    // The slice point (c·scale, z, w) is rotated in the XW then YW planes, so the slice tilts
    // through the 4th dimension and the pattern morphs instead of sliding diagonally.
    let aXW = drift * 0.31;
    let aYW = drift * 0.19;
    let cXW = cos(aXW); let sXW = sin(aXW);
    let cYW = cos(aYW); let sYW = sin(aYW);
    let c0 = (uv - vec2<f32>(0.5)) * scale;
    let x1 = c0.x * cXW - w * sXW;
    let w1 = c0.x * sXW + w * cXW;
    let y2 = c0.y * cYW - w1 * sYW;
    let w2 = c0.y * sYW + w1 * cYW;

    // ── Idea 2: 4D → 3D perspective divide 1/(D − w′) ──────────────────────
    // wRel is the w pushed in by the tilt alone (the mouse w offset itself is subtracted so the
    // cursor still navigates rather than zooming the whole frame). Near-in-w swells, far shrinks.
    let wRel = w2 - w;
    let persp = 1.0 / max(1.0 - 0.22 * wRel, 0.4);
    let p4 = vec4<f32>(vec3<f32>(x1, y2, z) * persp, w2);

    // ── Idea 3: dispersion along w — R/G/B ride three different 3D slices of 4-space ──
    // The old chromatic offsets were ~0.01 at normal audio, so the field was monochrome. A
    // fixed separation along w (widening toward the viewer) keeps the colour split alive in
    // silence; bass / treble still push R / B along x as before.
    let disp = 0.14 * persp;
    let offR = vec4<f32>(bass * 0.1, 0.0, 0.0, -disp);
    let offB = vec4<f32>(-treble * 0.1, 0.0, 0.0, disp);
    let n_r = noise4D(p4 + drift + offR);
    let n_g = noise4D(p4 + drift);
    let n_b = noise4D(p4 + drift + offB);
    // Detail slider scales the higher octaves' amplitude (fine structure on/off)
    let n2 = noise4D(p4 * 2.3 - drift * 0.7) * 0.5 * detail;
    let n3 = noise4D(p4 * 4.7 + drift * 1.3) * 0.25 * detail;

    // RESCUE: normalise by the total octave amplitude so the field is 0..1 again (it summed to
    // a mean of ~1.0 → extrapolated past cream → ACES shoulder → flat white frame).
    let ampInv = 1.0 / (1.0 + 0.75 * detail);
    let fractal_r = (n_r + n2 + n3) * ampInv;
    let fractal_g = (n_g + n2 + n3) * ampInv;
    let fractal_b = (n_b + n2 + n3) * ampInv;
    let fractal_col = vec3<f32>(fractal_r, fractal_g, fractal_b);
    let fMean = (fractal_r + fractal_g + fractal_b) * (1.0 / 3.0);
    let depthField = clamp(fMean * 0.6 + 0.3, 0.0, 1.0);

    // Field → navy..cream gradient. Value noise clusters near 0.5, so the gradient is stretched
    // around the mean to traverse the whole palette.
    let tField = smoothstep(vec3<f32>(0.22), vec3<f32>(0.78), fractal_col);
    var col = mix(vec3<f32>(0.1, 0.15, 0.25), vec3<f32>(0.9, 0.85, 0.7), tField * 0.85 + 0.1);

    // w-depth fog (idea 2): the far side of the hypercube sinks toward the navy end.
    let farFog = 1.0 - smoothstep(-1.1, 0.0, wRel);
    col = mix(col, vec3<f32>(0.1, 0.15, 0.25) * 0.8, farFog * 0.4);

    // Temporal persistence for dream-like trails (colour space, exact C texel; the pixel itself)
    let prev = trailTexel(pix);
    col = mix(col, prev * 0.92, 0.12 + bass * 0.05);

    // Cosine-palette dimension tint: hue drifts with the smoothed 4D angles,
    // mixed at ~0.25 so the original palette stays dominant.
    let dimPhase = (z + w) * 0.11 + fractal_col.x * 0.35 + time * 0.03;
    let tint = cosinePalette(
        dimPhase,
        vec3<f32>(0.5, 0.5, 0.55),
        vec3<f32>(0.35, 0.3, 0.4),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    var tinted = mix(col, col * (0.6 + tint * 1.1), 0.25);

    let extraColor = vec3<f32>(abs(z) * 0.1, abs(w) * 0.08, (z + w) * 0.05);
    tinted += extraColor;

    // ── Worley dream-dust: sparse animated sparkle, now riding the hyper-rotated slice ──
    let dustP = vec3<f32>(p4.xy * 3.0, drift * 0.5 + p4.z * 0.25 + w2 * 0.15);
    let wor = worley3D(dustP);
    // Sparse: sharp pow keeps only the cell centers; depth-fade hides dust in
    // dense fractal regions; treble modulates brightness.
    let sparkle = pow(clamp(1.0 - wor, 0.0, 1.0), 24.0);
    let depthFade = 1.0 - smoothstep(0.35, 0.9, depthField);
    let dust = sparkle * depthFade * (0.25 + treble * 0.9);
    let dustCol = cosinePalette(
        dimPhase + 0.5,
        vec3<f32>(0.7, 0.7, 0.8),
        vec3<f32>(0.3, 0.3, 0.2),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.5, 0.8)
    );
    let finalCol = max(tinted + dustCol * dust, vec3<f32>(0.0));

    let alpha = clamp(fMean * 0.6 + 0.4 + bass * 0.05 + dust * 0.3, 0.25, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    // A: HDR colour; texels (0,0)/(1,0) carry the spring state / time sentinel instead.
    var aOut = vec4<f32>(finalCol, a);
    if (gid.x == 0u && gid.y == 0u) { aOut = vec4<f32>(z, vz, w, vw); }
    if (gid.x == 1u && gid.y == 0u) { aOut = vec4<f32>(fract(tAbs), 0.0, 0.0, STATE_TAG); }

    textureStore(writeTexture, gid.xy, vec4<f32>(acesToneMap(finalCol * 1.1), a));
    textureStore(dataTextureA, gid.xy, aOut);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthField, 0.0, 0.0, 0.0));
}
