// ═══════════════════════════════════════════════════════════════════
//  Melting Oil
//  Category: artistic
//  Features: gradient-flow, branchless-ripples, audio-reactive, advection, upgraded-rgba
//  Complexity: Medium
//  Created: Phase B / Optimizer
//  Upgraded: 2026-05-23 — rewired 2026-08-02 (Algorithmist swarm b27)
//
//  Slider contract (saved-preset safe — ids/names/defaults unchanged):
//    x  Viscosity       (0.50) advection step length — liquid thickness
//    y  Turbulence      (0.40) chaotic sinusoidal flow perturbation
//    z  Ripple Strength (0.50) click-stir amplitude: mix(0,2,z) → 1.0
//    w  Color Shift     (0.30) hue-shift mix amount (hueShiftK)
//
//  Engine uniform truth:
//    config       = [time, rippleCount, resW, resH]
//    zoom_config  = [time, mouseX, mouseY, mouseDown]
//    zoom_params  = [viscosity, turbulence, rippleStrength, colorShift]
//
//  Persistent state (extraBuffer, [133..255] ONLY):
//    [133..134] = spring-smoothed mouse position
//    [135..136] = spring velocity
//    [137]       = initialized flag
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Viscosity, y=Turbulence, z=RippleStrength, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

// Fixed constants replacing the old mislabeled slider roles.
// MOUSE_FORCE = 0.4 keeps the mouse gate bit-exact at the default preset.
// AUDIO_K = 1.0 is the old slider-w multiplier on the bass boost.
const MOUSE_FORCE: f32 = 0.4;
const AUDIO_K: f32 = 1.0;

// Critically-damped mouse spring (zeta = 1): the flow bend glides
// toward the raw mouse, which stays the spring target.
const SPRING_OMEGA: f32 = 12.0;
const SPRING_DT: f32 = 0.0166667;

fn safeNormalize2(v: vec2<f32>) -> vec2<f32> {
    return v * inverseSqrt(max(dot(v, v), 1e-8));
}

