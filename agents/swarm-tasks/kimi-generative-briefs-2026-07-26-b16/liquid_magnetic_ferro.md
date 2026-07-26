# Swarm Brief: liquid_magnetic_ferro

**Role:** Algorithmist
**Name:** Magnetic Ferrofluid
**Category:** generative
**Description:** Interactive ferrofluid simulation with magnetic field lines, Rosensweig instability spike formation, and metallic iridescent rendering
**Current lines:** 190
**Target lines:** 240–280 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This ferrofluid sim has a dead slider, mislabeled audio, and a NaN waiting at screen center - fix the physics honesty:
- WIRE THE DEAD VISCOSITY SLIDER (priority 1): zoom_params.z is read into `fluidViscosity` but never used. Make it real with temporal field smoothing: store the magnetic field magnitude to dataTextureA each frame and read back the previous field (dataTextureC), mixing `field = mix(prevField, field, mix(0.05, 0.95, 1.0 - viscosity))` so high viscosity = slow, molasses-like spike response. Keep the stored field raw (sim state - never tonemap the A write).
- Honest audio: `audioPulse = u.zoom_config.w` is mouse-DOWN, not audio. Rewire to bass (`plasmaBuffer[0].x`) modulating field strength and treble (`plasmaBuffer[0].z`) modulating spike frequency.
- Kill the NaNs: `normalize(uv - 0.5)` is normalize(0,0) at the exact screen-center pixel - add an epsilon guard (e.g. `normalize(uv - 0.5 + vec2<f32>(1e-4, 0.0))` or select-based safe normalize); same for `normalize(field)` where field ~ 0. Clamp the depth write to >= 0.0 (spike height can go negative via sign(pattern)).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the Rosensweig spike formula (`pow(abs(pattern), 0.3) * sign(pattern)`) and the dipole 1/r^3 falloff VERBATIM - they are the physics identity. dataTextureA becomes SIM STATE (raw field) with this upgrade - never clamp/tonemap it.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "liquid_magnetic_ferro",
  "name": "Magnetic Ferrofluid",
  "url": "shaders/liquid_magnetic_ferro.wgsl",
  "description": "Interactive ferrofluid simulation with magnetic field lines, Rosensweig instability spike formation, and metallic iridescent rendering",
  "tags": [
    "ferrofluid",
    "magnetic",
    "liquid",
    "interactive",
    "metallic"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "metallic",
    "magnetic-simulation"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Field Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Spike Sharpness",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Viscosity",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Num Dipoles",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.7,
  "updatedParams": [
    {
      "index": 0,
      "name": "Field Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 1,
      "name": "Spike Sharpness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 2,
      "name": "Viscosity",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 3,
      "name": "Num Dipoles",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════════════════
//  liquid_magnetic_ferro.wgsl - Magnetic Ferrofluid Simulation
//  
//  Agent: Interactivist + Algorithmist
//  Techniques:
//    - Magnetic field line simulation
//    - Ferrofluid spike formation (Rosensweig instability)
//    - Mouse-attracted fluid dynamics
//    - Audio-reactive field strength
//  
//  Target: 4.7★ rating
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

// Multiple magnetic sources
fn multiMagneticField(p: vec2<f32>, time: f32, mousePos: vec2<f32>, numDipoles: i32) -> vec2<f32> {
    var field = vec2<f32>(0.0);
    
    // Mouse-controlled dipole
    field += magneticField(p, mousePos, 2.0);
    
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

// Rosensweig instability - ferrofluid spike formation
fn ferrofluidSpikes(p: vec2<f32>, field: vec2<f32>, time: f32) -> f32 {
    let fieldStrength = length(field);
    let fieldDir = normalize(field);
    
    // Peaks form perpendicular to field lines
    let perp = vec2<f32>(-fieldDir.y, fieldDir.x);
    let alignment = dot(normalize(p - 0.5), perp);
    
    // Instability creates regular pattern
    let pattern = sin(alignment * 20.0 + time) * 
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
    let halfDir = normalize(lightDir + viewDir);
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
    return x / (1.0 + x);
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
    
    // Parameters
    let fieldStrength = 0.5 + u.zoom_params.x;         // 0.5-1.5
    let spikeSharpness = u.zoom_params.y * 2.0 + 0.5;  // 0.5-2.5
    let fluidViscosity = u.zoom_params.z;              // 0-1
    let numDipoles = i32(u.zoom_params.w * 4.0) + 2;   // 2-6
    
    // Mouse position (normalized)
    let mousePos = u.zoom_config.yz;
    
    // Audio reactivity
    let audioPulse = u.zoom_config.w;
    
    // Calculate magnetic field
    var field = multiMagneticField(uv, time, mousePos, numDipoles);
    field *= fieldStrength * (1.0 + audioPulse);
    
    // Ferrofluid surface
    let spikes = ferrofluidSpikes(uv, field, time);
    
    // Smooth fluid base
    let fluidBase = smoothstep(0.3, 0.7, length(field));
    
    // Combine
    let height = fluidBase + spikes * spikeSharpness * 0.3;
    
    // Normal from field gradient
    let delta = 0.01;
    let fieldR = multiMagneticField(uv + vec2<f32>(delta, 0.0), time, mousePos, numDipoles);
    let fieldU = multiMagneticField(uv + vec2<f32>(0.0, delta), time, mousePos, numDipoles);
    let normal = normalize(vec2<f32>(
        length(field) - length(fieldR),
        length(field) - length(fieldU)
    ));
    
    // Metallic coloring
    let lightDir = normalize(vec2<f32>(cos(time * 0.5), sin(time * 0.5)));
    let viewDir = normalize(uv - 0.5);
    let baseColor = vec3<f32>(0.1, 0.15, 0.25); // Dark metallic base
    
    var color = metallicColor(normal, lightDir, viewDir, baseColor);
    
    // Highlight peaks
    color += vec3<f32>(1.0, 0.9, 0.7) * max(spikes, 0.0) * 0.5;
    
    // Field line visualization
    let fieldDir = normalize(field);
    let linePattern = abs(sin(atan2(fieldDir.y, fieldDir.x) * 10.0 + time));
    color += vec3<f32>(0.2, 0.4, 0.8) * smoothstep(0.8, 1.0, linePattern) * 0.3;
    
    // Tone mapping
    color = toneMap(color * 2.0);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(height, 0.0, 0.0, 1.0));
}
```
