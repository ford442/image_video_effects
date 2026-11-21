// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Smear — Pointer-Velocity Pigment Drag
//  Category: liquid-effects
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, spring-damper-pointer, velocity-smear,
//            pigment-diffusion, edge-guided transport, monotone reconstruction,
//            depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 58B + tensor-guided precision pass), 2026-11-21
//  Ideas: bank-and-wake pile-up (§12.2D shallow-water continuity on the drag field);
//         bristle rake striations across the stroke normal (§12.2C); speed-thinning brush radius (§12.2C)
//  A packing: pre-ACES pigment RGB + alpha (>= 0.02) read back as C colour;
//             texel (0,0) holds the pointer state (smoothed pos xy, vel xy), never pigment
// ═══════════════════════════════════════════════════════════════════════════════
//  Two structures replace the original "pull toward the cursor" offset:
//
//    1. Velocity smear from a spring-damped pointer — the smoothed cursor and
//       its velocity (position xy, velocity xy) ride in texel (0,0) of A, which
//       becomes C next frame. They used to live in extraBuffer[133..136], but the
//       engine rewrites all 256 extraBuffer floats before every dispatch, so the
//       velocity was always 0 (no drag ever happened) and ~70 % of invocations
//       raced the write and saw the pointer at (0,0). Every invocation now
//       recomputes the same spring step from last frame's texel (deterministic);
//       invocation (0,0) alone stores it, and every history load redirects that
//       texel to (1,0) so state is never read as pigment. The smear direction is
//       the pointer's actual travel direction with its speed as the drag length,
//       so flicking the cursor rakes pigment along the stroke. The old code had
//       no velocity at all — it always pulled toward the cursor centre, which
//       reads as a sink, not a brush.
//
//    2. Per-band FFT pigment diffusion — the smeared field is blurred along the
//       stroke normal by a kernel whose width comes from the local FFT bin, so
//       loud bands bleed pigment sideways while quiet ones keep crisp streaks.
//       (The bin now comes from the engine's extraBuffer[5 + bin]; plasmaBuffer[1..8]
//       was never uploaded, so the old per-band term was a constant 0.)
//
//  2026-11-21 ideas, all riding the drag field this file already computes:
//    - bank and wake: the displacement map's divergence piles pigment up ahead of
//      the brush and thins it behind (continuity), feeding thickness/alpha and a
//      Beer-Lambert density shade on the pigment before the Mix Strength blend;
//    - bristle rake: the drag length is modulated across the stroke normal in the
//      brush frame, leaving striations parallel to the path;
//    - speed-thinning: fast flicks rake with a narrow brush, slow drags pool wide.
//
//  Also fixed: the shader had NO bounds guard (it wrote past the render target
//  on non-multiple-of-16 resolutions), and it read dataTextureC through the
//  FILTERING sampler. dataTextureC is rgba32float and `float32-filterable` is
//  only requested when the adapter offers it (src/renderer/webgpu/device.ts),
//  so that read is invalid on devices without the feature. History is now
//  fetched with exact textureLoad, bilinear-interpolated by hand where the
//  advection offset is sub-pixel.
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=SmearStrength, y=BrushSize, z=Persistence, w=MixStrength

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  return F0 + (1.0 - F0) * m2 * m2 * m;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// PCG lattice hash — copied verbatim from public/shaders/_std/_std_hash.wgsl
// (pcg, u32ToUnit, hash11).
fn pcg(v: u32) -> u32 {
  let s = v * 747796405u + 2891336453u;
  let w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
  return (w >> 22u) ^ w;
}
fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}
fn hash11(p: f32) -> f32 {
  return u32ToUnit(pcg(bitcast<u32>(p)));
}

// Pigment history fetch. Texel (0,0) of C carries the pointer state (see header),
// never pigment, so it is read from its right-hand neighbour instead.
fn loadC(c: vec2<i32>) -> vec4<f32> {
    let cc = select(c, vec2<i32>(1, 0), all(c == vec2<i32>(0)));
    return textureLoad(dataTextureC, cc, 0);
}

