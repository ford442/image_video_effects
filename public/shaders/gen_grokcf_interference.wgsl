// ═══════════════════════════════════════════════════════════════════════════════
//  Cylindrical Drum Modes — Bessel Function Modal Synthesis
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural, animated
//  Complexity: High
//  Scientific: Vibrating circular membrane modes u_{mn}(r,φ,t) =
//              J_m(α_{mn}·r/R)·cos(m·φ+φ₀)·cos(ω_{mn}·t),
//              polynomial approximation to Bessel J₀…J₃ on GPU,
//              audio bands activate different (m,n) mode families:
//              bass→(0,1)(0,2), mids→(1,1)(2,1), treble→(1,2)(3,1),
//              each mode weighted by its matching FFT bin (true cymatics),
//              Chladni node-line colour coding (zero-crossings → white),
//              click strikes inject decaying impulse ripples into u_total,
//              mouse genuinely re-centres the drum via the polar mapping
//  Sliders:  x=ModeScale  y=ColourMode (hue rotation of base colour)
//            z=NodeSharpness  w=ModeCount
//  State:    dataTextureA = (u_total, leaky |u| sand energy, phi/2π, blendAlpha) —
//            raw sim state, never tone-mapped; extraBuffer is only READ (the real
//            FFT bins live at extraBuffer[5..132]); persistent data lives in A
//            and the uniform ripple ring buffer.
//  Upgraded: 2026-10-17, 2026-11-08
//  Ideas: radial vs azimuthal tint; displacement Lambert; antinode disks; radial beat; sand on the plate (leaky |u| history in A.g); modal strike response (S_k(hit)·S_k(p) ring-down)
//  A packing: raw u_total, leaky |u| (sand), phi/2π, blendAlpha
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ModeScale, y=ColourMode, z=NodeSharpness, w=ModeCount

// ─── Polynomial Bessel approximations (Abramowitz & Stegun 9.4) ───
// J₀(x)  — accurate for x ∈ [0, 8] via two-range polynomial
fn J0(x: f32) -> f32 {
    let ax = abs(x);
    if (ax < 8.0) {
        let y = x * x;
        let p1 = 57568490574.0 - y*(13362590354.0 - y*(651619640.7 - y*(11214424.18 - y*(77392.33017 - y*184.9052456))));
        let q1 = 57568490411.0 + y*(1029532985.0 + y*(9494680.718 + y*(59272.64853 + y*(267.8532712 + y))));
        return p1 / q1;
    }
    let z  = 8.0 / ax;
    let y  = z * z;
    let xx = ax - 0.785398164;
    let p1 = 1.0 + y*(-0.1098628627e-2 + y*(0.2734510407e-4 + y*(-0.2073370639e-5 + y*0.2093887211e-6)));
    let q1 = -0.1562499995e-1 + y*(0.1430488765e-3 + y*(-0.6911147651e-5 + y*(0.7621095161e-6 - y*0.934945152e-7)));
    return sqrt(0.636619772 / ax) * (cos(xx) * p1 - z * sin(xx) * q1);
}

fn J1(x: f32) -> f32 {
    let ax = abs(x);
    if (ax < 8.0) {
        let y = x * x;
        let p1 = x*(72362614232.0 - y*(7895059235.0 - y*(242396853.1 - y*(2972611.439 - y*(15704.48260 - y*30.16036606)))));
        let q1 = 144725228442.0 + y*(2300535178.0 + y*(18583304.74 + y*(99447.43394 + y*(376.9991397 + y))));
        return p1 / q1;
    }
    let z  = 8.0 / ax;
    let y  = z * z;
    let xx = ax - 2.356194491;
    let p1 = 1.0 + y*(0.183105e-2 + y*(-0.3516396496e-4 + y*(0.2457520174e-5 - y*0.240337019e-6)));
    let q1 = 0.04687499995 + y*(-0.2002690873e-3 + y*(0.8449199096e-5 + y*(-0.88228987e-6 + y*0.105787412e-6)));
    let ans = sqrt(0.636619772 / ax) * (cos(xx) * p1 - z * sin(xx) * q1);
    return select(ans, -ans, x < 0.0);
}

