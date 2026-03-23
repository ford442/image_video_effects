# Agent 4A: Generative Shader Creator
## Task Specification - Phase A, Agent 4

**Role:** Procedural Effect Generator  
**Priority:** MEDIUM  
**Target:** Create 13 new generative shaders (10 base + 3 temporal/motion)  
**Estimated Duration:** 5-6 days

---

## Mission

Create 10 entirely new generative shaders that don't require input images. These should be audio-reactive or time-driven, and work as standalone visuals.

---

## What is a Generative Shader?

Generative shaders create visuals procedurally without sampling from `readTexture`. They produce output based on:
- Time (`u.config.x`)
- UV coordinates
- Mathematical functions
- Noise algorithms
- Physics simulations

### Key Characteristics
- Category: `"generative"`
- Can ignore `readTexture` samples
- Must still declare all 13 bindings (for pipeline compatibility)
- Should write constant or procedural value to `writeDepthTexture`

### Minimal Example
```wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / res;
    let t = u.config.x;
    
    // Procedural color (no texture sample!)
    let color = vec3<f32>(0.5 + 0.5 * sin(uv.x * 10.0 + t), 0.0, 0.0);
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0)); // Flat depth
}
```

---

## New Shader Concepts

### 1. `gen-neural-fractal`
**Concept:** Neural network weight visualization style fractals  
**Mathematical Basis:** Mandelbrot/Julia variations with neural-inspired activation functions

```
Visual: Layered neural network weights visualized as colored fractal patterns
Colors: Gradient from deep blues to electric purples to hot pinks
Motion: Slow zoom and rotation revealing deeper structure
Params:
  - x: Zoom level (0.1x to 10x)
  - y: Color cycling speed
  - z: Iteration depth (10 to 100 iterations)
  - w: Mutation factor (adds noise to iteration)
```

**Implementation Notes:**
- Use `tanh()` or `sigmoid()` instead of standard z = z² + c
- Domain warping for organic feel
- Multi-layer composition

---

### 2. `gen-voronoi-crystal`
**Concept:** Animated crystal growth using Voronoi diagrams  
**Mathematical Basis:** Voronoi tessellation with time-evolving seed points

```
Visual: Crystal facets growing and merging like frost on glass
Colors: Icy blues, whites, occasional rainbow iridescence
Motion: Seeds move slowly, cells grow, merge, split
Params:
  - x: Growth speed
  - y: Number of crystals (2 to 20)
  - z: Irregularity (perfect hex to chaotic)
  - w: Glow intensity
```

**Implementation Notes:**
- 2D Voronoi with distance to nearest seed
- Seeds move along smooth random paths
- Edge detection for "facets"
- Depth simulation based on cell age

---

### 3. `gen-audio-spirograph`
**Concept:** Audio-reactive spirograph with harmonic resonance  
**Mathematical Basis:** Epitrochoid curves with audio-driven parameters

```
Visual: Lissajous-like patterns with glowing trails
Colors: Cycling rainbow with audio-reactive saturation
Motion: Continuous drawing with fade trails
Params:
  - x: Base frequency ratio
  - y: Audio reactivity amount
  - z: Trail length
  - w: Line thickness
```

**Implementation Notes:**
- Use `u.config.y` (or appropriate field) for audio input
- Accumulate trails in feedback buffer
- Frequency ratios based on musical intervals (3:2, 4:3, etc.)

---

### 4. `gen-topology-flow`
**Concept:** Topological surface flow with Morse theory inspiration  
**Mathematical Basis:** Gradient flow on height field, critical point detection

```
Visual: Flow lines converging/diverging at saddle points
Colors: Height-based coloring (valleys blue, peaks red)
Motion: Particles flowing along gradient lines
Params:
  - x: Flow speed
  - y: Height field complexity
  - z: Particle density
  - w: Trail persistence
```

**Implementation Notes:**
- Generate height field with FBM
- Calculate gradient for flow direction
- Simulate particles advected by flow
- Detect critical points (where gradient ≈ 0)

---

### 5. `gen-string-theory`
**Concept:** Vibrating string visualizations with interference patterns  
**Mathematical Basis:** Wave equation, string harmonics, superposition

