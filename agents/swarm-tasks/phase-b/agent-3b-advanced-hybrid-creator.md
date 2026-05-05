# Agent 3B: Advanced Hybrid Shader Creator
## Task Specification - Phase B, Agent 3

**Role:** Complex Multi-Technique Shader Architect  
**Priority:** HIGH  
**Target:** Create 18 new advanced hybrid/simulation shaders (10 complex + 8 multi-pass simulations)  
**Estimated Duration:** 6-7 days

---

## Mission

Create complex shaders combining multiple advanced techniques from Phase A's chunk library. These are "next-level" hybrids that push the boundaries of what's possible with the existing rendering architecture.

---

## Advanced Hybrid Concepts

### 1. `hyper-tensor-fluid`
**Concept:** Combines tensor field mathematics with Navier-Stokes fluid dynamics  
**Complexity:** Very High  
**Techniques:**
- Tensor eigendecomposition (from tensor-flow-sculpting)
- Velocity advection (from navier-stokes-dye)
- Depth-aware displacement
- Multi-frequency FBM

```wgsl
// Key Innovation: Use tensor eigenvectors as flow field directions
let eigen = calculateTensorEigen(depthGradient);
let flowDirection = eigen.vec_pos;

// Advect fluid along principal stress directions
let advectedUV = uv + flowDirection * velocity * dt;

// Add turbulence via FBM
let turbulence = fbm(uv * 8.0 + time) * 0.1;
advectedUV += turbulence;
```

**Visual:** Fluid that flows according to image structure - edges create barriers, smooth areas allow flow

**Params:**
- x: Tensor strength
- y: Fluid viscosity
- z: Turbulence amount
- w: Advection speed

---

### 2. `neural-raymarcher`
**Concept:** Neural network weight visualization rendered with raymarching  
**Complexity:** Very High  
**Techniques:**
- SDF raymarching
- Neural activation patterns (tanh, sigmoid, ReLU)
- Weight matrix visualization
- Volumetric fog

```wgsl
// SDF combining neural "neurons" arranged in layers
fn neuralSDF(p: vec3<f32>) -> f32 {
    var d = MAX_DIST;
    
    // Layer 1: Input neurons
    for (var i = 0; i < 8; i++) {
        let neuronPos = vec3<f32>(f32(i) * 0.5 - 2.0, 0.0, 0.0);
        let neuron = sdSphere(p - neuronPos, 0.2);
        d = smin(d, neuron, 0.1);
    }
    
    // Connections with weights visualized as thickness
    // ...
    
    return d;
}

// Activation function coloring
let activation = tanh(dot(inputs, weights));
let color = activationPalette(activation);
```

**Visual:** Glowing 3D neural network structure floating in space, weights shown as connection thickness, activations as color

**Params:**
- x: Network depth (layers)
- y: Activation visualization
- z: Glow intensity
- w: Camera rotation speed

---

### 3. `chromatic-reaction-diffusion`
**Concept:** Multi-channel reaction-diffusion with chromatic aberration  
**Complexity:** High  
**Techniques:**
- Gray-Scott reaction-diffusion
- Multi-channel (RGB each have separate feed/kill rates)
- Chromatic separation
- Temporal feedback

```wgsl
// Separate feed/kill for each channel
let feedRates = vec3<f32>(
    mix(0.01, 0.1, u.zoom_params.x),
    mix(0.02, 0.08, u.zoom_params.y),
    mix(0.005, 0.12, u.zoom_params.z)
);

// Reaction-diffusion for each channel
var r = reactDiffuse(uv, feedRates.r, killRates.r, 0);
var g = reactDiffuse(uv, feedRates.g, killRates.g, 1);
var b = reactDiffuse(uv, feedRates.b, killRates.b, 2);

// Chromatic displacement based on Laplacian
let laplacian = vec3<f32>(
    length(r - centerR),
    length(g - centerG),
    length(b - centerB)
);

// Displace each channel differently
color.r = sampleChannelR(uv + laplacian.yz * 0.01);
color.g = sampleChannelG(uv + laplacian.xz * 0.01);
color.b = sampleChannelB(uv + laplacian.xy * 0.01);
```

**Visual:** Organic patterns where each color channel evolves independently, creating chromatic fringes at pattern boundaries

**Params:**
- x: Red channel feed rate
- y: Green channel feed rate
- z: Blue channel feed rate
- w: Chromatic separation amount