// J₂, J₃ via recurrence: J_{n+1} = (2n/x)·J_n − J_{n-1}
fn J2(x: f32) -> f32 {
    if (abs(x) < 0.001) { return 0.0; }
    return (2.0 / x) * J1(x) - J0(x);
}
fn J3(x: f32) -> f32 {
    if (abs(x) < 0.001) { return 0.0; }
    return (4.0 / x) * J2(x) - J1(x);
}

// Drum mode u_{mn}: J_m(alpha_mn * r/R) * cos(m*phi + phi0) * cos(omega_mn * t)
// alpha_mn = first/second zero of J_m (tabulated constants)
fn drumMode(r: f32, phi: f32, t: f32, m: i32, alpha_mn: f32, omega: f32, phi0: f32) -> f32 {
    let bessel = select(
        select(
            select(J3(alpha_mn * r), J2(alpha_mn * r), m == 2),
            J1(alpha_mn * r), m == 1
        ),
        J0(alpha_mn * r), m == 0
    );
    return bessel * cos(f32(m) * phi + phi0) * cos(omega * t);
}

// Cymatic weight: each mode family is driven by its own slice of the REAL FFT.
// (HEAD read plasmaBuffer[1..8], which the engine never uploads — every weight was a
// constant 0.6.)  Bins are extraBuffer[5 + i], i = 0..127, normalised 0..1.
// Slices: (0,1) bins 0-1 · (0,2) 2-3 · (1,1) 4-6 · (2,1) 7-10 · (1,2) 11-18 · (3,1) 19-40.
fn fftBand(lo: u32, n: u32) -> f32 {
    var s = 0.0;
    for (var i: u32 = 0u; i < n; i = i + 1u) {
        s = s + extraBuffer[5u + lo + i];
    }
    return clamp(s / f32(n), 0.0, 1.0);
}
fn fftModeWeight(mode: u32) -> f32 {
    let lo = select(select(select(select(select(0u, 2u, mode >= 1u), 4u, mode >= 2u), 7u, mode >= 3u), 11u, mode >= 4u), 19u, mode >= 5u);
    let n  = select(select(select(select(select(2u, 2u, mode >= 1u), 3u, mode >= 2u), 4u, mode >= 3u), 8u, mode >= 4u), 22u, mode >= 5u);
    return 0.85 + 0.9 * fftBand(lo, n);
}

// Pure mode shape S_k (no time factor) for the six-mode table used in main():
// k: 0=(0,1) 1=(0,2) 2=(1,1) 3=(2,1) 4=(1,2) 5=(3,1)  — same m, α_mn, φ0 as main().
fn modeAlpha(k: u32) -> f32 {
    return select(select(select(select(select(2.4048, 5.5201, k == 1u), 3.8317, k == 2u), 5.1356, k == 3u), 7.0156, k == 4u), 6.3802, k == 5u);
}
fn modeShape(k: u32, r: f32, phi: f32) -> f32 {
    let m    = select(select(select(select(0, 1, k >= 2u), 2, k >= 3u), 1, k >= 4u), 3, k >= 5u);
    let phi0 = select(select(select(select(0.0, 0.7, k >= 2u), 1.2, k >= 3u), 0.3, k >= 4u), 2.1, k >= 5u);
    return drumMode(r, phi, 0.0, m, modeAlpha(k), 0.0, phi0);
}
// Same activation gates as main(): (0,1),(1,1) always; (0,2)≥3; (2,1)≥4; (1,2)≥5; (3,1)≥6.
fn modeActive(k: u32, modeCount: f32) -> f32 {
    let need = select(select(select(select(2.0, 3.0, k == 1u), 4.0, k == 3u), 5.0, k == 4u), 6.0, k == 5u);
    return select(0.0, 1.0, modeCount >= need);
}