```
Visual: Glowing strings vibrating at different harmonics
Colors: Each harmonic has distinct color, interference creates moiré
Motion: Standing waves with traveling wave components
Params:
  - x: Fundamental frequency
  - y: Harmonic richness (1 to 10 harmonics)
  - z: Damping/decay
  - w: Excitement (pluck strength)
```

**Implementation Notes:**
- 1D wave equation: y = sin(kx - ωt) + sin(kx + ωt)
- Multiple strings at different angles
- Interference visualization
- Glow/bloom for string energy

---

### 6. `gen-supernova-remnant`
**Concept:** Expanding shell structures with shockwave physics  
**Mathematical Basis:** Expanding spherical shells, shock front physics

```
Visual: Explosive radial patterns like Hubble nebula images
Colors: Core white-hot, cooling to reds and purples at edges
Motion: Continuous expansion, new shells born at center
Params:
  - x: Explosion energy
  - y: Shell density
  - z: Turbulence/chaos
  - w: Color temperature shift
```

**Implementation Notes:**
- Multiple expanding concentric shells
- Each shell has different speed
- Turbulence via noise displacement
- Rayleigh-Taylor instability patterns

---

### 7. `gen-quasicrystal`
**Concept:** Penrose tiling-inspired quasicrystal patterns  
**Mathematical Basis:** Aperiodic tiling, 5-fold symmetry, projection method

```
Visual: Never-repeating patterns with 5-fold symmetry
Colors: Metallic golds and silvers with gem accents
Motion: Slow rotation revealing hidden symmetries
Params:
  - x: Symmetry order (5, 7, 9, 11)
  - y: Pattern density
  - z: Color cycling
  - w: Projection angle
```

**Implementation Notes:**
- Use projection from higher-dimensional lattice
- Slice method for quasicrystal generation
- Rhombus tiling with matching rules
- Gradients for metallic effect

---

### 8. `gen-mycelium-network`
**Concept:** Growing network patterns like fungal mycelium  
**Mathematical Basis:** Diffusion-limited aggregation, branching processes

```
Visual: Organic branching networks spreading from centers
Colors: Earthy browns, bioluminescent green tips
Motion: Slow growth, tips pulse with activity
Params:
  - x: Growth rate
  - y: Branching factor
  - z: Nutrient density (fills space)
  - w: Bioluminescence intensity
```

**Implementation Notes:**
- Agent-based or reaction-diffusion approach
- Tips search for space, branch probabilistically
- Age-based coloring (older = darker)
- Tip glow for active growth areas

---

### 11. `gen-temporal-motion-smear`
**Concept:** Motion-aware temporal smearing using optical flow estimation  
**Mathematical Basis:** Frame differencing, velocity estimation, directional blur

```
Visual: Moving objects leave colorful trails that follow their path
Colors: Warm trails fading to cool (or rainbow based on velocity)
Motion: Real-time motion detection with decaying trails
Params:
  - x: Trail persistence (how long trails last)
  - y: Motion sensitivity
  - z: Smear directionality (0=omni, 1=direction-aware)
  - w: Color intensity boost
```

**Implementation Notes:**
- Use readTexture (current) vs dataTextureC (previous frame)
- Calculate motion vectors via frame differencing
- Apply directional blur along motion vectors
- Decay trail intensity over time using feedback
- Category: "image" (requires input)

---

### 12. `gen-velocity-bloom`
**Concept:** Velocity-sensitive bloom that intensifies on motion  
**Mathematical Basis:** Motion magnitude detection, threshold-based glow

```
Visual: Static areas normal, moving areas glow with light
Colors: White core with colored aura based on velocity
Motion: Bloom intensity proportional to speed
Params:
  - x: Velocity threshold
  - y: Bloom intensity
  - z: Bloom radius
  - w: Decay rate
```

**Implementation Notes:**
- Compare current vs previous frame
- Calculate velocity magnitude per pixel
- Apply bloom where velocity > threshold
- Multi-octave glow for quality
- Category: "image" (requires input)

---

### 13. `gen-feedback-echo-chamber`
**Concept:** Multi-layer temporal echo with feedback decay  
**Mathematical Basis:** Feedback buffer, exponential decay, layered composition

```
Visual: Multiple ghost images of previous frames fading into depth
Colors: Each echo layer tinted differently (oldest = most faded)
Motion: Real-time video echoes into infinite depth
Params:
  - x: Echo count (2 to 8 layers)
  - y: Decay rate (how fast echoes fade)
  - z: Echo spacing (temporal distance)
  - w: Color shift per echo
```