---

### 4. `audio-voronoi-displacement`
**Concept:** Audio-reactive Voronoi cells that displace the image  
**Complexity:** High  
**Techniques:**
- Voronoi tessellation
- Audio FFT analysis
- Displacement mapping
- Cell-based color grading

```wgsl
// Get audio bands
let bass = audioBands.x;   // Low frequencies
let mid = audioBands.y;    // Mid frequencies
let treble = audioBands.z; // High frequencies

// Generate Voronoi with audio-modulated seeds
let seeds = generateSeeds(uv, time);
seeds += audioReactiveOffset(seeds, bass, mid, treble);

let voronoi = calculateVoronoi(uv, seeds);
let cellId = voronoi.id;
let cellCenter = voronoi.center;

// Displace based on cell + audio
let displacement = normalize(uv - cellCenter) * bass * 0.1;
let displacedUV = uv + displacement;

// Color based on frequency bands per cell
let cellHash = hash12(vec2<f32>(f32(cellId)));
let colorShift = vec3<f32>(
    bass * cellHash,
    mid * fract(cellHash * 1.5),
    treble * fract(cellHash * 2.5)
);
```

**Visual:** Image fractured into cells that pulse and move with the music, each cell tinted by frequency

**Params:**
- x: Cell count
- y: Audio reactivity
- z: Displacement strength
- w: Color intensity

---

### 5. `fractal-boids-field`
**Concept:** Flocking behavior on a fractal vector field  
**Complexity:** High  
**Techniques:**
- Reynolds boids (separation, alignment, cohesion)
- Fractal flow field (from domain-warped FBM)
- GPU particle simulation
- Trail rendering

```wgsl
// Fractal vector field
let flowField = domainWarpFBM(uv * 5.0, time * 0.1);

// Boid simulation
for (var i = 0; i < NUM_BOIDS; i++) {
    let boid = boids[i];
    
    // Combine boid rules with flow field
    let separation = calculateSeparation(boid, neighbors);
    let alignment = calculateAlignment(boid, neighbors);
    let cohesion = calculateCohesion(boid, neighbors);
    let flow = sampleFlowField(boid.position);
    
    let velocity = separation * 1.5 + alignment * 1.0 + cohesion * 0.5 + flow * 2.0;
    boid.position += velocity * dt;
    
    // Render boid trail
    let trailIntensity = renderTrail(boid.position, boid.history);
    color += boid.color * trailIntensity;
}
```

**Visual:** Swarms of particles flowing through organic fractal currents, leaving glowing trails

**Params:**
- x: Boid count (simulated)
- y: Flow field strength
- z: Trail persistence
- w: Separation distance

---

### 6. `holographic-interferometry`
**Concept:** Simulated hologram with interference fringe patterns  
**Complexity:** High  
**Techniques:**
- Interference pattern math (constructive/destructive)
- Holographic recording/reconstruction
- Phase-based coloring
- Speckle noise

```wgsl
// Simulate reference beam interference
let objectBeam = sampleObject(uv, depth);
let referenceBeam = exp(i * k * dot(uv, referenceDirection));

// Interference pattern
let interference = objectBeam + referenceBeam;
let intensity = dot(interference, conjugate(interference));

// Fringe pattern from phase differences
let phase = atan2(interference.y, interference.x);
let fringes = sin(phase * fringeDensity);

// Holographic reconstruction
let reconstructed = reconstructHologram(intensity, phase, reconstructionBeam);

// Speckle noise for realism
let speckle = generateSpeckle(uv, laserCoherence);
```

**Visual:** Rainbow interference fringes, speckled laser light, depth-parallax holographic effect

**Params:**
- x: Fringe density
- y: Coherence length (speckle size)
- z: Reconstruction angle
- w: Color saturation

---

### 7. `gravitational-lensing`
**Concept:** General relativistic light bending around massive objects  
**Complexity:** Very High  
**Techniques:**
- Schwarzschild metric
- Geodesic raytracing
- Einstein ring
- Accretion disk physics