fn hash21(q: vec2<f32>) -> f32 {
    let h = fract(q * vec2<f32>(123.34, 456.21));
    let g = h + dot(h, h + 45.32);
    return fract(g.x * g.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// HSV → RGB for the displacement colouring
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let hh = fract(h);
    let hi = floor(hh * 6.0);
    let f  = hh * 6.0 - hi;
    let p_ = v * (1.0 - s);
    let q_ = v * (1.0 - f * s);
    let tv = v * (1.0 - (1.0 - f) * s);
    let m  = i32(hi) % 6;
    if (m == 0) { return vec3<f32>(v, tv, p_); }
    if (m == 1) { return vec3<f32>(q_, v, p_); }
    if (m == 2) { return vec3<f32>(p_, v, tv); }
    if (m == 3) { return vec3<f32>(p_, q_, v); }
    if (m == 4) { return vec3<f32>(tv, p_, v); }
    return vec3<f32>(v, p_, q_);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let coord  = vec2<i32>(global_id.xy);
    let audioBands = plasmaBuffer[0].xyz;
    let bass   = audioBands.x;
    let mids   = audioBands.y;
    let treble = audioBands.z;
    let previousState = textureLoad(dataTextureC, coord, 0);
    let previousValid = step(0.0001, previousState.a);

    // ─── Sliders (all four honestly wired to this shader's algorithm) ───
    let modeScale  = mix(0.5, 2.5, clamp(u.zoom_params.x, 0.0, 1.0));  // x: radial mode scale ONLY
    let colourMode = clamp(u.zoom_params.y, 0.0, 1.0);                 // y: hue rotation of base colour
    let nodeSharp  = mix(2.0, 30.0, clamp(u.zoom_params.z, 0.0, 1.0)); // z: Chladni node-line sharpness
    let modeCount  = floor(clamp(u.zoom_params.w, 0.0, 1.0) * 6.0) + 2.0; // w: active mode families

    // ─── Polar coords centred on the drum — mouse genuinely re-centres it ───
    let mouse      = u.zoom_config.yz;                    // [mouseX, mouseY] in uv space
    let drumCenter = vec2<f32>(0.5) + (mouse - vec2<f32>(0.5)) * 0.45;
    // HEAD used the raw uv, so the "circular" membrane was an ellipse on any non-square canvas.
    let aspect     = resolution.x / max(resolution.y, 1.0);
    let frameScale = vec2<f32>(max(aspect, 1.0), max(1.0 / aspect, 1.0));
    let p          = (uv - drumCenter) * 2.0 * frameScale;
    let r          = length(p) * modeScale;
    let phi        = atan2(p.y, p.x);

    // ─── Mode family activation by audio band, FFT-bin weighted ───
    // First zeros of J_m: J0→2.4048, 5.5201; J1→3.8317, 7.0156; J2→5.1356; J3→6.3802
    //
    // Physical model: an ideal circular membrane of radius R fixed at its rim
    // vibrates in orthogonal modes u_{mn}. The radial part J_m(α_{mn}·r/R)
    // vanishes at r = R because α_{mn} is the n-th zero of J_m; the azimuthal
    // part cos(m·φ+φ₀) creates m nodal diameters; ω_{mn}·t animates the
    // standing wave. Superposing modes with mismatched frequencies yields the
    // quasi-chaotic interference figures seen on real Chladni plates.
    //
    // Cymatic coupling: each mode's amplitude is additionally modulated by
    // its matching FFT bin, so the spectrum of the audio literally selects
    // which eigenmodes are excited — the same way a loudspeaker under a
    // sand-covered plate picks out resonant patterns.
    var u_total = 0.0;
    var u_radial = 0.0;
    var u_az = 0.0;

    // Bass → (0,1) and (0,2) radially symmetric modes
    let m01 = drumMode(r, phi, time, 0, 2.4048, 2.4048 * 0.5, 0.0) * (0.5 + bass * 0.5) * fftModeWeight(0u);
    u_total += m01;
    u_radial += m01;
    if (modeCount >= 3.0) {
        let m02 = drumMode(r, phi, time, 0, 5.5201, 5.5201 * 0.5, 0.0) * (0.3 + bass * 0.3) * fftModeWeight(1u);
        u_total += m02;
        u_radial += m02;
    }

    // Mids → (1,1) and (2,1)
    let m11 = drumMode(r, phi, time, 1, 3.8317, 3.8317 * 0.5, 0.7) * (0.4 + mids * 0.5) * fftModeWeight(2u);
    u_total += m11;
    u_az += m11;
    if (modeCount >= 4.0) {
        let m21 = drumMode(r, phi, time, 2, 5.1356, 5.1356 * 0.5, 1.2) * (0.3 + mids * 0.4) * fftModeWeight(3u);
        u_total += m21;
        u_az += m21;
    }

    // Treble → (1,2) and (3,1)
    if (modeCount >= 5.0) {
        let m12 = drumMode(r, phi, time, 1, 7.0156, 7.0156 * 0.5, 0.3) * (0.2 + treble * 0.5) * fftModeWeight(4u);
        u_total += m12;
        u_az += m12;
    }
    if (modeCount >= 6.0) {
        let m31 = drumMode(r, phi, time, 3, 6.3802, 6.3802 * 0.5, 2.1) * (0.15 + treble * 0.4) * fftModeWeight(5u);
        u_total += m31;
        u_az += m31;
    }

    // ─── Membrane strikes: each click injects a decaying drum hit ───
    // ripples[i] = (uv.x, uv.y, spawnTime, strength); live count from config.y.
    // A strike is a localised displacement impulse (mallet hit) whose energy
    // radiates outward as a damped wave packet, then rings down exponentially.
    let strikeCount = min(u32(u.config.y), 50u);
    var strikeGlow  = 0.0;
    var strikeDisplacement = 0.0;
    // Pixel-side mode shapes, needed only while a strike is ringing.
    var shapeP = array<f32, 6>(0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    if (strikeCount > 0u) {
        for (var k: u32 = 0u; k < 6u; k = k + 1u) { shapeP[k] = modeShape(k, r, phi); }
    }
    var activeStrikes = 0u;
    for (var i: u32 = 0u; i < strikeCount; i = i + 1u) {
        let rp  = u.ripples[i];
        let age = time - rp.z;
        // ripples[i].w is padding (always 0) — HEAD's `rp.w > 0.001` gate meant no click ever struck the drum.
        if (age >= 0.0 && age < 2.5 && activeStrikes < 8u) {
            activeStrikes = activeStrikes + 1u;
            // Click point mapped into the same drum-centred, aspect-correct polar frame
            let hitP    = (rp.xy - drumCenter) * 2.0 * frameScale;
            let d       = distance(p, hitP);
            // Contact transient: localized decaying impulse + outward-travelling wave packet
            let impulse = exp(-d * d * 10.0) * cos(d * 22.0 - age * 14.0);
            strikeDisplacement += 0.8 * exp(-age * 3.0) * impulse;
            // Impact flash: bright contact point that fades with the ring-down
            strikeGlow += exp(-d * d * 24.0) * exp(-age * 4.5);

            // ── Idea 6: modal strike response ──
            // A mallet hit excites eigenmode k in proportion to that mode's shape at the
            // strike point; each mode then rings at its own ω_k and dies at its own rate
            // (higher α → faster).  Centre hit: only the radial (0,n) modes ring.
            let hitR   = length(hitP) * modeScale;
            let hitPhi = atan2(hitP.y, hitP.x);
            var modal  = 0.0;
            for (var k: u32 = 0u; k < 6u; k = k + 1u) {
                let a_k   = modeAlpha(k);
                let ring  = exp(-age * (0.55 + 0.22 * a_k)) * cos(a_k * 1.8 * age);
                modal += modeActive(k, modeCount) * modeShape(k, hitR, hitPhi) * shapeP[k] * ring;
            }
            strikeDisplacement += 0.55 * modal;
        }
    }

    // Exact-load prior membrane displacement and damp it through the existing
    // A.r state channel. Analytic modes keep driving the target while the
    // stored displacement supplies physically legible ring-down continuity.
    u_total = mix(u_total, previousState.r * 0.965, previousValid * 0.72) + strikeDisplacement;

    // ─── Boundary: circular membrane fixed at r = R ───
    // Dirichlet condition u(R) = 0, softened over a thin rim for anti-aliasing.
    let R      = 0.9;
    let inside = smoothstep(R + 0.03, R, r / modeScale);
    u_total *= inside;

    // ─── Chladni node-line colouring ───
    // Nodes are zero-crossings: glow proportional to |u_total|
    // ── Idea 5: sand on the plate ──
    // Grains migrate to where the plate moves least. A leaky average of |u| lives in A.g
    // (the old write-only `r` channel). Instantaneous zero crossings (gold line below) keep
    // sweeping with the modes; the sand only stays where the figure is stationary.
    // Inherited C from another shader is clamped and converges within ~1.5 s.
    let magnitude = abs(u_total);
    let sandPrev  = clamp(previousState.g, 0.0, 2.0);
    let sandE     = select(magnitude, mix(sandPrev, magnitude, 0.03), previousValid > 0.5);
    let sandK     = 8.0 + nodeSharp * 1.2;                         // node-sharpness slider sets the band width
    let sandDust  = exp(-sandE * sandK) * inside;
    let sandGrain = 0.55 + 0.45 * hash21(floor(vec2<f32>(coord) * 0.5));

    let nodeEdge = abs(u_total);
    let nodeGlow = smoothstep(0.0, 0.5 / nodeSharp, nodeEdge) *
                   smoothstep(1.5 / nodeSharp, 0.5 / nodeSharp, nodeEdge);

    // Displacement → hue, then COLOUR MODE rotates the base hue
    let hue = fract(u_total * 0.15 + time * 0.04 + bass * 0.08 + colourMode);
    let sat = 0.85;
    // Perceptual transfer: HEAD's linear |u|·1.5 left a silent drum at ~0.2 coverage on a photo.
    let val = clamp(sqrt(abs(u_total) * 2.2), 0.0, 1.0) * inside;
    let baseColor = hsv2rgb(hue, sat, val);

    // Nodes → white/gold Chladni lines; Idea 1 — radial vs azimuthal tint
    let nodeKind = smoothstep(-0.15, 0.15, abs(u_az) - abs(u_radial));
    let nodeTint = mix(vec3<f32>(1.0, 0.88, 0.62), vec3<f32>(0.72, 0.9, 1.0), nodeKind);
    var chladniColor = mix(baseColor, nodeTint, nodeGlow * 0.7);

    // Idea 2 — displacement Lambert (signed u as a drum surface)
    let lambert = 0.62 + 0.38 * clamp(u_total * 1.8, -1.0, 1.0);
    chladniColor = chladniColor * lambert;
    // Idea 3 — antinode disks: soft peaks away from the node lines
    let antinode = smoothstep(0.28, 0.75, abs(u_total)) * (1.0 - nodeGlow);
    chladniColor = chladniColor + baseColor * antinode * 0.28;
    // Idea 4 — beat between the first two radial zeros (α02 − α01)
    let radialBeat = 0.5 + 0.5 * cos((5.5201 - 2.4048) * 0.5 * time);
    let radialShare = abs(u_radial) / (abs(u_total) + 0.08);
    chladniColor = chladniColor * (0.78 + 0.22 * radialBeat * smoothstep(0.2, 0.7, radialShare));

    // Sand: warm static grains over the stationary nodal figure
    chladniColor = mix(chladniColor, vec3<f32>(0.86, 0.72, 0.48) * sandGrain, sandDust * 0.55);

    // Strike flash tints the impact zone hot white while the hit rings down
    chladniColor = mix(chladniColor, vec3<f32>(1.0, 0.98, 0.92), clamp(strikeGlow, 0.0, 1.0) * 0.6);

    // Fixed rim: the clamped edge of the membrane catches a faint highlight,
    // anchoring the drum visually where the boundary condition pins u = 0.
    let rim     = smoothstep(0.05, 0.0, abs(r / modeScale - R)) * 0.35;
    chladniColor += vec3<f32>(0.9, 0.85, 0.7) * rim;

    // Blend with image input: the membrane figure overlays the source frame
    // wherever displacement or node glow is strong.
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let blendAlpha = clamp(val * 0.85 + nodeGlow * 0.3 + sandDust * 0.3 + bass * 0.05 + strikeGlow * 0.25, 0.0, 1.0);
    let finalColor = mix(inputColor.rgb, chladniColor, blendAlpha);
    let finalAlpha = max(inputColor.a, blendAlpha);
    let membraneDepth = clamp(0.5 - u_total * 0.16, 0.05, 0.95);
    let finalDepth = mix(inputDepth, membraneDepth, blendAlpha);

    // Output (tone-mapped display), sim state (raw, never clamped), generated membrane depth.
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(finalColor * 1.1), finalAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(u_total, sandE, phi / 6.28318, blendAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
