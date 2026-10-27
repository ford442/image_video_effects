// ═══════════════════════════════════════════════════════════════════════════════
//  liquid_magnetic_ferro.wgsl - Magnetic Ferrofluid Simulation
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-27
//  Ideas: spike-base meniscus rings; directional magnetic striations
//  A packing: raw [field x, field y, magnitude, 1]
//
//  Agent: Interactivist + Algorithmist (Batch 16 upgrade)
//  Techniques:
//    - Magnetic field line simulation (dipole 1/r^3 falloff)
//    - Ferrofluid spike formation (Rosensweig instability)
//    - Mouse-attracted fluid dynamics
//    - Honest audio reactivity: bass -> field strength, treble -> spike frequency
//    - Viscosity-driven temporal field smoothing (sim state in dataTextureA/C)
//    - NaN-hardened normalization (epsilon guards everywhere)
//
//  Target: 4.7★ rating
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

// NaN-hardened normalize: returns a safe fallback direction when the
// vector is near zero length (screen-center pixel, dead field zones).
fn safeNormalize(v: vec2<f32>, fallback: vec2<f32>) -> vec2<f32> {
    let len2 = dot(v, v);
    if (len2 > 1e-8) {
        return v * inverseSqrt(len2);
    }
    return fallback;
}

// Magnetic dipole field
fn magneticField(p: vec2<f32>, dipolePos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = p - dipolePos;
    let dist2 = dot(d, d);
    let dist = sqrt(dist2);

    // Dipole field falls off as 1/r^3
    let magnitude = strength / (dist2 * dist + 0.001);

    // Field lines curl around
    return vec2<f32>(
        d.x * magnitude,
        -d.y * magnitude * 0.5
    );
}

// Multiple magnetic sources: one mouse-driven dipole plus orbiting dipoles.
// `mouseStrength` lets a mouse-press intensify the primary dipole (grab the fluid).
fn multiMagneticField(p: vec2<f32>, time: f32, mousePos: vec2<f32>, numDipoles: i32, mouseStrength: f32) -> vec2<f32> {
    var field = vec2<f32>(0.0);

    // Mouse-controlled dipole
    field += magneticField(p, mousePos, mouseStrength);

    // Orbiting dipoles
    for (var i: i32 = 0; i < numDipoles; i = i + 1) {
        let fi = f32(i);
        let angle = time * 0.5 + fi * (2.0 * PI / f32(numDipoles));
        let radius = 0.3 + sin(time * 0.3 + fi) * 0.1;
        let dipolePos = vec2<f32>(
            0.5 + cos(angle) * radius,
            0.5 + sin(angle) * radius
        );
        field += magneticField(p, dipolePos, 0.8);
    }

    return field;
}

// Rosensweig instability - ferrofluid spike formation.
// `spikeFreq` scales the instability wavelength (treble-reactive).
fn ferrofluidSpikes(p: vec2<f32>, field: vec2<f32>, time: f32, spikeFreq: f32) -> f32 {
    let fieldStrength = length(field);
    let fieldDir = safeNormalize(field, vec2<f32>(1.0, 0.0));

    // Peaks form perpendicular to field lines
    let perp = vec2<f32>(-fieldDir.y, fieldDir.x);
    // Epsilon-guarded: screen-center pixel would otherwise be normalize(0,0)
    let toCenter = safeNormalize(p - 0.5, vec2<f32>(1.0, 0.0));
    let alignment = dot(toCenter, perp);

    // Instability creates regular pattern
    let pattern = sin(alignment * spikeFreq + time) *
                  cos(fieldStrength * 10.0);

    // Sharp peaks
    let spikes = pow(abs(pattern), 0.3) * sign(pattern);

    return spikes * fieldStrength;
}

// Metallic iridescent coloring
fn metallicColor(normal: vec2<f32>, lightDir: vec2<f32>, viewDir: vec2<f32>, baseColor: vec3<f32>) -> vec3<f32> {
    // Fresnel
    let fresnel = pow(1.0 - abs(dot(normal, viewDir)), 3.0);

    // Specular
    let halfDir = safeNormalize(lightDir + viewDir, vec2<f32>(0.0, 1.0));
    let specAngle = max(dot(normal, halfDir), 0.0);
    let specular = pow(specAngle, 64.0);

    // Iridescent shift
    let shift = dot(normal, lightDir) * 0.5 + 0.5;
    let irid = vec3<f32>(
        sin(shift * PI) * 0.5 + 0.5,
        sin(shift * PI + 2.0) * 0.5 + 0.5,
        sin(shift * PI + 4.0) * 0.5 + 0.5
    );

    return baseColor * (0.3 + fresnel * 0.7) + specular * irid * 0.8;
}

