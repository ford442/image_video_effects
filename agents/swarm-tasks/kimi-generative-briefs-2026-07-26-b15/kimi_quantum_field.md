# Swarm Brief: kimi_quantum_field

**Role:** Algorithmist
**Name:** Kimi Quantum Field
**Category:** generative
**Description:** Wave interference patterns with uncertainty visualization and probability densities.
**Current lines:** 184
**Target lines:** 234–274 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This wave-packet interferometer has a double tonemap and dead code - clean the signal path, then make the spectrum a real interferometer:
- FIX THE DOUBLE TONEMAP (priority 1): the shader applies Reinhard `col/(1+col)` + pow(0.95), THEN `acesToneMap(col*1.1)` - stacked curves over-darken the mids. Remove the Reinhard/pow line and keep the ACES call. Also delete the dead `psi()` helper (defined, never called).
- Spectrum interferometer: drive individual wave-source amplitudes from per-bin `plasmaBuffer[1..k]` reads (source i reads bin i+1) so the interference pattern is a literal audio interferogram; mids -> phase hue via an IQ cosine palette, treble -> antinode bloom gain.
- Honest sliders (preset contract): the JSON names are mislabeled vs. code (Intensity=waveCount, Speed=coherence, Scale=uncertainty, Detail=decayRate) and CANNOT be renamed (saved-preset contract). Keep the JSON exactly as-is; in the WGSL make each slider's effect match its label as closely as possible WITHOUT changing defaults' visual output (e.g. let 'Speed' also drive packet phase velocity, 'Scale' also drive field zoom).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the |psi|^2 probability accumulation loop and the `alpha = probability + nodes*0.3 + collapsed*mouseDown` semantics VERBATIM - alpha-as-probability is the shader's identity. When fixing the tonemap, remove ONLY the Reinhard line, not the ACES call.

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

## JSON Parameters / Controls

```json
{
  "id": "kimi-quantum-field",
  "name": "Kimi Quantum Field",
  "url": "shaders/kimi_quantum_field.wgsl",
  "description": "Wave interference patterns with uncertainty visualization and probability densities.",
  "features": [
    "mouse-driven",
    "generative",
    "waves",
    "interference",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "procedural",
    "generative"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Kimi Quantum Field
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-06
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

// Kimi Quantum Field - Wave interference patterns with uncertainty visualization

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Wave function
fn psi(x: f32, y: f32, t: f32, k: f32, w: f32, sx: f32, sy: f32) -> f32 {
    var envelope = exp(-(x * x / (2.0 * sx * sx) + y * y / (2.0 * sy * sy)));
    var wave = cos(k * x - w * t);
    return envelope * wave;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity: bass energizes wave packets, mids shift hue, treble lights nodes
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse position
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Aspect correct
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    // Mouse in world space
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;
    
    // Parameters
    let waveCount = i32(u.zoom_params.x * 8.0) + 3;
    let coherence = u.zoom_params.y;
    let uncertainty = u.zoom_params.z * 0.5 * (1.0 + bass * 0.4);
    let decayRate = (u.zoom_params.w * 2.0 + 0.5) * (1.0 + bass * 0.3);
    
    // Multi-source interference
    var amplitude = 0.0;
    var probability = 0.0;
    
    // Central source at mouse
    for (var i = 0; i < waveCount; i++) {
        let fi = f32(i);
        
        // Wave packet properties
        let k = 10.0 + fi * 5.0;
        let w = 2.0 + fi;
        let phase = fi * 0.7;
        
        // Uncertainty in position (Gaussian spread)
        let spread = 0.1 + uncertainty * (0.5 + 0.5 * sin(time * decayRate + fi));
        
        // Wave source with slight offset for interference
        let offset = vec2<f32>(
            cos(fi * 2.094) * 0.1 * coherence,
            sin(fi * 2.094) * 0.1 * coherence
        );
        let source = mousePos + offset;
        
        // Distance from source
        let diff = p - source;
        let dist = length(diff);
        let angle = atan2(diff.y, diff.x);
        
        // Radial wave with angular modulation
        let radial = sin(k * dist - w * time + phase);
        let angular = cos(angle * 3.0 + fi);
        
        // Wave packet envelope
        var envelope = exp(-dist * dist / (2.0 * spread * spread));
        
        // Add to total amplitude
        var wave = radial * angular * envelope;
        amplitude += wave;
        
        // Probability density (|ψ|²)
        probability += wave * wave;
    }
    
    // Normalize
    amplitude /= f32(waveCount);
    probability /= f32(waveCount);
    
    // Phase visualization
    let phaseColor = 0.5 + 0.5 * sin(amplitude * 10.0 + time);
    
    // Quantum color palette
    let lowEnergy = vec3<f32>(0.1, 0.0, 0.3);   // Deep purple
    let midEnergy = vec3<f32>(0.0, 0.5, 0.8);   // Cyan
    let highEnergy = vec3<f32>(0.9, 0.9, 1.0);  // White
    
    var col = mix(lowEnergy, midEnergy, smoothstep(0.0, 0.5, probability));
    col = mix(col, highEnergy, smoothstep(0.5, 1.0, probability));
    
    // Add phase-based hue shift (mids widen the chromatic swing)
    col += vec3<f32>(0.3, 0.0, -0.3) * phaseColor * (0.5 + mids * 0.5);
    
    // Uncertainty visualization (blur at edges)
    let edgeDist = 1.0 - length(p);
    let uncertaintyGlow = smoothstep(0.0, 0.3, edgeDist) * uncertainty;
    col += vec3<f32>(1.0, 0.3, 0.6) * uncertaintyGlow * 0.3;
    
    // Constructive interference nodes (treble brightens the antinodes)
    let nodes = pow(probability, 3.0) * 2.0 * (1.0 + treble * 1.2);
    col += vec3<f32>(0.8, 1.0, 0.9) * nodes;
    
    // Particle measurement (collapse visualization)
    let measureProb = hash(uv + vec2<f32>(time * 0.1));
    let collapsed = select(0.0, 1.0, measureProb < probability * 0.1);
    col += vec3<f32>(1.0, 0.9, 0.7) * collapsed * mouseDown;
    
    // Vignette
    let vignette = 1.0 - length(p) * 0.3;
    col *= vignette;
    
    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.95));

    // Alpha encodes probability density (|ψ|²) + collapse flashes, never flat 1.0
    let alpha = clamp(probability + nodes * 0.3 + collapsed * mouseDown, 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    // Depth: denser probability regions read as nearer
    let depth = clamp(probability * 1.5, 0.0, 1.0);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
```
