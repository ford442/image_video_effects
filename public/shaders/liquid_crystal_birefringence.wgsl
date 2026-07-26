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
//  Target: 4.7★ rating
//  Upgraded: 2026-07-26 (swarm Algorithmist b15)
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);

    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

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

    // Alpha based on polarization rotation amount
    let rotationAmount = abs(sin(localTwist)) * (1.0 + birefringence);
    let finalAlpha = rotationAmount * 0.7 + 0.3;

    // Tone mapping
    color = color / (1.0 + color * 0.3);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;

    textureStore(writeTexture, coord, vec4<f32>(color * vignette, finalAlpha * vignette));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));

    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