**Implementation Notes:**
- Use dataTextureA/B for echo history
- Cycle through N echo buffers
- Each frame: shift echoes, add current
- Apply exponential decay
- Composite with color grading per layer
- Category: "image" (requires input)

---

### 9. `gen-magnetic-field-lines`
**Concept:** Visualizing magnetic field lines with charged particles  
**Mathematical Basis:** Dipole field equations, Lorentz force, particle tracing

```
Visual: Curved field lines with particles spiraling along them
Colors: North pole blue, south pole red, particles white
Motion: Particles flow along field lines
Params:
  - x: Field strength
  - y: Particle speed
  - z: Number of dipoles (1 to 5)
  - w: Particle trail length
```

**Implementation Notes:**
- Magnetic dipole field: B ∝ (3(m·r)r - m) / |r|³
- Particle tracing with Runge-Kutta or simple Euler
- Multiple dipoles for complex fields
- Streamline visualization

---

### 10. `gen-bifurcation-diagram`
**Concept:** Logistic map bifurcation as visual art  
**Mathematical Basis:** Logistic map: xₙ₊₁ = r·xₙ·(1-xₙ), bifurcation theory

```
Visual: Classic bifurcation diagram with artistic enhancement
Colors: Density-based coloring (more iterations = brighter)
Motion: Slow pan across r parameter, zoom into interesting regions
Params:
  - x: r parameter position (2.0 to 4.0)
  - y: Zoom level
  - z: Iteration count
  - w: Color scheme (thermal, rainbow, etc.)
```

**Implementation Notes:**
- For each pixel, iterate logistic map
- Plot x values after transient
- Color by density or iteration count
- Highlight periodic windows and chaos

---

## Technical Requirements

### Required Functions for Generative Shaders

```wgsl
// Standard header (all 13 bindings)
// ...

// Useful helper functions (include as needed)
fn hash12(p: vec2<f32>) -> f32 { ... }
fn hash13(p: vec3<f32>) -> f32 { ... }
fn noise(p: vec2<f32>) -> f32 { ... }
fn fbm(p: vec2<f32>, octaves: i32) -> f32 { ... }
fn rot2(a: f32) -> mat2x2<f32> { ... }
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> { ... }
```

### Parameter Safety (Critical!)

All parameters must be randomization-safe:

```wgsl
// GOOD: Always valid
let speed = mix(0.1, 2.0, u.zoom_params.x);
let count = i32(u.zoom_params.y * 10.0) + 1;

// BAD: Can cause issues
let divide = 1.0 / u.zoom_params.x; // Division by zero!
let logVal = log(u.zoom_params.y);  // log(0) undefined!
```

### Audio Reactivity (Optional)

If including audio reactivity:

```wgsl
// Audio input typically in zoom_config.x or config.y
let audio = u.config.y; // 0.0 to 1.0

// Use to modulate parameters
let intensity = baseIntensity * (1.0 + audio * 0.5);
```

---

## JSON Definition Template

```json
{
  "id": "gen-{name}",
  "name": "{Display Name}",
  "url": "shaders/gen-{name}.wgsl",
  "category": "generative",
  "description": "Brief description of the effect",
  "tags": ["generative", "procedural", "loops", "mathematical"],
  "features": ["audio-reactive"],
  "params": [
    {
      "id": "param1",
      "name": "Parameter 1 Name",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Parameter 2 Name",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Parameter 3 Name",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Parameter 4 Name",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ]
}
```

---

## Deliverables

For each of the 10 shaders, provide:

1. **WGSL File** at `public/shaders/gen-{name}.wgsl`
2. **JSON Definition** at `shader_definitions/generative/gen-{name}.json`
3. **Brief Description** (2-3 sentences) of the visual effect

---

## Quality Criteria

- [ ] Shader compiles without errors
- [ ] Works without input image (generative)
- [ ] Parameters are randomization-safe
- [ ] Runs at 60fps
- [ ] Visually interesting at default parameters
- [ ] Alpha = 1.0 (full opaque, appropriate for generative)
- [ ] Proper header comment with description

---

## Inspiration References

- Inigo Quilez's articles on raymarching and SDFs
- The Book of Shaders (shaderToy examples)
- Nature of Code (generative algorithms)
- Complexification.net (generative art gallery)
