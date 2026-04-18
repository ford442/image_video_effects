# Agent 2C: Psychedelic Mouse Sculptor
## Task Specification — Phase C, Agent 2

**Role:** Complex Mouse-Responsive Shader Artist  
**Priority:** HIGH  
**Target:** 15 mouse-interactive shaders with physically-inspired interaction models  
**Estimated Duration:** 5-7 days

---

## Mission

Create mouse-interactive shaders that go far beyond simple ripple distortion. The current library uses mouse position for displacement, ripples for wave propagation, and basic attractor/repulsion. This agent introduces **physically-inspired interaction models** where the mouse acts as an electromagnetic source, a gravitational lens, a quantum tunneling probe, a fluid coupling device, or a fractal zoom portal.

Each shader must be **visually psychedelic, beautiful, and fun to play with** — the kind of effect that makes people move their mouse just to see what happens.

---

## Interaction Model Catalog

### Category A: Field-Based Mouse Interactions

#### 1. `mouse-electromagnetic-aurora.wgsl` — Electromagnetic Field Visualization
**Concept:** The mouse is a moving charge. It generates electric and magnetic field lines that distort and colorize the image. When the mouse moves fast, relativistic effects cause Doppler-shifted colors. Click ripples act as secondary charges with opposite polarity.

**Physics model:**
```wgsl
fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
    let r = pos - chargePos;
    let dist = max(length(r), 0.001);
    return charge * normalize(r) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
    let r = pos - chargePos;
    let dist = max(length(r), 0.001);
    // B = (charge * v × r) / r³  (2D cross product gives scalar)
    return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}
```

**Mouse velocity:** Derived from `u.zoom_config.yz` difference vs previous frame (stored in `dataTextureC` at a fixed pixel location as a convention, or approximated from time derivative).

**Visual output:**
- Field lines visible as flowing, colored streamlines over the image
- Electric field distorts UV coordinates (pixel displacement along field direction)
- Magnetic field rotates pixel color hue (stronger field = more hue rotation)
- Moving charges create Lorentz force on nearby "virtual particles" that flow with the field
- Click ripples spawn opposite-polarity charges that orbit the mouse position

**RGBA32FLOAT exploitation:**
- RG: Accumulated field vector (signed f32 — fields can point in any direction)
- B: Field magnitude (can exceed 1.0 near charges)
- A: Magnetic flux (signed — essential for correct field visualization)

**Params:**
| Param | Name | Default | Range | Purpose |
|-------|------|---------|-------|---------|
| x | Charge Strength | 0.5 | 0.0-1.0 | Primary charge magnitude |
| y | Field Visibility | 0.5 | 0.0-1.0 | How visible the field lines are |
| z | Distortion Strength | 0.3 | 0.0-1.0 | UV displacement amount |
| w | Color Rotation | 0.5 | 0.0-1.0 | Hue rotation from magnetic field |

---

#### 2. `mouse-gravity-lensing.wgsl` — General Relativistic Gravitational Lensing
**Concept:** The mouse is a massive object warping spacetime. Light rays from the input image are bent around the mouse position following the Schwarzschild metric approximation. Creates Einstein rings, arcs, and multiple images of background objects.

**Physics model:**
```wgsl
fn deflectionAngle(impactParam: f32, schwarzschildRadius: f32) -> f32 {
    // Weak-field GR: α ≈ 4GM / (c²b) = 2Rs / b
    return 2.0 * schwarzschildRadius / max(impactParam, 0.001);
}

fn lensSample(uv: vec2<f32>, lensPos: vec2<f32>, mass: f32) -> vec2<f32> {
    let r = uv - lensPos;
    let dist = length(r);
    let rs = mass * 0.1; // Schwarzschild radius (scaled)
    let deflection = deflectionAngle(dist, rs);
    let deflectionDir = normalize(r);
    return uv + deflectionDir * deflection;
}
```

**Visual output:** The image bends around the mouse like looking through a gravity well. Close to the mouse, you see an Einstein ring — the background image wraps completely around. Multiple ghost images appear near the critical curve.

**Mouse interactivity:**
- Position = center of gravity well
- Mouse speed = mass (move fast = stronger lensing)
- Ripples = gravitational wave bursts (oscillating distortion that propagates outward)
- Mouse down = doubles the mass (deep lens mode)

---