```wgsl
// Ray direction from UV
let rayDir = normalize(vec3<f32>(uv - 0.5, 1.0));
let rayPos = cameraPos;

// Raytrace through Schwarzschild metric
for (var i = 0; i < MAX_STEPS; i++) {
    // Calculate metric at current position
    let r = length(rayPos - blackHolePos);
    let metric = schwarzschildMetric(r, blackHoleMass);
    
    // Geodesic equation
    let christoffel = calculateChristoffel(rayPos, metric);
    rayDir += christoffel * dt;
    rayDir = normalize(rayDir);
    rayPos += rayDir * dt;
    
    // Check for event horizon
    if (r < eventHorizon) {
        color = vec3<f32>(0.0); // Black hole
        break;
    }
    
    // Sample background at far distances
    if (r > 100.0) {
        color = sampleBackground(rayDir);
        break;
    }
}

// Add accretion disk
let diskColor = renderAccretionDisk(rayPos, rayDir);
color += diskColor;
```

**Visual:** Background stars distorted around black hole, Einstein ring, glowing accretion disk with Doppler beaming

**Params:**
- x: Black hole mass
- y: Accretion disk brightness
- z: Camera orbit position
- w: Gravitational redshift intensity

---

### 8. `cellular-automata-3d`
**Concept:** 3D cellular automata (like 3D Game of Life) rendered with volume raymarching  
**Complexity:** Very High  
**Techniques:**
- 3D cellular automata (26 neighbors)
- Volume texture storage
- Raymarching through volume
- Transfer function coloring

```wgsl
// 3D CA rules (similar to Conways but in 3D)
// Birth: 4-5 neighbors, Survival: 5-6 neighbors
fn updateCell3D(pos: vec3<i32>) -> f32 {
    let neighbors = countNeighbors3D(pos);
    let current = getCell3D(pos);
    
    if (current > 0.5) {
        // Survival
        return select(0.0, 1.0, neighbors >= 5 && neighbors <= 6);
    } else {
        // Birth
        return select(0.0, 1.0, neighbors >= 4 && neighbors <= 5);
    }
}

// Raymarch through CA volume
fn raymarchCA(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var t = 0.0;
    var color = vec3<f32>(0.0);
    var transmittance = 1.0;
    
    for (var i = 0; i < 128; i++) {
        let pos = ro + rd * t;
        let cell = sampleCAVolume(pos);
        
        if (cell > 0.5) {
            // Transfer function: cell age → color
            let age = getCellAge(pos);
            let emission = transferFunction(age);
            
            // Volume rendering equation
            let density = 0.1;
            color += transmittance * emission * density;
            transmittance *= 1.0 - density;
            
            if (transmittance < 0.01) { break; }
        }
        
        t += 0.05;
    }
    
    return color;
}
```

**Visual:** Glowing 3D structures that evolve frame-by-frame, viewed from any angle

**Params:**
- x: Evolution speed
- y: Initial density
- z: Color cycling
- w: Camera rotation

---

### 9. `spectral-flow-sorting`
**Concept:** Optical flow-based pixel sorting with spectral analysis  
**Complexity:** High  
**Techniques:**
- Optical flow calculation
- Pixel sorting along flow lines
- FFT frequency analysis
- Directional blur

```wgsl
// Calculate optical flow between frames
let flow = calculateOpticalFlow(uv, prevFrame, currentFrame);

// Analyze frequency content
let spectrum = fft2x2(currentFrame);
let dominantFreq = findDominantFrequency(spectrum);

// Sort pixels along flow direction
let flowAngle = atan2(flow.y, flow.x);
let flowLine = rotateUV(uv, flowAngle);

// Sort based on luminance along flow line
let sorted = sortPixelsAlongLine(flowLine, sortThreshold);

// Color based on frequency
let freqColor = frequencyToColor(dominantFreq);
let finalColor = mix(sorted, freqColor, freqInfluence);
```

**Visual:** Pixels flow and sort along motion vectors, colors shift based on spatial frequencies

**Params:**
- x: Flow sensitivity
- y: Sort threshold
- z: Frequency influence
- w: Temporal smoothing

---

### 10. `multi-fractal-compositor`
**Concept:** Smoothly blend between multiple fractal types  
**Complexity:** High  
**Techniques:**
- Mandelbrot set
- Julia set
- Burning Ship
- Newton fractal
- Smooth interpolation between types