// Exact float32 history fetch with hand-rolled bilinear — dataTextureC must
// never go through the filtering sampler (see header).
fn historyBilinear(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
    let maxC = dims - vec2<i32>(1);
    let f = fract(p);
    let i0 = vec2<i32>(floor(p));
    let s00 = loadC(clamp(i0, vec2<i32>(0), maxC));
    let s10 = loadC(clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC));
    let s01 = loadC(clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC));
    let s11 = loadC(clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC));
    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

struct HistoryBounds {
    low: vec4<f32>,
    high: vec4<f32>,
};

// Clamp higher-detail reconstruction to the local cross stencil. This is the
// same monotonicity safeguard used by high-order fluid advection: it prevents
// ringing from creating negative pigment or HDR speckles in persistent trails.
fn historyBounds(p: vec2<f32>, dims: vec2<i32>) -> HistoryBounds {
    let maxC = dims - vec2<i32>(1);
    let c = clamp(vec2<i32>(round(p)), vec2<i32>(0), maxC);
    let e = loadC(clamp(c + vec2<i32>( 1,  0), vec2<i32>(0), maxC));
    let w = loadC(clamp(c + vec2<i32>(-1,  0), vec2<i32>(0), maxC));
    let n = loadC(clamp(c + vec2<i32>( 0,  1), vec2<i32>(0), maxC));
    let s = loadC(clamp(c + vec2<i32>( 0, -1), vec2<i32>(0), maxC));
    let m = loadC(c);
    var out: HistoryBounds;
    out.low = min(m, min(min(e, w), min(n, s)));
    out.high = max(m, max(max(e, w), max(n, s)));
    return out;
}

