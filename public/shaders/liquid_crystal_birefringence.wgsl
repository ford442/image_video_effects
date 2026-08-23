// ═══════════════════════════════════════════════════════════════════════════════
//  liquid_crystal_birefringence.wgsl - Liquid Crystal Optical Effects
//
//  RGBA Focus: Alpha = polarization rotation amount
//  Techniques:
//    - Birefringent double refraction
//    - Polarization rotation through twisted nematic
//    - Color shifting based on cell thickness
//    - Electric field response (mouse-driven + click voltage pulses)
//    - Schlieren texture visualization
//    - Honest audio: bass -> Frederiks cell compression, mids -> twist
//      oscillation, treble -> Schlieren sparkle grain
//    - 8-bin spectral retardation bands (per-bin Newton-ring fringes)
//    - Spring-damper smoothed mouse defect core (extraBuffer[133..134])
//    - Crossed-polarizer analyzer obeying Malus's law, steered by the pointer
//    - Frederiks relaxation lag read back from dataTextureC
//  Target: 4.7★ rating
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
//
//  BUG FIXED IN THIS PASS — depth clobber. The shader wrote its polarization
//  alpha into writeDepthTexture:
//
//      textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0, 0, 1));
//
//  so every depth-aware shader chained after this one read polarization instead
//  of scene geometry, and the engine's depth swap fed that back in. Scene depth
//  is now preserved and only modulated by the cell's effective thickness.
//
//  TWO NEW STRUCTURES
//
//    1. Crossed-polarizer analyzer (Malus's law) — the cell now sits between a
//       fixed polarizer and an analyzer whose angle follows the held pointer.
//       Transmission goes as cos² of the angle between the emergent
//       polarization and the analyzer axis, which is what produces the dark
//       extinction brushes real liquid-crystal microscopy shows wherever the
//       director lines up with either axis. Previously the "polarization" was
//       applied with no analyzer at all, so the extinction structure — the most
//       recognisable feature of the effect — could not appear.
//
//    2. Frederiks relaxation lag — real nematic cells do not switch instantly;
//       rise time falls with applied voltage while decay is voltage-independent
//       and slow. The transmitted field is now relaxed toward its new state
//       through dataTextureC with an asymmetric time constant, so bright
//       transitions snap under voltage and dark ones bleed away.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Schlieren texture (liquid crystal director field)
fn schlierenTexture(uv: vec2<f32>, time: f32) -> vec2<f32> {
    let scale = 8.0;
    let x = uv.x * scale;
    let y = uv.y * scale;

    // Twisted nematic pattern
    let twist = sin(x + time * 0.5) * cos(y + time * 0.3);
    let angle = twist * PI * 0.5;

    return vec2<f32>(cos(angle), sin(angle));
}

// Director field with defects
fn directorField(uv: vec2<f32>, time: f32, mouse: vec2<f32>) -> vec2<f32> {
    var dir = vec2<f32>(0.0);

    // Base twist
    let baseAngle = uv.x * PI * 2.0 + time * 0.2;
    dir = vec2<f32>(cos(baseAngle), sin(baseAngle));

    // Mouse creates defect
    let toMouse = uv - mouse;
    let dist = length(toMouse);
    let defectStrength = smoothstep(0.3, 0.0, dist);
    let defectAngle = atan2(toMouse.y, toMouse.x) * 0.5;
    let defectDir = vec2<f32>(cos(defectAngle), sin(defectAngle));

    dir = mix(dir, defectDir, defectStrength);

    // Add turbulence
    let turb = schlierenTexture(uv * 2.0, time);
    dir = normalize(dir + turb * 0.3);

    return dir;
}

// Birefringent phase retardation (physical constants preserved verbatim)
fn phaseRetardation(thickness: f32, birefringence: f32, wavelength: f32) -> f32 {
    return 2.0 * PI * thickness * birefringence / wavelength;
}

// Apply polarization rotation (Mueller-matrix math preserved verbatim)
fn rotatePolarization(color: vec3<f32>, angle: f32, retardation: vec3<f32>) -> vec3<f32> {
    // Simplified Mueller matrix for twisted nematic
    let cosA = cos(angle);
    let sinA = sin(angle);

    // Each channel gets different retardation
    var result: vec3<f32>;
    result.r = color.r * cosA * cosA + color.g * sinA * sinA * cos(retardation.r);
    result.g = color.r * sinA * sinA + color.g * cosA * cosA * cos(retardation.g);
    result.b = color.b * cos(retardation.b);

    return result;
}

// Color from birefringence
fn birefringenceColor(phase: f32) -> vec3<f32> {
    // Newton's rings color sequence
    let hue = fract(phase / (2.0 * PI));
    return vec3<f32>(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.19) * 0.5 + 0.5
    );
}