#### 3. `mouse-quantum-tunnel-probe.wgsl` — Quantum Tunneling Effect
**Concept:** The image is divided into "potential barriers" based on edge detection. The mouse emits a quantum probability wave that tunnels through barriers with exponential attenuation. Bright regions are "allowed" zones, dark edges are "barriers." The tunneling creates ghostly, ethereal reveals.

**Physics model:**
```wgsl
fn tunnelingProbability(barrierHeight: f32, barrierWidth: f32, particleEnergy: f32) -> f32 {
    // T ≈ exp(-2κd) where κ = sqrt(2m(V-E)) / ℏ
    let kappa = sqrt(max(barrierHeight - particleEnergy, 0.0)) * 10.0;
    return exp(-2.0 * kappa * barrierWidth);
}
```

**Visual output:** A glowing probability cloud emanates from the mouse position. It flows through open (bright) areas of the image easily, but where edges (barriers) exist, only a fraction of the "wave" penetrates. The result is a ghostly, luminous reveal that follows the image's natural contours.

---

#### 4. `mouse-fluid-coupling.wgsl` — Viscous Fluid Coupling
**Concept:** The mouse drags a viscous fluid that covers the image. The fluid has surface tension, viscosity, and the mouse acts as a stirring rod. Dragging creates vortex streets (von Kármán pattern). The fluid acts as a colored lens — its thickness determines color shift and blur amount.

**Physics model:** Simplified 2D Navier-Stokes with mouse as a moving boundary condition.

```wgsl
// Velocity field stored in dataTextureC (from previous frame)
fn advectVelocity(uv: vec2<f32>, dt: f32) -> vec2<f32> {
    let vel = textureLoad(dataTextureC, coord, 0).xy;
    let prevUV = uv - vel * dt;
    return textureSampleLevel(dataTextureC, u_sampler, prevUV, 0.0).xy;
}

fn applyMouseForce(uv: vec2<f32>, mousePos: vec2<f32>, mouseVel: vec2<f32>, radius: f32) -> vec2<f32> {
    let dist = length(uv - mousePos);
    let influence = smoothstep(radius, 0.0, dist);
    return mouseVel * influence * 2.0;
}
```

**RGBA32FLOAT exploitation:**
- RG: Velocity field (signed, sub-pixel precision essential for stable advection)
- B: Pressure field (from Poisson solver — needs f32 for convergence)
- A: Fluid density/thickness (controls visual opacity and color absorption)

---

### Category B: Fractal & Mathematical Mouse Interactions

#### 5. `mouse-mandelbrot-zoom-portal.wgsl` — Interactive Mandelbrot Deep Zoom
**Concept:** The mouse position maps to a point in the Mandelbrot set. Moving the mouse navigates the infinite fractal landscape in real time. Clicking creates a zoom portal — a circular region that shows a deeper zoom level. Multiple clicks create nested portals.

**Implementation:** Uses `u.ripples` array to store zoom portal centers and their zoom levels (startTime encodes depth level). Each portal renders the Mandelbrot at a progressively deeper zoom using the ripple position as the complex-plane center.

```wgsl
fn mandelbrot(c: vec2<f32>, maxIter: i32) -> vec2<f32> {
    var z = vec2<f32>(0.0);
    var i = 0;
    for (; i < maxIter; i++) {
        if (dot(z, z) > 4.0) { break; }
        z = vec2<f32>(z.x*z.x - z.y*z.y, 2.0*z.x*z.y) + c;
    }
    // Smooth iteration count (guarded against log2(0) when dot(z,z) <= 1.0)
    let smooth_i = select(f32(i), f32(i) - log2(log2(max(dot(z, z), 1.0001))) + 4.0, dot(z, z) > 1.0);
    return vec2<f32>(smooth_i, f32(maxIter));
}
```

**RGBA32FLOAT exploitation:** Alpha stores the **smooth iteration count** (continuous float, not integer). This enables silky-smooth color gradients in the fractal boundary that would be impossible with integer iteration counts in 8-bit.

---

#### 6. `mouse-julia-morph.wgsl` — Interactive Julia Set Morphing
**Concept:** The mouse position controls the Julia set constant `c`. As the mouse moves, the Julia set continuously morphs between shapes. The input image is used as the escape-time color palette. Click ripples "pin" specific Julia configurations that persist and blend.

---

#### 7. `mouse-hyperbolic-navigator.wgsl` — Poincaré Disk Interactive Navigation
**Concept:** The image is mapped onto a Poincaré disk (hyperbolic plane). Mouse movement is a Möbius transformation that scrolls the hyperbolic plane. The image tiles infinitely as you navigate, with tiles getting smaller and more numerous toward the disk boundary.