fn plateGradient(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let weights = vec3<f32>(0.2126, 0.7152, 0.0722);
    let l = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb, weights);
    let r = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb, weights);
    let t = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb, weights);
    let b = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb, weights);
    return vec2<f32>(r - l, b - t);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    let texel = 1.0 / resolution;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let smearStrength = 0.1 + (u.zoom_params.x * 0.9);
    let brushSize = 0.05 + (u.zoom_params.y * 0.2);
    let decayRate = 0.9 + (u.zoom_params.z * 0.095);
    let mixStrength = 0.1 + (u.zoom_params.w * 0.9);

    // ── Structure 1: spring-damped pointer + velocity ────────────────────────
    // ── Rescue R1: the spring state rides in texel (0,0) of C (= last frame's A) as
    // (smoothed pos xy, smoothed vel xy). extraBuffer[133..136] is re-zeroed by the
    // engine every frame, so it could never hold velocity. Every invocation derives
    // the same spring step from that texel (deterministic, no cross-invocation race);
    // only invocation (0,0) stores it (see the A write below).
    let rawMouse = u.zoom_config.yz;
    let st = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    // An empty / foreign / non-finite texel is not a pointer state: restart from the raw pointer.
    let stValid = (st.x != 0.0 || st.y != 0.0)
        && all(st.xy >= vec2<f32>(0.0)) && all(st.xy <= vec2<f32>(1.0))
        && all(abs(st.zw) < vec2<f32>(50.0));
    let smPrev = select(rawMouse, st.xy, stValid);
    let velPrev = select(vec2<f32>(0.0), st.zw, stValid);
    let springDt = 0.016;
    let springK = 1.0 - exp(-9.0 * springDt);
    let mousePos = smPrev + (rawMouse - smPrev) * springK;
    let mouseVel = mix(velPrev, (mousePos - smPrev) / springDt, 0.25);
    let held = step(0.5, u.zoom_config.w);

    let speed = length(mouseVel);
    // ── Idea 3: speed-thinning (§12.2C). A fast flick rakes with a narrow contact patch,
    // a slow drag pools wide. Brush Size stays the radius at rest (speed 0 → R = brushSize).
    let brushR = brushSize / (1.0 + 0.35 * speed);

    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toMouse);
    let brushFalloff = 1.0 - smoothstep(0.0, brushR, dist);

    // Drag along the pointer's actual travel, not toward its centre.
    let strokeDir = select(vec2<f32>(0.0), mouseVel / max(speed, 1e-5), speed > 1e-4);
    let imageGradient = plateGradient(uv, texel);
    let edgeEnergy = clamp(length(imageGradient) * 5.0, 0.0, 1.0);
    let edgeTangent = normalize(vec2<f32>(-imageGradient.y, imageGradient.x) + strokeDir * 1e-4);
    // Wet pigment follows source contours instead of bleeding across them.
    let guidedDir = normalize(mix(strokeDir, edgeTangent, edgeEnergy * (0.25 + 0.45 * smearStrength)) + vec2<f32>(1e-6));
    let dragLen = clamp(speed * 0.02, 0.0, 0.06) * smearStrength * (0.5 + held);

    // ── Idea 2: bristle rake (§12.2C stroke tangent / direction, not just magnitude).
    // The across-stroke coordinate lives in the brush frame (aspect-corrected, so it is
    // perpendicular on screen); a smooth 1-D bristle profile (0..2x, mean 1) scales the
    // drag length per lane, and the thin lanes (bristle gaps) let the bare plate show through
    // via the existing `refresh` term below, so the path is left with striations parallel to
    // the stroke instead of one smooth shear.
    let dirA = normalize(guidedDir * vec2<f32>(aspect, 1.0));
    let across = dot(toMouse, vec2<f32>(-dirA.y, dirA.x));
    let bristleStep = max(brushR * 0.16, 3.0 * texel.y);      // ~6 bristles per radius, never < 3 px
    let bristleP = across / bristleStep + 64.0;               // keep floor() on one side of zero
    let bristleF = fract(bristleP);
    let bristle = mix(hash11(floor(bristleP)), hash11(floor(bristleP) + 1.0), bristleF * bristleF * (3.0 - 2.0 * bristleF));
    let rake = clamp(1.0 + 2.2 * (bristle - 0.5), 0.0, 2.0);  // 0..2, mean 1: total drag unchanged, gaps drag nothing
    var offset = guidedDir * dragLen * brushFalloff * rake;

    // ── Idea 1: bank and wake (§12.2D shallow-water continuity, d(rho)/dt = -div(rho v)).
    // The history is sampled at uv - offset, so pigment is carried along +offset and its
    // thickness scales with 1 - div(offset): >1 where the field converges (ahead of the
    // brush: a bank), <1 where it spreads (the wake). The smooth-envelope divergence is
    // analytic from the brush falloff's derivative, so it costs no extra taps.
    let tN = clamp(dist / max(brushR, 1e-4), 0.0, 1.0);
    let dFall = -6.0 * tN * (1.0 - tN) / max(brushR, 1e-4);    // d(brushFalloff)/d(dist)
    let radial = toMouse / max(dist, 1e-4);                    // aspect-space unit vector from the brush
    let divOffset = dragLen * dFall * (guidedDir.x * radial.x * aspect + guidedDir.y * radial.y);
    let rho = clamp(1.0 - divOffset, 0.6, 1.6);

    // ── Bounded click splats ─────────────────────────────────────────────────
    var splat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.2) {
            let rDelta = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
            let r = max(length(rDelta), 1e-4);
            let front = r - age * 0.42;
            let env = exp(-front * front * 150.0) * exp(-age * 1.5);
            offset += (rDelta / r) * env * smearStrength * 0.03;
            splat += env;
        }
    }
    splat = min(splat, 1.5);

    // ── Structure 2: per-band FFT pigment diffusion ──────────────────────────
    // Band chosen by position so different regions bleed with different bins;
    // the blur runs along the stroke NORMAL, spreading pigment sideways.
    let bandIdx = u32(clamp((uv.x * 0.5 + uv.y * 0.5) * 8.0, 0.0, 7.999));
    // ── Rescue R2: engine FFT bins live in extraBuffer[5 + bin] (0..1, engine-owned).
    // plasmaBuffer[1..8] is never uploaded, so the HEAD band term was a constant 0.
    let fftBin = 5u + bandIdx * 4u;
    let band = clamp(0.5 * (extraBuffer[fftBin] + extraBuffer[fftBin + 1u]), 0.0, 1.0);
    let bleed = (0.4 + band * 3.2 + mids * 0.8) * (0.5 + smearStrength);
    let normalDir = vec2<f32>(-guidedDir.y, guidedDir.x);

    let basePx = (uv - offset) * resolution;
    let bleedPx = normalDir * bleed;
    let h0 = historyBilinear(basePx, dimsI);
    let h1 = historyBilinear(basePx + bleedPx, dimsI);
    let h2 = historyBilinear(basePx - bleedPx, dimsI);
    let h3 = historyBilinear(basePx + bleedPx * 2.0, dimsI);
    let h4 = historyBilinear(basePx - bleedPx * 2.0, dimsI);
    // Gaussian-ish 5-tap along the normal.
    var smeared = h0 * 0.38 + (h1 + h2) * 0.24 + (h3 + h4) * 0.07;
    let bounds = historyBounds(basePx, dimsI);
    smeared = clamp(smeared, bounds.low, bounds.high);

    let currentInput = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Cold start: an empty history seeds from the live plate.
    if (smeared.a <= 0.0001) { smeared = currentInput; }

    // Fresh input keeps bleeding in so the field never degenerates; clicks and
    // the brush core inject extra fresh pigment.
    // Idea 2: bristle gaps (rake < 1) pick fresh plate up, in proportion to how hard the brush is raking.
    let bareLane = clamp(1.0 - rake, 0.0, 1.0) * brushFalloff * clamp(dragLen * 40.0, 0.0, 1.0);
    let refresh = clamp(splat * 0.5 + brushFalloff * held * 0.4 + bareLane * 0.35, 0.0, 0.9);
    let keep = decayRate * (1.0 - refresh);
    let blend = mix(currentInput, smeared, keep);

    // ── Colour ───────────────────────────────────────────────────────────────
    // Idea 1 (display only — A keeps the plain pigment): thicker pigment absorbs more
    // (Beer-Lambert), so the bank reads deeper and the wake lighter. It rides inside the
    // Mix Strength blend, so Mix Strength 0 still shows the untouched plate.
    let pigmentShade = exp(-1.0 * (rho - 1.0));
    var color = mix(currentInput.rgb, blend.rgb * pigmentShade, mixStrength);
    color += vec3<f32>(0.02, 0.01, 0.0) * smearStrength;
    color += vec3<f32>(1.0, 0.86, 0.7) * splat * 0.25 * (1.0 + bass * 0.6);
    color += vec3<f32>(0.25, 0.45, 0.8) * brushFalloff * held * (0.15 + treble * 0.35);
    let fibrePhase = dot(uv * resolution, guidedDir) * (0.16 + band * 0.12) + time * (0.7 + treble);
    color += vec3<f32>(0.16, 0.09, 0.04) * sin(fibrePhase) * edgeEnergy * smearStrength * 0.045;
    color = acesFilm(color);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    let normal = normalize(vec3<f32>(offset * 40.0, 1.0));
    let fresnel = schlickFresnel(max(0.0, normal.z), 0.02);
    let thickness = (smearStrength * 2.0 * brushFalloff + 0.2) * rho;   // Idea 1: bank thickens, wake thins
    let absorption = exp(-thickness);
    let baseAlpha = mix(0.4, mix(0.7, 0.95, decayRate), absorption);
    let pigment = clamp(brushFalloff * 0.5 + splat * 0.6 + length(offset) * 12.0, 0.0, 1.0);
    let alpha = clamp(mix(currentInput.a * baseAlpha, 1.0, pigment) * (1.0 - fresnel * 0.2), 0.0, 1.0);

    let outColor = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, outColor);
    // A carries the smeared field forward — it becomes next frame's C. Texel (0,0)
    // instead carries the pointer state (R1); loadC() keeps it out of the pigment.
    let isStateTexel = (global_id.x == 0u) && (global_id.y == 0u);
    textureStore(dataTextureA, coord, select(vec4<f32>(blend.rgb, max(alpha, 0.02)), vec4<f32>(mousePos, mouseVel), isStateTexel));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