```wgsl
// Fractal type blending
let fractalMix = u.zoom_params.w; // 0.0 to 1.0 cycles through types

let typeA = i32(fractalMix * 4.0) % 4;
let typeB = (typeA + 1) % 4;
let blend = fract(fractalMix * 4.0);

// Calculate both fractals
let resultA = calculateFractal(uv, typeA, maxIter);
let resultB = calculateFractal(uv, typeB, maxIter);

// Smooth interpolation (not just mix - interpolate the iteration counts)
let result = smoothFractalInterpolate(resultA, resultB, blend);

// Domain warping for extra organic feel
let warpedUV = domainWarp(uv, time);
result += fbm(warpedUV * 10.0) * 0.1;

// Color from iteration count + orbit trap
let color = orbitTrapColoring(result.z, result.trap);
```

**Visual:** Morphing fractals that smoothly transition between Mandelbrot, Julia, and other types, with domain warping for organic feel

**Params:**
- x: Zoom level
- y: Iteration count
- z: Domain warp amount
- w: Fractal type blend

---

### 11. `sim-fluid-feedback-field`
**Concept:** Multi-pass fluid simulation with feedback trails  
**Complexity:** Very High  
**Techniques:**
- Navier-Stokes simplified (2D)
- Multi-pass advection
- Density field feedback
- Velocity-decay trails

```
Pass 1: Velocity advection
  - Advect velocity field through itself
  - Add curl noise for turbulence
  - Output to dataTextureA

Pass 2: Density advection  
  - Advect density through velocity field
  - Add new density from mouse/input
  - Output to dataTextureB

Pass 3: Composite
  - Read density from dataTextureB
  - Add glow, color grading
  - Volumetric rendering approximation
```

**Visual:** Glowing fluid that swirls, mixes, and leaves trails - like ink in water with light inside

**Params:**
- x: Viscosity (flow resistance)
- y: Turbulence amount
- z: Density fade rate
- w: Glow intensity

---

### 12. `sim-heat-haze-field`
**Concept:** Procedural heat distortion with thermal convection  
**Complexity:** High  
**Techniques:**
- Temperature field simulation
- Convection currents
- Refraction index from temperature
- Multi-octave distortion

```
Visual: Desert mirage effect with rising heat patterns
Colors: Hot areas shimmer with distortion, cooler areas clearer
Motion: Heat rises naturally, creating organic convection cells
Params:
  - x: Temperature intensity
  - y: Convection speed
  - z: Distortion strength
  - w: Heat source count
```

**Implementation Notes:**
- Simulate temperature field on grid
- Hot air rises (buoyancy), cools, falls
- Use temperature to drive refraction offset
- Multiple heat sources that can be moved
- Category: "distortion"

---

### 13. `sim-sand-dunes`
**Concept:** Falling sand physics with wind erosion  
**Complexity:** High  
**Techniques:**
- Cellular automata (sand rules)
- Wind field simulation
- Erosion patterns
- Particle accumulation

```
Visual: Dynamic sand dunes that shift and evolve
Colors: Warm desert tones - golds, oranges, reds
Motion: Sand falls, piles, avalanches, wind sculpts
Params:
  - x: Gravity strength
  - y: Wind direction/speed
  - z: Sand viscosity
  - w: Erosion rate
```

**Implementation Notes:**
- Grid-based sand simulation
- Sand falls down, piles at angle of repose
- Wind moves loose sand particles
- Mouse adds sand at click
- Category: "simulation"

---

### 14. `sim-ink-diffusion`
**Concept:** Fluid ink diffusion with paper absorption  
**Complexity:** High  
**Techniques:**
- Reaction-diffusion (Gray-Scott)
- Paper texture simulation
- Ink bleeding at edges
- Multiple ink colors

```
Visual: Ink drops spreading on wet paper
Colors: Deep blacks, blues, reds blending organically
Motion: Drops expand, merge, bleed into paper grain
Params:
  - x: Paper wetness (diffusion rate)
  - y: Ink viscosity
  - z: Feed rate (drop size)
  - w: Color mixing intensity
```

**Implementation Notes:**
- Multi-channel reaction-diffusion
- Each channel = one ink color
- Paper texture affects diffusion rate
- Mouse drops ink at position
- Category: "artistic"

---

### 15. `sim-smoke-trails`
**Concept:** Rising smoke with turbulence and dissipation  
**Complexity:** High  
**Techniques:**
- Vorticity-based fluid simulation
- Temperature/buoyancy
- Particle seeding
- Dissipation/decay

```
Visual: Billowing smoke rising with natural turbulence
Colors: Gray smoke with fire-source glow at bottom
Motion: Smoke rises, swirls, dissipates realistically
Params:
  - x: Smoke density
  - y: Turbulence strength
  - z: Rise speed
  - w: Dissipation rate
```