```wgsl
fn mobiusTransform(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
    // (z - a) / (1 - conj(a)*z) in complex arithmetic
    let num = complexSub(z, a);
    let den = complexSub(vec2<f32>(1.0, 0.0), complexMul(complexConj(a), z));
    return complexDiv(num, den);
}
```

---

### Category C: Psychedelic & Artistic Mouse Interactions

#### 8. `mouse-chromatic-explosion.wgsl` — Chromatic Channel Explosion
**Concept:** The mouse acts as a prism. Near the mouse, the R, G, and B channels of the image are physically separated and displaced in different directions based on their "wavelength." Creates rainbow halos, chromatic aberration art, and spectral fan-outs.

**Advanced twist:** Each color channel follows a slightly different physical path (like light through a prism), creating smooth spectral fans. The displacement distance is proportional to wavelength separation from the reference (green), so red shifts more than blue in one direction.

```wgsl
fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32) -> vec2<f32> {
    let toMouse = uv - mousePos;
    let dist = length(toMouse);
    let prismAngle = atan2(toMouse.y, toMouse.x);
    
    // Snell's law approximation: deflection proportional to wavelength
    let deflection = wavelengthOffset * 0.05 / max(dist, 0.01);
    let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
    
    return uv + perpendicular * deflection;
}

// Sample each channel at different UV
let r = textureSampleLevel(readTexture, u_sampler, prismDisplace(uv, mousePos, -1.0), 0.0).r;
let g = textureSampleLevel(readTexture, u_sampler, prismDisplace(uv, mousePos, 0.0), 0.0).g;
let b = textureSampleLevel(readTexture, u_sampler, prismDisplace(uv, mousePos, 1.0), 0.0).b;
```

---

#### 9. `mouse-kaleidoscope-tunnel.wgsl` — Infinite Kaleidoscope Tunnel
**Concept:** The mouse position is the tunnel center. Moving creates a spiraling kaleidoscope that reflects and repeats the image into infinity. Depth (distance from mouse) determines the number of mirror reflections and the z-position in the tunnel.

**Implementation:** Combine polar coordinates → mirror folds → spiral twist → perspective projection.

---

#### 10. `mouse-paint-splatter.wgsl` — Fluid Paint Splatter
**Concept:** Mouse drags leave colorful paint splatters that spread, mix, and dry over time. Uses a simplified Lattice Boltzmann method for the fluid dynamics. Colors are sampled from the input image at the splash origin.

**RGBA32FLOAT exploitation:**
- RGB: Paint color (HDR — overlapping splatters accumulate beyond 1.0, then tone-mapped)
- A: Paint thickness/wetness (f32 precision tracks drying rate: starts at 1.0, exponentially decays toward 0.0 over time)

---

#### 11. `mouse-voronoi-shatter-interactive.wgsl` — Interactive Voronoi Shattering
**Concept:** Click positions create Voronoi cell centers. Each cell "shatters" the image — cells rotate, shift, and scale independently based on distance from their creating ripple. Creates a stained-glass window effect that evolves with each click.

**Implementation:** Uses ALL 50 ripple slots as Voronoi seeds.

```wgsl
fn nearestRippleVoronoi(uv: vec2<f32>) -> vec3<f32> {
    var minDist = 999.0;
    var secondDist = 999.0;
    var nearest = vec2<f32>(0.0);
    var nearestTime = 0.0;
    
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let d = length(uv - ripple.xy);
        if (d < minDist) {
            secondDist = minDist;
            minDist = d;
            nearest = ripple.xy;
            nearestTime = ripple.z;
        } else if (d < secondDist) {
            secondDist = d;
        }
    }
    
    return vec3<f32>(nearest, minDist);
}
```

---

#### 12. `mouse-magnetic-pixel-sand.wgsl` — Magnetic Pixel Sand
**Concept:** Pixels are treated as iron filings. The mouse is a magnet that attracts/repels pixels based on their luminance (bright = magnetic, dark = non-magnetic). Creates beautiful patterns as "bright grains" flow toward/away from the mouse.

---

#### 13. `mouse-time-crystal.wgsl` — Temporal Crystal Growth
**Concept:** Mouse clicks seed crystal growth points. Crystals grow over time using DLA (Diffusion-Limited Aggregation), but the crystal structure is modulated by the image's color/luminance. The crystal branches follow the image's natural gradients. Uses `dataTextureC` for persistent crystal state.

