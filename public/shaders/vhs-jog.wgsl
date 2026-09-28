// ═══════════════════════════════════════════════════════════════════
//  VHS Jog Wheel
//  Category: interactive-mouse
//  Features: mouse-driven, click-reactive, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: cue/review noise bars; pause-mode field flutter; reverse-play colour phase error
//  A packing: pre-ACES linear display RGB + alpha; C read back as colour (max-hold streak + pause field)
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
  zoom_params: vec4<f32>,  // x=Noise, y=DistortionFreq, z=ColorBleed, w=Scanlines
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Rotate the CbCr chroma plane of an RGB colour by `ang` radians (BT.601 weights).
fn rotateChroma(c: vec3<f32>, ang: f32) -> vec3<f32> {
    let y = dot(c, vec3<f32>(0.299, 0.587, 0.114));
    let cb = (c.b - y) * 0.564;
    let cr = (c.r - y) * 0.713;
    let s = sin(ang);
    let co = cos(ang);
    let cb2 = cb * co - cr * s;
    let cr2 = cb * s + cr * co;
    return vec3<f32>(y + 1.403 * cr2, y - 0.344 * cb2 - 0.714 * cr2, y + 1.773 * cb2);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv_raw = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));

    // Base color for alpha preservation
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv_raw, 0.0);

    // Params — bass amplifies tracking instability, mids the warp freq, treble the bleed
    let noise_amt = clamp(u.zoom_params.x + bass * 0.15, 0.0, 1.0);
    let dist_freq = (u.zoom_params.y * 50.0 + 1.0) * (1.0 + mids * 0.5);
    let bleed_amt = u.zoom_params.z * 0.02 * (1.0 + bass * 0.4 + treble * 0.4);
    let scanline_intensity = u.zoom_params.w;

    // Mouse Inputs
    let mouse_x = u.zoom_config.y; // 0.0 to 1.0
    let mouse_y = u.zoom_config.z; // 0.0 to 1.0
    let mouse_down = u.zoom_config.w;

    // Jog Wheel: Mouse X controls horizontal tear/distortion intensity
    let shuttle = abs(mouse_x - 0.5) * 2.0;                 // 0 at pause, 1 at full cue/review
    let distortion_strength = shuttle * shuttle * 0.5;       // Stronger at edges
    let direction = sign(mouse_x - 0.5);

    // Tracking: Mouse Y controls vertical offset
    let vertical_tracking = (mouse_y - 0.5) * 0.2;

    // Apply Vertical Tracking (looping)
    var uv = uv_raw;
    let headRollPhase = fract(uv.y - time * (0.55 + distortion_strength * 2.5) * direction + 0.5);
    let headRollX = (headRollPhase - 0.5) / 0.055;
    let headSwitchRoll = exp(-(headRollX * headRollX)) * distortion_strength;
    uv.y = fract(uv.y + vertical_tracking + time * 0.05 * distortion_strength * direction + headSwitchRoll * 0.035 * direction);

    var tapeSlip = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let slipY = fract(ripple.y + age * (0.22 + mids * 0.10));
            let bandDist = abs(fract(uv_raw.y - slipY + 0.5) - 0.5);
            tapeSlip += (1.0 - smoothstep(0.0, 0.035, bandDist)) * (1.0 - age / 2.2);
        }
    }
    tapeSlip += mouse_down * (1.0 - smoothstep(0.0, 0.025, abs(uv_raw.y - mouse_y))) * 0.45;
    tapeSlip = min(tapeSlip, 1.5);

    // Horizontal Distortion (Jitter)
    // Create 'bands' of distortion based on Y and Time
    let dist_wave = noise(vec2<f32>(uv.y * dist_freq, time * 20.0));
    // Threshold the wave to make it look like digital tearing
    let tear = smoothstep(0.4, 0.6, dist_wave) * distortion_strength;

    let horizontalStreak = sin(uv.y * resolution.y * 0.15 - time * (35.0 + dist_freq)) * (headSwitchRoll + tapeSlip);
    uv.x += (dist_wave - 0.5) * tear * 0.2 + horizontalStreak * (0.015 + distortion_strength * 0.08) * direction;

    // ── IDEA 1: cue/review noise bars ──
    // Fast-shuttling a VHS drags the heads across several tracks per field, so the picture
    // shows evenly spaced horizontal noise bars. Bar count grows with shuttle speed (2 → 7),
    // the bars scroll against the play direction (opposite sign to the head-switch roll), and
    // they widen slightly at the very top of the speed range.
    let cueAmt = smoothstep(0.30, 0.95, shuttle);
    let cueBars = 2.0 + floor(cueAmt * 5.0);
    let cueWidth = 0.055 + cueAmt * 0.03;
    let cuePhase = fract(uv_raw.y * cueBars + time * (0.8 + cueAmt * 1.4) * direction);
    let cueBand = 1.0 - smoothstep(cueWidth * 0.5, cueWidth, abs(cuePhase - 0.5));
    let cueMask = cueBand * cueAmt;
    // The head skids sideways inside the bar as well, dragging the row along.
    uv.x += cueMask * (noise(vec2<f32>(uv_raw.y * 90.0, time * 30.0)) - 0.5) * 0.06 * direction;

    // Color Bleed (Chromatic Aberration)
    // R, G, B sampled at different X offsets
    let r_offset = bleed_amt * (1.0 + distortion_strength * 5.0);
    let b_offset = -bleed_amt * (1.0 + distortion_strength * 5.0);

    let r = textureSampleLevel(readTexture, u_sampler, fract(uv + vec2<f32>(r_offset, 0.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, fract(uv), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, fract(uv + vec2<f32>(b_offset, 0.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // ── IDEA 3: reverse-play colour phase error ──
    // In review (backward shuttle) the colour-under carrier is demodulated with the wrong
    // phase reference, so each head-track band of rows carries its own hue rotation error.
    // Bands re-roll ~6x/s; the rotation settles to zero as the speed drops toward pause.
    let reverseAmt = smoothstep(0.06, 0.55, shuttle) * step(mouse_x, 0.4999);
    let phaseBand = floor(uv_raw.y * (6.0 + cueBars) + time * 0.5 * direction);
    let phaseErr = (hash12(vec2<f32>(phaseBand, floor(time * 6.0))) - 0.5) * PI * 1.3;
    color = rotateChroma(color, phaseErr * reverseAmt);

    // Static Noise
    let static_noise = noise(vec2<f32>(uv.x * resolution.x * 0.25, uv.y * 80.0 + time * 12.0));
    color += (static_noise - 0.5) * noise_amt;

    // Cue bar body: coarse row-streaked snow with a slight luma lift (idea 1).
    let cueSnow = noise(vec2<f32>(uv_raw.x * resolution.x * 0.12 + time * 40.0, uv_raw.y * resolution.y * 0.5));
    color = mix(color, vec3<f32>(0.25 + cueSnow * 0.7), cueMask * 0.85);

    // Exact, clamped display-history loads make horizontal tape streaks stable.
    // C holds last frame's pre-ACES linear display RGB (A packing).
    let streakOffset = i32(round(direction * (3.0 + distortion_strength * 14.0 + tapeSlip * 8.0)));
    let history = textureLoad(dataTextureC, clamp(coord - vec2<i32>(streakOffset, 0), vec2<i32>(0), maxCoord), 0);
    color = max(color, clamp(history.rgb, vec3<f32>(0.0), vec3<f32>(3.0)) * (0.42 + headSwitchRoll * 0.25 + tapeSlip * 0.18));

    // ── IDEA 2: pause-mode field flutter ──
    // Near X = 0.5 the deck is in still-frame: the head reads the same two fields over and
    // over. Odd screen rows come from the held picture (C, jittering ±1 row per frame) and
    // even rows from the live source, so the still shimmers instead of sitting dead.
    let pauseAmt = 1.0 - smoothstep(0.0, 0.09, shuttle);
    if (pauseAmt > 0.001) {
        let rowJitter = i32(floor(hash12(vec2<f32>(floor(time * 30.0), 3.0)) * 3.0)) - 1;
        let fieldParity = (coord.y + rowJitter) & 1;
        let held = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, rowJitter), vec2<i32>(0), maxCoord), 0).rgb;
        // Lagging field: mostly the held picture, a little live feed so the row converges to
        // the source through C instead of decaying to black or stacking to white.
        let heldField = mix(color, clamp(held, vec3<f32>(0.0), vec3<f32>(3.0)), 0.8);
        let flutter = (hash12(vec2<f32>(f32(coord.y), floor(time * 30.0))) - 0.5) * 0.06 * pauseAmt;
        let fieldColor = select(color, heldField, fieldParity == 1) + flutter;
        color = mix(color, fieldColor, pauseAmt);
    }

    // Scanlines — on the screen row, not the rolled tape row
    let scanline = sin(uv_raw.y * resolution.y * 0.5 * PI);
    color *= 1.0 - (scanline * scanline_intensity * 0.5);

    // Vignette / Tube curve (optional, keep it subtle)
    let d = distance(uv_raw, vec2<f32>(0.5));
    color *= 1.0 - d * 0.3;
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(3.0));

    // Alpha: preserve input transparency while blending tear / slip / cue-bar coverage
    let finalAlpha = clamp(mix(baseColor.a, 1.0, clamp(tear * 0.7 + tapeSlip * 0.3 + cueMask * 0.5, 0.0, 1.0)), 0.0, 1.0);
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(color), finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_raw, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}