fn loadHistoryR(coord: vec2<i32>, dims: vec2<i32>) -> f32 {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    let dim = textureDimensions(dataTextureA);
    let dimI = vec2<i32>(dim);
    let dimF = vec2<f32>(f32(dim.x), f32(dim.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    // ── Honest slider constants (saved-preset contract) ─────────────
    let viscosity = clamp(0.85 + u.zoom_params.x * 0.13, 0.5, 0.99);
    let turbK = clamp(u.zoom_params.y, 0.0, 1.0);
    let rippleStrength = clamp(u.zoom_params.z, 0.0, 1.0);
    let hueShiftK = clamp(u.zoom_params.w, 0.0, 1.0);
    let audioK = clamp(AUDIO_K * (1.0 + bass * 0.5), 0.0, 2.0);

    // ── Critically-damped mouse spring (extraBuffer[133..136]) ─────
    let rawMouse = u.zoom_config.yz;
    var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sv = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        sm = rawMouse;
        sv = vec2<f32>(0.0);
    }
    let springAccel = (rawMouse - sm) * (SPRING_OMEGA * SPRING_OMEGA)
                    - sv * (2.0 * SPRING_OMEGA);
    sv += springAccel * SPRING_DT;
    sm += sv * SPRING_DT;
    sm = clamp(sm, vec2<f32>(0.0), vec2<f32>(1.0));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = sm.x;
        extraBuffer[134] = sm.y;
        extraBuffer[135] = sv.x;
        extraBuffer[136] = sv.y;
        extraBuffer[137] = 1.0;
    }

    // ── 9-tap Sobel gradient over last frame's display history ─────
    let r0 = vec3<f32>(
        loadHistoryR(coord + vec2<i32>(-1, -1), dimI),
        loadHistoryR(coord + vec2<i32>( 0, -1), dimI),
        loadHistoryR(coord + vec2<i32>( 1, -1), dimI));
    let r1 = vec3<f32>(
        loadHistoryR(coord + vec2<i32>(-1,  0), dimI),
        loadHistoryR(coord, dimI),
        loadHistoryR(coord + vec2<i32>( 1,  0), dimI));
    let r2 = vec3<f32>(
        loadHistoryR(coord + vec2<i32>(-1,  1), dimI),
        loadHistoryR(coord + vec2<i32>( 0,  1), dimI),
        loadHistoryR(coord + vec2<i32>( 1,  1), dimI));

    let gx = (r0.z + 2.0 * r1.z + r2.z) - (r0.x + 2.0 * r1.x + r2.x);
    let gy = (r2.x + 2.0 * r2.y + r2.z) - (r0.x + 2.0 * r0.y + r0.z);
    let grad = vec2<f32>(gx, gy);
    let gradLen = max(length(grad), 1e-4);
    var flow_dir = grad / gradLen;

    // ── Mouse bend through the spring-smoothed cursor ──────────────
    let mouse = sm;
    let mouseDown = u.zoom_config.w;
    let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
    let dM = length(toMouse);
    let mouseGate = exp(-dM * dM * 12.0) * (MOUSE_FORCE + mouseDown * 0.5);
    let mouseDir = toMouse / max(dM, 1e-4);
    flow_dir = safeNormalize2(mix(flow_dir, mouseDir, mouseGate));

    // ── Turbulence: time-varying sinusoidal perturbation (slider y) ─
    let turbUV = uv * vec2<f32>(aspect, 1.0);
    let turbPhase = turbUV * 9.0 + vec2<f32>(time * 0.7, time * 0.55);
    let turb = vec2<f32>(
        sin(turbPhase.y + sin(turbPhase.x * 1.3 + time * 0.4)),
        cos(turbPhase.x - sin(turbPhase.y * 1.1 - time * 0.5)));
    flow_dir = safeNormalize2(flow_dir + turb * (turbK * 0.35));

    // ── Click stirs: standard guarded ripple loop (slider z) ───────
    var stir = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rip = u.ripples[i];
        let rippleActive = step(1e-4, rip.z);
        let age = max(time - rip.z, 0.0);
        let alive = step(age, 3.0);
        let toR = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
        let dR2 = dot(toR, toR);
        let pulse = exp(-dR2 * 60.0) * (1.0 - age / 3.0) * rippleActive * alive;
        stir += vec2<f32>(-toR.y, toR.x) * 0.5 * pulse;
    }
    stir *= mix(0.0, 2.0, rippleStrength);
    flow_dir = safeNormalize2(flow_dir + stir);

    // ── Advection sampling (hand-tuned, verbatim) ──────────────────
    let advectStep = flow_dir * viscosity * (1.0 + audioK * 0.4);
    let last_pos = vec2<f32>(coord) - advectStep;
    let color = textureSampleLevel(readTexture, u_sampler, clamp(last_pos / dimF, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // ── Hue shift (verbatim PHI math) + per-band FFT shimmer ───────
    // 8 vertical bands ride engine FFT bins so the oil sheen shimmers
    // across the spectrum; the core golden-ratio phase is untouched.
    let band = u32(clamp(uv.y, 0.0, 0.9999) * 8.0);
    let bandFFT = plasmaBuffer[(band % 8u) + 1u].x;
    let hue_shift = (gradLen * 0.8 + time * 0.05) * hueShiftK * PHI;
    let hue_phase = hue_shift + bandFFT * 0.3;
    let hueMat = vec3<f32>(0.5 + 0.5 * sin(hue_phase),
                           0.5 + 0.5 * sin(hue_phase + 2.094),
                           0.5 + 0.5 * sin(hue_phase + 4.188));
    var shifted = mix(color.rgb, color.rgb * (0.6 + hueMat * 0.8), hueShiftK);

    // ── Alpha (hand-tuned, verbatim) ───────────────────────────────
    let luma = dot(shifted, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.5 + gradLen * 0.6 + mouseGate * 0.2 + treble * 0.05 + 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(shifted, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
