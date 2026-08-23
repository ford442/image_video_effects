// ═══════════════════════════════════════════════════════════════════
//  Magnetic Interference - Phase B Audio-Reactivity Upgrade
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, bass-pulse, mids-morph,
//            treble-sparkle, ripple-integration, depth-aware,
//            chromatic-aberration, aces-tone-map, temporal-feedback,
//            velocity-trails
//  Complexity: Medium
//  Upgraded: 2026-08-23 (Batch 64)
//
//  FIXED IN THIS PASS — three defects.
//
//  (a) State written into the engine's audio slots. The shader stored the
//      previous mouse position at `extraBuffer[0]` and `extraBuffer[1]` — which
//      per docs/BINDING_CONTRACT.md are BASS and MID. It was overwriting the
//      audio every other shader in the chain reads, and reading back values the
//      engine rewrites each frame, so its own mouse-velocity term was garbage
//      too. Moved to the scratch range `[133..134]`, written only by invocation
//      (0,0). The extraBuffer audit carried these as two baseline violations.
//
//  (b) Audio envelope smuggled through texel (0,0). The envelope was stashed in
//      `dataTextureA` at pixel (0,0) — corrupting the feedback buffer's corner
//      texel and making the whole frame depend on one arbitrary pixel. It now
//      lives in `extraBuffer[135]` alongside the pointer state, so A carries
//      display RGBA everywhere.
//
//  (c) The ripple loop bound was unguarded:
//
//      let rippleCount = u32(u.config.y);
//
//  The contract requires `min(u32(u.config.y), 50u)` (docs/BINDING_CONTRACT.md).
//  `config.y` is engine-supplied and normally within range, but an unclamped
//  `u32` conversion of a float is undefined for negative or oversized values
//  and would index past the 50-element ripple array.
//
//  TWO NEW STRUCTURES
//
//    1. Per-band domain-wall spectrum — magnetic domain walls are pinned at
//       defects and each wall responds at its own frequency. Eight wall
//       families, one per FFT bin, now carry their own pinning sites and
//       oscillation rate, so the interference pattern separates into spectral
//       bands rather than one field breathing globally.
//
//    2. Hysteresis memory — ferromagnets remember their magnetisation history;
//       the field lags the drive and only flips past a coercive threshold.
//       The previous magnetisation is read back from dataTextureC and relaxed
//       toward the driven state with a coercivity gate, so the pattern shows
//       real magnetic lag and remanence rather than instantaneous response.
//  Transform: Tightened bass envelope to canonical attack/release,
//             added beat-pulsed magnetic field, mids-driven swirl,
//             rotating chromatic aberration, and treble sparkle.
//             Ripple interference is now audio-amplified.
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ═══ Audio envelope (canonical smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32) -> f32 {
    let k = select(0.15, 0.8, bass > prev);
    return mix(prev, bass, k);
}

// ═══ 2D hash for treble sparkle ═══
fn hash21(p: vec2<f32>) -> f32 {
    let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453;
    return fract(n);
}

// ═══ Rotate vector by angle ═══
fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ═══ Gravity well (mouse attraction) ═══
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}

