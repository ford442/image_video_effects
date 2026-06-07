# Agent 2A: Shader Surgeon / Chunk Librarian
## Task Specification - Phase A, Agent 2

**Role:** Code Reuse & Hybrid Creator  
**Priority:** HIGH  
**Target:** Extract reusable chunks, create 10 hybrid shaders  
**Estimated Duration:** 4-5 days

---

## Mission

1. Analyze existing shaders to identify reusable code chunks
2. Create a "chunk library" of common WGSL functions
3. Build new hybrid shaders by combining chunks from different sources

---

## Phase 1: Chunk Extraction

Analyze these shader categories and extract reusable functions:

### Noise Functions (from generative shaders)
Target files:
- `gen_grok4_perlin.wgsl`
- `stellar-plasma.wgsl`
- `gen_grid.wgsl`
- Any shader with `fbm`, `hash`, `noise` functions

Extract:
```wgsl
// Hash functions
fn hash12(p: vec2<f32>) -> f32
fn hash13(p: vec3<f32>) -> f32
fn hash21(p: vec2<f32>) -> vec2<f32>

// Noise functions
fn valueNoise(p: vec2<f32>) -> f32
fn perlinNoise(p: vec2<f32>) -> f32
fn simplexNoise(p: vec2<f32>) -> f32

// FBM variants
fn fbm2(p: vec2<f32>, octaves: i32) -> f32
fn fbm3(p: vec3<f32>, octaves: i32) -> f32
fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32>
```

### Color Utilities (from artistic/lighting shaders)
Target files:
- `liquid-metal.wgsl`
- `chromatic-*.wgsl`
- `rgb-*.wgsl`

Extract:
```wgsl
// Conversions
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32>
fn rgb2hsl(c: vec3<f32>) -> vec3<f32>
fn srgbToLinear(c: vec3<f32>) -> vec3<f32>
fn linearToSrgb(c: vec3<f32>) -> vec3<f32>

// Palettes
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32>
fn hueShift(col: vec3<f32>, shift: f32) -> vec3<f32>
fn saturate(col: vec3<f32>, amount: f32) -> vec3<f32>

// Effects
fn chromaticAberration(uv: vec2<f32>, strength: f32) -> vec3<f32>
fn vignette(uv: vec2<f32>, intensity: f32) -> f32
fn tonemapACES(color: vec3<f32>) -> vec3<f32>
```

### UV Transformations (from geometric shaders)
Target files:
- `kaleidoscope.wgsl`
- `julia-warp.wgsl`
- `hyperbolic-dreamweaver.wgsl`
- `poincare-tile.wgsl`

Extract:
```wgsl
// 2D transforms
fn rot2(a: f32) -> mat2x2<f32>
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32>
fn polarToCartesian(uv: vec2<f32>) -> vec2<f32>
fn cartesianToPolar(uv: vec2<f32>) -> vec2<f32>

// Warping
fn juliaWarp(uv: vec2<f32>, c: vec2<f32>) -> vec2<f32>
fn mobiusTransform(uv: vec2<f32>, params: vec4<f32>) -> vec2<f32>
fn hyperbolicTiling(uv: vec2<f32>, iterations: i32) -> vec2<f32>
fn pinch(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec2<f32>
```

### SDF Primitives (from raymarched shaders)
Target files:
- `gen-xeno-botanical-synth-flora.wgsl`
- `crystal-*.wgsl`
- Any shader with `sd` prefix functions

Extract:
```wgsl
// Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32
fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32
fn sdCappedCone(p: vec3<f32>, c: vec3<f32>) -> f32
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32

// Operations
fn sdUnion(a: f32, b: f32) -> f32
fn sdSubtract(a: f32, b: f32) -> f32
fn sdIntersect(a: f32, b: f32) -> f32
fn sdSmoothUnion(a: f32, b: f32, k: f32) -> f32

// Utils
fn sdCalcNormal(p: vec3<f32>, sdf: fn(vec3<f32>) -> f32) -> vec3<f32>
```

### Lighting Effects (from lighting-effects)
Target files:
- `anamorphic-flare.wgsl`
- `lens-flare-brush.wgsl`
- `neon-*.wgsl`

Extract:
```wgsl
fn specularHighlight(viewDir: vec3<f32>, lightDir: vec3<f32>, normal: vec3<f32>, power: f32) -> f32
fn fresnel(viewDir: vec3<f32>, normal: vec3<f32>, power: f32) -> f32
fn glow(dist: f32, radius: f32, intensity: f32) -> f32
fn lightBloom(uv: vec2<f32>, lightPos: vec2<f32>, color: vec3<f32>) -> vec3<f32>
```

---

## Phase 2: Hybrid Shader Creation

Create 10 new hybrid shaders by combining chunks:

### Hybrid 1: `hybrid-noise-kaleidoscope`
**Chunks:** FBM noise + Kaleidoscope mirror + Chromatic aberration
```
Concept: Domain-warped noise fed through kaleidoscope symmetry with RGB splits
Chunks From:
- fbm() from stellar-plasma
- kaleidoscope() from kaleidoscope
- chromaticAberration() from chromatic-*
```

### Hybrid 2: `hybrid-sdf-plasma`
**Chunks:** SDF sphere + Domain warping + Plasma coloring
```
Concept: Raymarched SDF scene with plasma noise displacement
Chunks From:
- sdSphere/sdSmoothUnion from gen-xeno-botanical
- domainWarp() from stellar-plasma
- palette() color cycling
```

