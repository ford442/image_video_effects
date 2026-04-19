// ═══════════════════════════════════════════════════════════════════
//  liquid-magnetic-ferro-em
//  Category: advanced-hybrid
//  Features: ferrofluid-simulation, em-field-coupling, mouse-driven, temporal
//  Complexity: Very High
//  Chunks From: liquid_magnetic_ferro (Rosensweig spikes, metallic color), alpha-em-field-simulation (wave propagation, charge injection)
//  Created: 2026-04-18
//  By: Agent CB-6 — Alpha & Post-Process Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Ferrofluid with Electromagnetic Wave Coupling
//  Combines ferrofluid spike formation with propagating electromagnetic
//  waves. The magnetic field that drives Rosensweig instability is
//  augmented by time-varying EM dipole radiation, creating rippling
//  fluid peaks that respond to both mouse position and wave physics.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// ═══ CHUNK: hash12 (from alpha-em-field-simulation.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ CHUNK: magnetic dipole (from liquid_magnetic_ferro.wgsl) ═══
fn magneticField(p: vec2<f32>, dipolePos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = p - dipolePos;
    let dist2 = dot(d, d);
    let dist = sqrt(dist2);
    let magnitude = strength / (dist2 * dist + 0.001);
    return vec2<f32>(d.x * magnitude, -d.y * magnitude * 0.5);
}

fn multiMagneticField(p: vec2<f32>, time: f32, mousePos: vec2<f32>, numDipoles: i32) -> vec2<f32> {
    var field = vec2<f32>(0.0);
    field += magneticField(p, mousePos, 2.0);
    for (var i: i32 = 0; i < numDipoles; i = i + 1) {
        let fi = f32(i);
        let angle = time * 0.5 + fi * (2.0 * PI / f32(numDipoles));
        let radius = 0.3 + sin(time * 0.3 + fi) * 0.1;
        let dipolePos = vec2<f32>(0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius);
        field += magneticField(p, dipolePos, 0.8);
    }
    return field;
}

// ═══ CHUNK: Rosensweig spikes (from liquid_magnetic_ferro.wgsl) ═══
fn ferrofluidSpikes(p: vec2<f32>, field: vec2<f32>, time: f32) -> f32 {
    let fieldStrength = length(field);
    let fieldDir = normalize(field);
    let perp = vec2<f32>(-fieldDir.y, fieldDir.x);
    let alignment = dot(normalize(p - 0.5), perp);
    let pattern = sin(alignment * 20.0 + time) * cos(fieldStrength * 10.0);
    let spikes = pow(abs(pattern), 0.3) * sign(pattern);
    return spikes * fieldStrength;
}

fn metallicColor(normal: vec2<f32>, lightDir: vec2<f32>, viewDir: vec2<f32>, baseColor: vec3<f32>, emTint: vec3<f32>) -> vec3<f32> {
    let fresnel = pow(1.0 - abs(dot(normal, viewDir)), 3.0);
    let halfDir = normalize(lightDir + viewDir);
    let specAngle = max(dot(normal, halfDir), 0.0);
    let specular = pow(specAngle, 64.0);
    let shift = dot(normal, lightDir) * 0.5 + 0.5;
    let irid = vec3<f32>(
        sin(shift * PI) * 0.5 + 0.5,
        sin(shift * PI + 2.0) * 0.5 + 0.5,
        sin(shift * PI + 4.0) * 0.5 + 0.5
    );
    return baseColor * (0.3 + fresnel * 0.7) + specular * mix(irid, emTint, 0.4) * 0.8;
}