**Implementation Notes:**
- Simplified fluid sim with vorticity confinement
- Smoke seeded at bottom or mouse position
- Buoyancy drives upward motion
- Turbulence adds realism
- Category: "simulation"

---

### 16. `sim-slime-mold-growth`
**Concept:** Physarum-style slime mold with trail following  
**Complexity:** Very High  
**Techniques:**
- Agent-based particle system
- Chemoattractant trail deposition
- Sensor-based steering
- Decay/diffusion of trails

```
Visual: Branching network of glowing trails exploring space
Colors: Bright cyan trails on dark background
Motion: Organic exploration, pathfinding, network optimization
Params:
  - x: Sensor angle (steering sensitivity)
  - y: Trail decay rate
  - z: Particle count
  - w: Randomness/jitter
```

**Implementation Notes:**
- 1000s of agents in compute-friendly way
- Each agent deposits trail
- Agents steer based on trail sensors (left/center/right)
- Trails diffuse and decay over time
- Category: "simulation"

---

### 17. `sim-volumetric-fake`
**Concept:** Fake volumetric lighting without raymarching  
**Complexity:** Medium  
**Techniques:**
- Blur-based scattering approximation
- Depth-based density
- Multi-octave god rays
- Light source occlusion

```
Visual: Light beams through dusty air, volumetric god rays
Colors: Warm light shafts through cool shadows
Motion: Dust particles drift, light intensity pulses
Params:
  - x: Light source intensity
  - y: Dust density
  - z: Scattering amount
  - w: Noise speed (dust movement)
```

**Implementation Notes:**
- Radial blur from light source position
- Multiply by depth-based density
- Add noise for dust particles
- Occlusion from depth map
- Much faster than true volumetrics
- Category: "lighting-effects"

---

### 18. `sim-decay-system`
**Concept:** Multi-layer decay and corrosion simulation  
**Complexity:** Medium  
**Techniques:**
- Cellular automata (corrosion rules)
- Layered material system
- Edge-preferential decay
- Color transformation

```
Visual: Image appears to corrode, rust, or decay over time
Colors: Vibrant → faded → corroded → dark
Motion: Gradual degradation at different rates per region
Params:
  - x: Decay rate
  - y: Edge vulnerability
  - z: Color shift amount
  - w: Recovery/regeneration rate
```

**Implementation Notes:**
- Use feedback buffer for decay state
- Decay progresses from edges inward
- Different materials decay differently
- Can "paint" protection or accelerate decay
- Category: "artistic"

---

## Technical Requirements

### Header Template

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {ADVANCED_HYBRID_NAME}
//  Category: {category}
//  Features: advanced-hybrid, {technique-list}
//  Complexity: {High/Very High}
//  Chunks From: {source shaders}
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════

// Include necessary chunks from Agent 2A's library
// ...

// Hybrid-specific functions
// ...

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    // ... implementation
}
```

### Performance Targets

| Shader | Target FPS (GTX 1060) |
|--------|----------------------|
| hyper-tensor-fluid | 45-60 |
| neural-raymarcher | 30-45 |
| chromatic-reaction-diffusion | 60 |
| audio-voronoi-displacement | 60 |
| fractal-boids-field | 45-60 |
| holographic-interferometry | 60 |
| gravitational-lensing | 30-45 |
| cellular-automata-3d | 30-45 |
| spectral-flow-sorting | 45-60 |
| multi-fractal-compositor | 45-60 |

### Parameter Safety

All parameters must use safe patterns:

```wgsl
// Safe parameter extraction
let param1 = u.zoom_params.x; // 0-1
let param2 = mix(minVal, maxVal, u.zoom_params.y); // Mapped range

// No unsafe operations
// - Division: always add epsilon
// - Log: always add offset
// - Sqrt: always max with 0
```

---

## Deliverables

1. **10 WGSL files:** `public/shaders/{hybrid-name}.wgsl`
2. **10 JSON definitions:** `shader_definitions/{category}/{hybrid-name}.json`
3. **Documentation:** For each hybrid, explain:
   - Techniques combined
   - Visual effect description
   - Parameter guide
   - Performance notes

---

## Success Criteria

- All 10 shaders compile and run
- Visual quality is "wow" level
- Performance targets met
- Parameters are randomization-safe
- Code is well-commented
- Techniques properly attributed to source chunks