**RGBA32FLOAT exploitation:**
- R: Crystal age (how long ago this pixel crystallized — f32 tracks precise timing)
- G: Crystal branch ID (each seed gets a unique floating-point ID)
- B: Crystal density (accumulated growth probability)
- A: Crystal color temperature (maps to color based on age gradient)

---

#### 14. `mouse-wormhole-portal.wgsl` — Wormhole Portal Effect
**Concept:** Mouse position creates a portal to a "warped" version of the image. Inside the portal radius, the image is shown inverted, color-shifted, and with a spiraling distortion. The portal edge has an event-horizon glow with gravitational lensing. Dragging "stretches" the wormhole into an oval.

---

#### 15. `mouse-synesthetic-sound-paint.wgsl` — Synesthesia Painter
**Concept:** Combines mouse interaction with audio reactivity. Mouse position determines which "instrument" you're playing — different screen regions map to different effects (low-frequency bass blob in bottom, treble sparkles on top). When audio is present (plasmaBuffer), the mouse becomes a conductor, directing the visual "orchestra."

**Without audio:** Falls back to a mouse-responsive color synthesis where position determines the generative pattern (noise, Voronoi, fractals) and drag speed determines energy/complexity.

**RGBA32FLOAT exploitation:**
- RGB: Accumulated visual "sound" (HDR — loud moments push values far above 1.0)
- A: Energy level (continuous decay, f32 precision prevents quantization artifacts in the decay curve)

---

## Mouse Velocity Estimation Pattern

Since we don't have explicit mouse velocity in the uniforms, estimate it:

```wgsl
// Store current mouse position in dataTextureA at a known location
let storageCoord = vec2<u32>(0u, 0u); // Reserved pixel
if (global_id.x == 0u && global_id.y == 0u) {
    // Current mouse position
    textureStore(dataTextureA, storageCoord, vec4<f32>(u.zoom_config.yz, 0.0, 0.0));
}

// Read previous mouse position from dataTextureC
let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
let currentMouse = u.zoom_config.yz;
let mouseVelocity = (currentMouse - prevMouse) * 60.0; // Approximate at 60fps
```

---

## Shared Code Chunks

These utility functions should be used across multiple shaders:

```wgsl
// ═══ CHUNK: complexArithmetic (Agent 2C) ═══
fn complexMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}
fn complexDiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = max(dot(b, b), 0.0001); // Guard against division by zero
    return vec2<f32>(a.x*b.x + a.y*b.y, a.y*b.x - a.x*b.y) / denom;
}
fn complexConj(a: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x, -a.y);
}
fn complexSub(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a - b;
}
fn complexAbs(a: vec2<f32>) -> f32 {
    return length(a);
}

// ═══ CHUNK: mouseVelocityEstimator (Agent 2C) ═══
fn estimateMouseVelocity(dataTexC: texture_2d<f32>, currentMouse: vec2<f32>) -> vec2<f32> {
    let prevMouse = textureLoad(dataTexC, vec2<i32>(0, 0), 0).xy;
    return (currentMouse - prevMouse) * 60.0;
}

// ═══ CHUNK: rippleVoronoi (Agent 2C) ═══
// [nearestRippleVoronoi function from shader #11 above]
```

---

## Deliverables

1. **15 WGSL shader files** in `public/shaders/mouse-*.wgsl`
2. **15 JSON definition files** in `shader_definitions/interactive-mouse/mouse-*.json`
3. **Each shader must:**
   - Use a physically-inspired mouse interaction model
   - React to both `u.zoom_config.yz` (continuous position) AND `u.ripples` (click events)
   - Use the alpha channel meaningfully (document what it stores)
   - Be genuinely psychedelic / beautiful / fun to interact with
   - Include at least 2 controllable params
4. **Chunk library additions** to `swarm-outputs/chunk-library.md`

---

## Success Criteria

- [ ] All 15 shaders compile without WGSL errors
- [ ] Each shader responds to mouse movement (visually obvious within 0.1 seconds)
- [ ] Each shader responds to clicks via ripples (visually obvious within 0.2 seconds)
- [ ] No shader duplicates an existing interaction model
- [ ] Performance: 30+ FPS at 2048×2048
- [ ] "Fun factor" — each shader makes you want to move the mouse around
- [ ] JSON definitions include params, tags (must include "interactive", "mouse-driven"), description