// ── Spectrum retardation bands ────────────────────────────────────────────────
// Each FFT bin (plasmaBuffer[1..8]) adds a radial Newton-ring fringe to the
// phase retardation: the rainbow decomposes into 8 spectral bands.
fn spectralFringe(uv: vec2<f32>, center: vec2<f32>, time: f32) -> f32 {
    let dist = length(uv - center);
    var fringe = 0.0;
    for (var i: u32 = 1u; i <= 8u; i = i + 1u) {
        let energy = plasmaBuffer[i].x;
        let binFreq = 4.0 + f32(i) * 3.0; // higher bins -> tighter rings
        let ring = cos(dist * binFreq * 2.0 * PI - time * (1.0 + f32(i) * 0.35));
        fringe += energy * ring;
    }
    return fringe * 0.18; // modest phase modulation, keeps physical colors dominant
}

// ── Click voltage pulses ──────────────────────────────────────────────────────
// Each click ripple is a propagating voltage front: a travelling Gaussian ring
// that locally flips the director orientation as it passes, then relaxes.
fn clickVoltagePulse(uv: vec2<f32>, time: f32) -> f32 {
    var pulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let frontRadius = age * 0.45;             // front propagation speed
            let dist = length(uv - ripple.xy);
            let band = dist - frontRadius;
            let ring = exp(-band * band * 90.0);      // thin travelling front
            let decay = max(0.0, 1.0 - age / 3.0);
            pulse += ring * decay;
        }
    }
    return min(pulse, 1.5);
}

// ── Treble sparkle grain ──────────────────────────────────────────────────────
// Cheap hash grain; treble makes the Schlieren texture glitter.
fn sparkleGrain(uv: vec2<f32>, time: f32) -> f32 {
    let p = uv * 512.0 + vec2<f32>(time * 37.0, time * 61.0);
    let h = sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453;
    return fract(h);
}