// ═══ Tent alpha curve ═══
fn tentAlpha(x: f32) -> f32 {
    return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

// ═══ ACES tone mapping ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Chromatic shift for generative / displaced output ═══
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, angleOffset: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5) + angleOffset;
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;

    // ─── Persistent state, scratch range only ───
    // [133..134] = previous pointer, [135] = audio envelope. Indices 0..132 are
    // ENGINE-OWNED (bass/mid/treble, historyHead, FFT bins) — see the header.
    let prevEnv = extraBuffer[135];
    let env = bass_env(prevEnv, bass);

    let prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let mouseVel = select(mouse - prevMouse, vec2<f32>(0.0), length(prevMouse) < 0.001);
    let mouseSpeed = length(mouseVel);

    let strength = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let scanline_intensity = u.zoom_params.w;

    // ─── Audio-derived modulators ───
    let bassPulse  = 1.0 + env * 0.4 + bass * 0.3;
    let midsRot    = mids * 0.5;
    let trebleGlow = treble * 0.35;

    let aspect = res.x / res.y;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uv_corrected, mouse_corrected);

    // Mouse X modulates radius; speed stretches it; bass pulses it
    let effectiveRadius = radius * (1.0 + mouse.x * 0.3 + mouseSpeed * 5.0) * (1.0 + env * 0.2);
    let audioStrength = strength * bassPulse * (1.0 + mids * 0.2);
    let audioScanlines = scanline_intensity * (1.0 + env * 0.5);

    // ─── Magnetic displacement field with mids-driven swirl ───
    let pull = audioStrength * 0.05 / (dist * dist + 0.01);
    let influence = smoothstep(effectiveRadius, 0.0, dist);
    let dir = uv - mouse;
    let swirl = rotate(dir, midsRot + env * 0.2);
    let magneticDisp = swirl * pull * influence;

    // ─── Ripple system integration (audio-amplified shockwaves) ───
    var rippleDisp = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rElapsed = time - ripple.z;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, ripple.xy);
            let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            let rAmp = 0.5 * (1.0 + env * 0.5 + bass * 0.3);
            rippleDisp += (uv - ripple.xy) * rWave * smoothstep(0.3, 0.0, rDist) * rAmp;
        }
    }

    // ─── Gravity well + velocity trail drag ───
    let gStrength = select(0.0, 0.03 + treble * 0.02, isMouseDown);
    let gWell = gravityWell(uv, mouse, gStrength);
    let gravityDisp = gWell * influence * 0.02;
    let velDisp = mouseVel * influence * (0.1 + env * 0.1);

    // ── Structure 1: per-band domain-wall spectrum ──────────────────────────
    // Eight wall families, each pinned at its own defect lattice and
    // oscillating at its own rate, driven by its own FFT bin.
    var wallDisp = vec2<f32>(0.0);
    var wallEnergy = 0.0;
    for (var w = 0u; w < 8u; w = w + 1u) {
        let fw = f32(w);
        let bandE = plasmaBuffer[w + 1u].x;
        // Pinning lattice: walls sit on a rotated grid unique to each family.
        let ang = fw * 0.7853981634;
        let dir = vec2<f32>(cos(ang), sin(ang));
        let k = 18.0 + fw * 11.0;
        let phase = dot(uv, dir) * k - time * (0.8 + fw * 0.35);
        // A domain wall is a narrow transition, not a sine — hence the power.
        let wall = pow(abs(sin(phase)), 14.0);
        wallDisp += dir * wall * bandE * 0.004;
        wallEnergy += wall * bandE;
    }
    wallEnergy = min(wallEnergy, 2.0);

    let totalDisp = magneticDisp + rippleDisp + gravityDisp + velDisp + wallDisp;
    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

    // ─── Sample video input at displaced UV ───
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // ─── Structure 2: hysteresis memory ───
    // Ferromagnets lag their drive and only flip past a coercive field. The
    // previous magnetisation relaxes toward the driven state at a rate gated by
    // how far the drive exceeds coercivity, giving real lag and remanence.
    let prevState = textureLoad(dataTextureC, pixel, 0);
    let prevColor = prevState.rgb;
    let fieldMag = length(totalDisp) * 20.0;

    let coercivity = 0.18 + (1.0 - env) * 0.22;
    let drive = clamp(fieldMag + wallEnergy * 0.3 + bass * 0.4, 0.0, 3.0);
    // Below coercivity the domain is pinned and barely moves; above it, it
    // switches quickly. smoothstep is the soft switching curve.
    let switching = smoothstep(coercivity, coercivity + 0.45, drive);
    let remanence = mix(0.92, 0.35, switching);

    let feedbackMix = clamp(tentAlpha(fieldMag) * (0.1 + mouseSpeed * 2.0 + env * 0.15)
                            + remanence * 0.35, 0.0, 0.92);
    var feedbackColor = mix(baseColor, prevColor, feedbackMix);
    // Domain walls glow where they are actively sweeping.
    feedbackColor += vec3<f32>(0.45, 0.72, 1.0) * wallEnergy * switching * 0.22;

    // Spectral tint via mix, not per-channel sampling
    let tint = vec3<f32>(1.0 + aberration * 0.3, 1.0, 1.0 - aberration * 0.3);
    let tintedColor = mix(feedbackColor, feedbackColor * tint, fieldMag * 0.5);

    // Scanlines modulated by field magnitude
    let scanline = sin((uv.y + fieldMag * 0.5) * res.y * 0.5 + time * 5.0);
    let scanline_mask = 1.0 - (scanline * 0.5 + 0.5) * audioScanlines;
    var color = tintedColor * scanline_mask;

    // ─── Treble sparkle overlay ───
    let sparkle = hash21(uv * 1200.0 + vec2<f32>(time * 80.0));
    let sparkleMask = smoothstep(0.88, 0.98, sparkle) * trebleGlow;
    color += vec3<f32>(sparkleMask * 0.8);

    // ─── Chromatic aberration + ACES tone map ───
    let caStr = 0.003 * (1.0 + env) + depth * 0.001;
    let caAngle = time * 0.3 + midsRot;
    color = genChromaticShift(color, uv, caStr * aberration, caAngle);
    color = acesToneMap(color * (0.9 + mids * 0.2 + env * 0.1));

    // ─── Depth-aware compositing (stronger in background) ───
    let fog = 1.0 - exp(-depth * 1.5);
    color = mix(baseColor, color, fog * 0.5 + 0.5);

    // ─── Semantic alpha = field intensity * distance falloff * depth + sparkle ───
    let fieldMagnetic = length(magneticDisp) * 10.0;
    let alpha = clamp(fieldMagnetic * influence + env * 0.2 + depth * 0.15 + sparkleMask * 0.5, 0.0, 1.0);

    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));

    if (pixel.x == 0 && pixel.y == 0) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
        extraBuffer[135] = env;
        // A now carries display RGBA here too — the envelope no longer needs to
        // squat on this texel.
        textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    } else {
        textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    }
}