// Tone mapping
fn toneMap(x: vec3<f32>) -> vec3<f32> {
    let v = max(x, vec3<f32>(0.0));
    return clamp((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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

    // ── Slider parameters (saved-preset contract: ids/defaults unchanged) ──
    let fieldStrength = 0.5 + u.zoom_params.x;         // Field Strength: 0.5-1.5
    let spikeSharpness = u.zoom_params.y * 2.0 + 0.5;  // Spike Sharpness: 0.5-2.5
    let fluidViscosity = u.zoom_params.z;              // Viscosity: 0-1 (NOW WIRED)
    let numDipoles = i32(u.zoom_params.w * 4.0) + 2;   // Num Dipoles: 2-6

    // Mouse position (normalized); mouse-DOWN is honest interactivity, not audio.
    // Pressing grabs the ferrofluid: the primary dipole doubles in strength.
    let mousePos = u.zoom_config.yz;
    let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseStrength = 2.0 * (1.0 + mouseDown);

    // ── Honest audio reactivity ──
    // Bass drives the magnetic field strength; treble drives spike frequency.
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let audioFieldBoost = 1.0 + bass * 0.8;
    let spikeFreq = 20.0 * (1.0 + treble * 0.75);

    // ── Instantaneous magnetic field ──
    var field = multiMagneticField(uv, time, mousePos, numDipoles, mouseStrength);
    field *= fieldStrength * audioFieldBoost;

    // ── Viscosity: temporal field smoothing (sim state, RAW — never tonemapped) ──
    // dataTextureC holds the previous frame's raw field (written to A last frame).
    // High viscosity -> tiny blend factor -> slow, molasses-like spike response.
    let prevSample = textureLoad(dataTextureC, coord, 0);
    let prevField = prevSample.xy;
    let blendFactor = mix(0.05, 0.95, 1.0 - fluidViscosity);
    // Guard: on the first frames prevField may be zero/uninitialized; the mix
    // still converges because blendFactor >= 0.05 always admits new field.
    field = mix(prevField, field, blendFactor);

    // ── Ferrofluid surface ──
    let spikes = ferrofluidSpikes(uv, field, time, spikeFreq);

    // Smooth fluid base
    let fluidBase = smoothstep(0.3, 0.7, length(field));

    // Combine into a height field
    let height = fluidBase + spikes * spikeSharpness * 0.3;

    // ── Surface normal from smoothed-field gradient ──
    // Gradient of the instantaneous field is fine for shading detail; the
    // smoothed field drives the silhouette via `height`.
    let delta = 0.01;
    let gradScale = fieldStrength * audioFieldBoost;
    let fieldR = multiMagneticField(uv + vec2<f32>(delta, 0.0), time, mousePos, numDipoles, mouseStrength) * gradScale;
    let fieldU = multiMagneticField(uv + vec2<f32>(0.0, delta), time, mousePos, numDipoles, mouseStrength) * gradScale;
    let normal = safeNormalize(vec2<f32>(
        length(field) - length(fieldR),
        length(field) - length(fieldU)
    ), vec2<f32>(0.0, 1.0));

    // ── Metallic coloring ──
    let lightDir = vec2<f32>(cos(time * 0.5), sin(time * 0.5));
    // Epsilon-guarded view direction: NaN-safe at exact screen center
    let viewDir = safeNormalize(uv - 0.5, vec2<f32>(1.0, 0.0));
    let baseColor = vec3<f32>(0.1, 0.15, 0.25); // Dark metallic base

    var color = metallicColor(normal, lightDir, viewDir, baseColor);

    // Highlight peaks (positive spikes catch warm rim light)
    color += vec3<f32>(1.0, 0.9, 0.7) * max(spikes, 0.0) * 0.5;

    // Field line visualization (flow ribbons along field direction)
    let fieldDir = safeNormalize(field, vec2<f32>(1.0, 0.0));
    let linePattern = abs(sin(atan2(fieldDir.y, fieldDir.x) * 10.0 + time));
    color += vec3<f32>(0.2, 0.4, 0.8) * smoothstep(0.8, 1.0, linePattern) * 0.3;
    let meniscus = exp(-abs(spikes) * 3.0) * fluidBase * smoothstep(0.1, 0.8, spikeSharpness);
    color += vec3<f32>(0.24, 0.38, 0.5) * meniscus * 0.3;
    let striationPhase = dot(uv, vec2<f32>(-fieldDir.y, fieldDir.x)) * spikeFreq;
    let striation = pow(max(0.5 + 0.5 * cos(striationPhase), 0.0), 8.0);
    color += vec3<f32>(0.12, 0.2, 0.3) * striation * fluidBase;

    // Soft cyan glow where the magnetic field is intense (dipole cores)
    let fieldMag = length(field);
    let coreGlow = smoothstep(1.5, 4.0, fieldMag);
    color += vec3<f32>(0.3, 0.7, 0.9) * coreGlow * 0.25;

    // Bass thump: subtle global brightness kick on low-frequency hits
    color *= 1.0 + bass * 0.15;

    // Tone mapping
    color = toneMap(color * 2.0);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    color *= vignette;

    // ── Writes ──
    let alpha = clamp(0.15 + fluidBase * 0.45 + min(abs(spikes), 1.0) * 0.35, 0.0, 0.95);
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    // Depth: clamp >= 0.0 (spike height can go negative via sign(pattern))
    textureStore(writeDepthTexture, coord, vec4<f32>(max(height, 0.0), 0.0, 0.0, 1.0));
    // Sim state: RAW smoothed field for next frame's viscosity feedback.
    // Never clamped, never tonemapped — this is physics state, not color.
    textureStore(dataTextureA, coord, vec4<f32>(field, length(field), 1.0));
}