// ── ACES filmic tone map (Narkowicz fit) ─────────────────────────────────────
fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// ── Crossed-polarizer analyzer (Malus's law) ─────────────────────────────────
// Intensity through an analyzer at `analyzerAngle` for light whose plane of
// polarization has been rotated to `emergentAngle`: I = I0 * cos^2(delta).
// The retardation term reintroduces the wavelength dependence, so the
// extinction brushes are coloured rather than neutral grey.
fn malusTransmission(emergentAngle: f32, analyzerAngle: f32, retardation: vec3<f32>) -> vec3<f32> {
    let delta = emergentAngle - analyzerAngle;
    let c = cos(delta);
    let extinction = c * c;
    // sin^2(delta) * sin^2(retardation/2) is the classic crossed-polar term.
    let s = sin(delta);
    let cross = s * s;
    let half = retardation * 0.5;
    let sr = sin(half);
    return vec3<f32>(extinction) + cross * sr * sr;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // ── Slider params (preset contract: zoom_params.x/y/z/w) ────────────────
    let cellThickness = 0.5 + u.zoom_params.x;        // Thickness: 0.5-1.5
    let twistAngle = u.zoom_params.y * PI * 2.0;      // Twist: 0-2π across cell
    let birefringence = 0.1 + u.zoom_params.z * 0.2;  // Birefringence Δn: 0.1-0.3
    let voltage = u.zoom_params.w;                    // Voltage: Frederiks drive

    // ── Spring-damper mouse defect core ─────────────────────────────────────
    // State: extraBuffer[133..134] = smoothed mouse xy (2 slots, [0..4] and
    // [5..132] engine FFT bins are untouched). Position-only damped spring:
    // critically-damped exponential tracking with frame-rate-correct factor.
    let rawMouse = u.zoom_config.yz;
    if (global_id.x == 0u && global_id.y == 0u) {
        var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        // Cold start: a zeroed buffer snaps to the live cursor immediately.
        if (sm.x == 0.0 && sm.y == 0.0) {
            sm = rawMouse;
        }
        let dt = 0.016;
        let springRate = 7.0;                          // defect core stiffness
        let k = 1.0 - exp(-springRate * dt);           // damping-corrected step
        sm = sm + (rawMouse - sm) * k;
        extraBuffer[133] = sm.x;
        extraBuffer[134] = sm.y;
    }
    let mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    let isMouseDown = u.zoom_config.w > 0.5;
    let distToMouse = length(uv - mousePos);
    let mouseGravity = 1.0 - smoothstep(0.0, 0.3, distToMouse);
    let clickPulse = select(0.0, 1.0, isMouseDown) * exp(-distToMouse * 5.0);

    // ── Honest audio bands ──────────────────────────────────────────────────
    let bass = plasmaBuffer[0].x;    // low end -> cell compression
    let mids = plasmaBuffer[0].y;    // mids    -> twist oscillation
    let treble = plasmaBuffer[0].z;  // treble  -> Schlieren sparkle grain

    // Director field (defect core follows the spring-damped mouse)
    let director = directorField(uv, time, mousePos);

    // Click voltage fronts: propagating pulses that flip the director locally
    let voltageFront = clickVoltagePulse(uv, time);

    // ── Frederiks transition: effective thickness varies with voltage ───────
    // Bass compresses the cell around the Frederiks threshold: below threshold
    // the director barely responds, above it compression kicks in hard.
    let frederiksThreshold = 0.35;
    let bassKick = smoothstep(frederiksThreshold, frederiksThreshold + 0.3, bass);
    let effectiveVoltage = voltage + mouseGravity * 0.3 + clickPulse * 0.5
                         + voltageFront * 0.6 + bassKick * 0.45;
    let effectiveThickness = cellThickness * (1.0 - effectiveVoltage * 0.7);

    // Phase retardation for RGB (different wavelengths)
    let wavelengthR = 650.0;
    let wavelengthG = 530.0;
    let wavelengthB = 460.0;

    // Spectral fringe: 8 FFT bins bend the retardation into radial band rings
    let fringe = spectralFringe(uv, mousePos, time);

    let localBirefringence = birefringence * (1.0 + mouseGravity);
    let retardation = vec3<f32>(
        phaseRetardation(effectiveThickness, localBirefringence, wavelengthR * 0.001) + fringe,
        phaseRetardation(effectiveThickness, localBirefringence, wavelengthG * 0.001) + fringe * 1.15,
        phaseRetardation(effectiveThickness, localBirefringence, wavelengthB * 0.001) + fringe * 1.3
    );

    // ── Twist angle varies across cell ──────────────────────────────────────
    // Mids drive the twist oscillation (was fake mouse-down "audio").
    let midsWobble = mids * sin(time * 5.0 + uv.y * 10.0) * 1.6;
    let localTwist = twistAngle * uv.x + midsWobble
                   + mouseGravity * 2.0 + clickPulse * 3.0
                   + voltageFront * PI * 0.5; // director flip behind the front

    // Sample background
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Apply polarization effect
    var color = rotatePolarization(bg, localTwist, retardation);

    // Add birefringence interference colors
    let interference = birefringenceColor(retardation.g + time * 0.5);
    color = mix(color, interference, 0.3 * (1.0 - voltage * 0.5));

    // Schlieren texture overlay, with treble-driven sparkle grain
    let schlieren = length(schlierenTexture(uv, time));
    let sparkle = sparkleGrain(uv, time) * treble;
    color += vec3<f32>(0.1, 0.15, 0.2) * schlieren * (0.5 + sparkle * 0.9);
    color += vec3<f32>(sparkle * 0.08); // fine treble glitter across the cell

    // ── Structure 1: crossed-polarizer analyzer ─────────────────────────────
    // The emergent plane of polarization is the director orientation carried
    // through the twist; the analyzer axis is fixed until the pointer is held,
    // when it rotates toward the cursor and sweeps the extinction brushes.
    let directorAngle = atan2(director.y, director.x);
    let emergentAngle = directorAngle + localTwist * 0.5;
    let toCursor = uv - mousePos;
    let heldAnalyzer = atan2(toCursor.y, toCursor.x);
    let analyzerAngle = mix(PI * 0.5, heldAnalyzer,
                            select(0.0, 1.0, isMouseDown) * (1.0 - smoothstep(0.0, 0.6, distToMouse)));
    let transmission = malusTransmission(emergentAngle, analyzerAngle, retardation);
    color *= 0.35 + transmission * 0.9;

    // Alpha based on polarization rotation amount
    let rotationAmount = abs(sin(localTwist)) * (1.0 + birefringence);
    let finalAlpha = rotationAmount * 0.7 + 0.3;

    // ── Structure 2: Frederiks relaxation lag (exact load from C) ───────────
    // Rise time shortens with drive voltage; decay is slow and voltage-blind.
    let prev = textureLoad(dataTextureC, coord, 0);
    let rising = step(dot(prev.rgb, vec3<f32>(1.0)), dot(color, vec3<f32>(1.0)));
    let riseRate = 0.45 + effectiveVoltage * 0.45;   // volts speed the switch on
    let decayRate = 0.16;                            // relaxation back is slow
    let rate = mix(decayRate, riseRate, rising);
    color = mix(prev.rgb, color, clamp(rate, 0.05, 1.0));

    color = acesFilm(color);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    let outColor = vec4<f32>(color * vignette, finalAlpha * vignette);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: scene geometry preserved (was clobbered by finalAlpha), thinned
    // slightly where the cell compresses under voltage.
    let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(sceneDepth * (1.0 - effectiveThickness * 0.05), 0.0, 1.0),
                           0.0, 0.0, 1.0));
}