fn toneMap(x: vec3<f32>) -> vec3<f32> {
    return x / (1.0 + x);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let fieldStrength = 0.5 + u.zoom_params.x;
    let spikeSharpness = u.zoom_params.y * 2.0 + 0.5;
    let emCoupling = u.zoom_params.z;
    let numDipoles = i32(u.zoom_params.w * 4.0) + 2;

    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;

    // ═══ CHUNK: EM wave field (from alpha-em-field-simulation.wgsl, adapted) ═══
    // Simulated propagating wave from dipole sources
    var emField = vec2<f32>(0.0);
    var emPotential = 0.0;
    var charge = 0.0;

    // Mouse dipole with wave propagation
    let mouseDist = length(uv - mousePos);
    let wavePhase = mouseDist * 20.0 - time * 4.0;
    let waveAmplitude = exp(-mouseDist * 3.0) * (0.5 + audioPulse);
    emField += vec2<f32>(cos(wavePhase), sin(wavePhase)) * waveAmplitude;
    emPotential += sin(wavePhase) * waveAmplitude * 0.5;

    // Ripple charges inject EM pulses
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.15) {
            let rPhase = rDist * 30.0 - age * 10.0;
            let rAmp = smoothstep(0.15, 0.0, rDist) * max(0.0, 1.0 - age);
            let sign = select(-1.0, 1.0, f32(i) % 2.0 < 1.0);
            emField += vec2<f32>(cos(rPhase), sin(rPhase)) * rAmp * sign * 2.0;
            charge += rAmp * sign * 0.5;
        }
    }

    // Background noise field
    let noiseVal = fbm2(uv * 4.0 + time * 0.05, 4);

    // Combine static magnetic field with EM wave
    var field = multiMagneticField(uv, time, mousePos, numDipoles);
    field *= fieldStrength * (1.0 + audioPulse);

    // Couple EM wave into magnetic field
    field += emField * emCoupling * 3.0;

    // Ferrofluid surface
    let spikes = ferrofluidSpikes(uv, field, time);
    let fluidBase = smoothstep(0.3, 0.7, length(field));
    let height = fluidBase + spikes * spikeSharpness * 0.3;

    // Normal from field gradient
    let delta = 0.01;
    let fieldR = multiMagneticField(uv + vec2<f32>(delta, 0.0), time, mousePos, numDipoles) + emField * emCoupling * 3.0;
    let fieldU = multiMagneticField(uv + vec2<f32>(0.0, delta), time, mousePos, numDipoles) + emField * emCoupling * 3.0;
    let normal = normalize(vec2<f32>(
        length(field) - length(fieldR),
        length(field) - length(fieldU)
    ));

    // EM-based color tint
    let eStrength = length(emField);
    let eDir = atan2(emField.y, emField.x) / (2.0 * PI) + 0.5;
    var emTint = vec3<f32>(0.0);
    if (eStrength > 0.01) {
        let hue = eDir;
        let sat = min(eStrength * 2.0, 1.0);
        let val = min(eStrength * 3.0 + 0.1, 1.0);
        let h6 = hue * 6.0;
        let c = val * sat;
        let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
        let m = val - c;
        if (h6 < 1.0) { emTint = vec3(c, x, 0.0); }
        else if (h6 < 2.0) { emTint = vec3(x, c, 0.0); }
        else if (h6 < 3.0) { emTint = vec3(0.0, c, x); }
        else if (h6 < 4.0) { emTint = vec3(0.0, x, c); }
        else if (h6 < 5.0) { emTint = vec3(x, 0.0, c); }
        else { emTint = vec3(c, 0.0, x); }
        emTint = emTint + vec3(m);
    }

    // Charge visualization
    let chargeVis = charge * emCoupling;
    emTint.r += max(0.0, chargeVis) * 0.5;
    emTint.b += max(0.0, -chargeVis) * 0.5;
    emTint = clamp(emTint, vec3<f32>(0.0), vec3<f32>(1.0));

    // Metallic coloring with EM tint
    let lightDir = normalize(vec2<f32>(cos(time * 0.5), sin(time * 0.5)));
    let viewDir = normalize(uv - 0.5);
    let baseColor = vec3<f32>(0.1, 0.15, 0.25);
    var color = metallicColor(normal, lightDir, viewDir, baseColor, emTint);

    // Highlight peaks
    color += vec3<f32>(1.0, 0.9, 0.7) * max(spikes, 0.0) * 0.5;

    // Field line visualization
    let fieldDir = normalize(field);
    let linePattern = abs(sin(atan2(fieldDir.y, fieldDir.x) * 10.0 + time));
    color += mix(vec3<f32>(0.2, 0.4, 0.8), emTint, 0.5) * smoothstep(0.8, 1.0, linePattern) * 0.3;

    // EM potential brightness variation
    color *= 1.0 + emPotential * emCoupling * 0.5;
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    color = toneMap(color * 2.0);
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    color *= vignette;

    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(height, 0.0, 0.0, 1.0));

    // Store EM state for potential feedback
    textureStore(dataTextureA, coord, vec4<f32>(emField, emPotential, charge));
}
