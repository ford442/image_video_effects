// ═══════════════════════════════════════════════════════════════════
//  Quantum Flux
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-23, 2026-08-02, 2026-11-09
//  Ideas: per-channel jitter + RGB split; radial standing wave; hue drift; interference scanlines;
//         click decoherence bursts; per-sector FFT jitter voices;
//         radial probability shells (jitter x standing-wave psi^2, §12.1 T2/T3);
//         quantum-jump hue (6 energy levels, plateau-then-jump)
//  A packing: display RGBA; texel (0,0) = (glide.x, glide.y, 7 marker, fract(time)) cursor state (not display data)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so the spring could never persist.
// State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel and
// integrates the same step, only pixel (0,0) stores it. First-order glide (a velocity cannot be stored
// f16-safely); at rest it snaps exactly onto the cursor.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    // w can round up to exactly 1.0 in f16 (fract(time) > 0.9997): accept it.
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
    return select(raw, snapped, ok);
}

// ── Rescue R2: engine FFT bins (extraBuffer[5 + bin], 0..1) ──────────
// HEAD read plasmaBuffer[1..8].x per sector; the host never uploads those (always 0).
fn fftBin(bin: u32) -> f32 {
    let idx = 5u + min(bin, 127u);
    return select(0.0, extraBuffer[min(idx, arrayLength(&extraBuffer) - 1u)], arrayLength(&extraBuffer) > idx);
}
// The 8 sector voices spread over the bins where the energy is: {0,1,2,4,7,11,19,32}.
fn fftVoice(v: u32) -> f32 {
    let lo = vec4<u32>(0u, 1u, 2u, 4u);
    let hi = vec4<u32>(7u, 11u, 19u, 32u);
    let k = v & 3u;
    return fftBin(select(lo[k], hi[k], v >= 4u));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Slider params (roles kept EXACTLY): x = Flux Jitter, y = Wave Freq,
    // z = Color Drift, w = Flux Radius — each rides its own audio band.
    let jitterBase = u.zoom_params.x * (1.0 + treble * 0.6);
    let freq = u.zoom_params.y * (1.0 + mids * 0.4);
    let driftSpeed = u.zoom_params.z * (1.0 + mids * 0.5);
    let radiusParam = u.zoom_params.w * (1.0 + bass * 0.3);

    // ─── Gliding flux center (Rescue R1, rate 9 = HEAD omega) ───
    // The raw cursor is only the glide TARGET; the influence zone trails it like a
    // probability cloud that cannot collapse instantly. HEAD's critically-damped spring
    // lived in extraBuffer[133..138], which the host re-uploads zeroed every frame, so
    // the centre always sat on the raw cursor. The state now lives in A texel (0,0).
    let mouse = u.zoom_config.yz;
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let fluxCenter = glideStep(glideState, mouse, time, 9.0);

    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(fluxCenter.x * aspect, fluxCenter.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let influenceRadius = radiusParam * 0.8 + 0.1;
    let influence = smoothstep(influenceRadius, 0.0, dist);

    // ─── Per-sector FFT voices ───
    // The influence zone is sliced into 8 angular sectors around the glided
    // center; each wedge's jitter magnitude rides its own FFT bin, so
    // different directions vibrate to different frequencies.
    let delta = uvCorrected - mouseCorrected;
    let angle = atan2(delta.y, delta.x);
    let sectorF = floor((angle + 3.14159265) / 6.2831853 * 8.0);
    let sector = u32(sectorF) % 8u;
    // Rescue R2: sector -> engine FFT bin (extraBuffer[5 + bin]) instead of plasmaBuffer[1..8].
    let sectorVoice = fftVoice(sector) * 0.3;

    // ─── Click decoherence bursts ───
    // Each live ripple (a click) spikes the jitter locally at its click
    // point: a decaying bump in an aspect-corrected ~0.25 radius falloff,
    // exp(-rippleAge * 2.0), effective lifetime ~1.2s. Reality flickers
    // where you clicked without holding the cursor still.
    var clickBurst = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge > 0.0 && rippleAge < 1.2) {
            let ripplePos = vec2<f32>(ripple.x * aspect, ripple.y);
            let rippleDist = distance(uvCorrected, ripplePos);
            clickBurst = clickBurst + jitterBase * 0.6
                * smoothstep(0.25, 0.0, rippleDist) * exp(-rippleAge * 2.0);
        }
    }

    // The radial standing-wave phase (kept from HEAD's `wave`), shared with Idea 1.
    let phi = dist * (freq * 50.0) - time * 5.0;

    // ── Idea 1: radial probability shells (jitter x psi^2) ───────────────
    // HEAD's jitter amplitude was flat inside the cloud, but a probability density
    // has structure. The wave phase phi is a standing wave; psi^2 = sin^2(phi) is its
    // density. Uncertainty (jitter + split) piles into the antinode shells, which
    // travel outward with the wave, and the photo is crisp at the nodes. The
    // weight 0.35 + 1.3 sin^2(phi) has mean 1.0, so the default strength is kept.
    // At Wave Freq -> 0 there are no spatial shells, so the weight fades to 1.
    let psi = sin(phi);
    let shell = mix(1.0, 0.35 + 1.3 * psi * psi, smoothstep(0.0, 0.08, freq));

    // Local jitter magnitude: slider base, voiced by this wedge's FFT bin and
    // shaped by the probability shells, spiked by click decoherence bursts
    // (the bursts sit at the click point, not on the shells, so they stay unweighted).
    let jitterAmount = jitterBase * (1.0 + sectorVoice) * shell + clickBurst;

    let seed = uv + vec2<f32>(time * 0.1, time * 0.1);
    let noiseX = (rand(seed) - 0.5) * 2.0;
    let noiseY = (rand(seed + vec2<f32>(1.0, 1.0)) - 0.5) * 2.0;
    let jitter = vec2<f32>(noiseX, noiseY) * jitterAmount * 0.05 * influence;
    let wave = psi * 0.02 * influence;

    let split = jitterAmount * 0.02 * influence;
    let uvR = clamp(uv + jitter + vec2<f32>(wave + split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - jitter + vec2<f32>(0.0, wave), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + jitter * 0.5 - vec2<f32>(split + wave, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Hue drift (branchless via mix on influence)
    var hsv = rgb2hsv(color);
    hsv.x = fract(hsv.x + (time * driftSpeed * 0.5) + (dist * 2.0));
    // ── Idea 2: quantum-jump hue ─────────────────────────────────────────
    // A quantum system's colour is quantised, but HEAD's hue drift was continuous.
    // The drifted hue is snapped to 6 energy levels with a fast smoothstep between
    // them: plateau-then-jump hue steps over time, and (through the existing
    // dist * 2 term) concentric hue shells around the flux centre. Drift Speed keeps
    // its role (how fast the levels advance, and the mask below).
    let hueL = hsv.x * 6.0;
    hsv.x = fract((floor(hueL) + smoothstep(0.78, 1.0, fract(hueL))) / 6.0);
    hsv.y = min(1.0, hsv.y + influence * 0.2);
    let driftedColor = hsv2rgb(hsv);
    let driftMask = clamp(driftSpeed * 10.0, 0.0, 1.0) * smoothstep(0.0, 0.01, influence);
    color = mix(color, driftedColor, driftMask);

    // Interference scanlines
    let interference = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.5 + 0.5;
    color = mix(color, color * (0.8 + 0.2 * interference), influence * 0.5);

    // Meaningful alpha: blend weight from influence + chromatic split + base alpha
    let splitMag = abs(sR.r - sB.b) + abs(sG.g - sR.r);
    let alpha = clamp(baseSample.a * 0.5 + influence * 0.3 + splitMag * 0.4 + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    // dataTextureA = display RGBA, except texel (0,0): cursor-glide state (Rescue R1).
    // The display pixel at (0,0) still goes to writeTexture above.
    var aOut = vec4<f32>(color, alpha);
    if (global_id.x == 0u && global_id.y == 0u) {
        aOut = vec4<f32>(fluxCenter, GLIDE_MARK, fract(time));
    }
    textureStore(dataTextureA, coord, aOut);
}