### Hybrid 3: `hybrid-chromatic-liquid`
**Chunks:** Liquid displacement + RGB split + Noise flow
```
Concept: Fluid-like distortion with chromatic separation flowing along noise field
Chunks From:
- Liquid displacement logic from liquid-jelly
- chromaticAberration() from chromatic shaders
- Flow field from luma-flow-field
```

### Hybrid 4: `hybrid-cyber-organic`
**Chunks:** Circuit patterns + Organic growth + Neon edges
```
Concept: Digital circuit traces that grow organically with neon glow
Chunks From:
- Hex/circuit patterns from hex-circuit
- Growth patterns from digital-moss
- Neon glow from neon-edge-diffusion
```

### Hybrid 5: `hybrid-voronoi-glass`
**Chunks:** Voronoi cells + Glass refraction + Chromatic dispersion
```
Concept: Voronoi diagram as glass blocks with light dispersion
Chunks From:
- Voronoi calculation from voronoi-glass
- Refraction from glass_refraction_alpha
- Dispersion from chromatic-manifold
```

### Hybrid 6: `hybrid-fractal-feedback`
**Chunks:** Fractal math + Temporal feedback + RGB delay
```
Concept: Julia/Mandelbrot set with feedback trails and RGB channel delay
Chunks From:
- Julia set from gen_julia_set or gen_grok41_mandelbrot
- Feedback buffer usage from temporal-echo
- RGB delay from rgb-delay-brush
```

### Hybrid 7: `hybrid-magnetic-field`
**Chunks:** Vector field + Particle trails + Magnetic distortion
```
Concept: Visualize magnetic field lines with flowing particles
Chunks From:
- Magnetic field from magnetic-field
- Trails from gen_trails
- Distortion from magnetic-edge
```

### Hybrid 8: `hybrid-particle-fluid`
**Chunks:** Particle system + Fluid simulation + Glow
```
Concept: Particles that move like fluid with glowing trails
Chunks From:
- Particle logic from particle-swarm
- Fluid advection from navier-stokes-dye
- Glow from neon-pulse
```

### Hybrid 9: `hybrid-reaction-diffusion-glass`
**Chunks:** Reaction-diffusion + Glass distortion + Depth awareness
```
Concept: Turing patterns refracted through depth-aware glass
Chunks From:
- Gray-Scott equations from reaction-diffusion
- Glass distortion from frosted-glass-lens
- Depth sampling from depth-aware shaders
```

### Hybrid 10: `hybrid-spectral-sorting`
**Chunks:** Pixel sorting + Spectral analysis + Audio reactivity
```
Concept: Audio-reactive pixel sorting with frequency-based color shifts
Chunks From:
- Bitonic sort from bitonic-sort
- Spectral analysis from spectrogram-displace
- Audio input handling from audio_* shaders
```

---

## Output Requirements

### 1. Chunk Library Document
Create `swarm-outputs/chunk-library.md` with:
- Categorized list of all extracted functions
- Source shader for each chunk
- Compatibility notes
- Usage examples

### 2. Hybrid Shader Files
For each hybrid, create:
1. **WGSL file** at `public/shaders/{hybrid-id}.wgsl`
2. **JSON definition** at appropriate `shader_definitions/{category}/{hybrid-id}.json`
3. **Documentation** explaining which chunks were combined

### 3. Hybrid Template

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {HYBRID_NAME}
//  Category: {CATEGORY}
//  Features: hybrid, {feature-list}
//  Chunks From: {source-shader-1}, {source-shader-2}, ...
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════

// --- STANDARD HEADER ---
[13 bindings + Uniforms struct]

// ═══ CHUNK 1: {Name} (from {source}) ═══
[Function code with attribution comment]

// ═══ CHUNK 2: {Name} (from {source}) ═══
[Function code with attribution comment]

// ═══ CHUNK 3: {Name} (from {source}) ═══
[Function code with attribution comment]

// ═══ HYBRID LOGIC ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // Parameter extraction (randomization-safe)
    let param1 = u.zoom_params.x; // Chunk 1 intensity
    let param2 = u.zoom_params.y; // Chunk 2 intensity
    let param3 = u.zoom_params.z; // Blend factor
    let param4 = u.zoom_params.w; // Global modifier
    
    // Apply chunk 1
    // Apply chunk 2
    // Blend results using chunk 3 or custom logic
    // Calculate alpha properly (see Agent 1A patterns)
    // Write outputs
}
```

---

## Parameter Mapping Guidelines

Each hybrid shader should use zoom_params as:

| Param | Typical Use | Range |
|-------|-------------|-------|
| x | Primary effect intensity | 0.0 - 1.0 |
| y | Secondary effect intensity | 0.0 - 1.0 |
| z | Blend/mix factor | 0.0 - 1.0 |
| w | Global modifier (speed/scale) | 0.0 - 1.0 |

---

## Quality Criteria

- [ ] All chunks properly attributed in comments
- [ ] Chunk interfaces compatible (matching UV spaces, return types)
- [ ] No naming conflicts between chunks
- [ ] Proper alpha channel handling
- [ ] Randomization-safe parameters
- [ ] Visual result is greater than sum of parts (true hybrid)
- [ ] Runs at 60fps

---

## Deliverables Checklist

- [ ] `chunk-library.md` with 30+ categorized functions
- [ ] 10 hybrid shader WGSL files
- [ ] 10 hybrid JSON definitions
- [ ] Brief documentation for each hybrid explaining the combination
