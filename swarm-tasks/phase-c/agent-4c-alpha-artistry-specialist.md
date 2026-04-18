# Agent 4C: Alpha Artistry Specialist
## Task Specification — Phase C, Agent 4

**Role:** RGBA-to-RGB Creative Effects & Alpha-as-Data-Channel Pioneer  
**Priority:** HIGH  
**Target:** 15 shaders that use RGBA32FLOAT as 4 independent creative data channels  
**Estimated Duration:** 5-7 days

---

## Mission

Go beyond "alpha = opacity" to create effects where the **alpha channel IS the effect**. In conventional rendering, RGBA means "color + transparency." In Phase C, RGBA means **four independent 32-bit floating-point data channels** that can store velocity, temperature, age, density, phase, or any other continuous value.

This agent creates shaders where:
1. The alpha channel stores simulation state that creates the visual effect
2. RGBA packing enables simulations that require 4+ fields in a single texture
3. The full dynamic range of f32 (negative values, values > 1.0, sub-pixel precision) is essential for the effect to work
4. Converting back to displayable RGB involves a creative, non-trivial mapping from the 4-channel state

**Key insight:** Most shaders in the library write `vec4(color, 1.0)` or `vec4(color, simple_alpha)`. These shaders write `vec4(field1, field2, field3, field4)` where the mapping to visual color happens as a separate step.

---

## RGBA-as-Data Effect Catalog

### Category A: Simulation-State RGBA

#### 1. `alpha-navier-stokes-paint.wgsl` — Full RGBA-Packed Fluid Simulation
**Concept:** The entire Navier-Stokes fluid state lives in ONE texture:
- R = velocity.x (signed f32 — can be negative for leftward flow)
- G = velocity.y (signed f32 — can be negative for upward flow)
- B = pressure (signed f32 — negative pressure = suction)
- A = dye density (0.0 = clear, 1.0+ = saturated)

**Why 4 channels matter:** A proper 2D incompressible fluid needs velocity (2 fields), pressure (1 field), and density (1 field) = 4 fields minimum. By packing into RGBA32FLOAT, we fit the entire simulation into the existing ping-pong pipeline without any extra textures.

**Implementation:**
```wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let dt = 0.016; // 60fps timestep
    
    // Read state from previous frame
    let state = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var vel = state.rg;
    var pressure = state.b;
    var density = state.a;
    
    // === ADVECTION (semi-Lagrangian) ===
    let backtraceUV = uv - vel * dt;
    let advected = textureSampleLevel(readTexture, u_sampler, backtraceUV, 0.0);
    vel = advected.rg;
    density = advected.a;
    
    // === DIFFUSION ===
    let viscosity = u.zoom_params.x * 0.001;
    let velL = textureSampleLevel(readTexture, u_sampler, uv - vec2(ps.x, 0.0), 0.0).rg;
    let velR = textureSampleLevel(readTexture, u_sampler, uv + vec2(ps.x, 0.0), 0.0).rg;
    let velD = textureSampleLevel(readTexture, u_sampler, uv - vec2(0.0, ps.y), 0.0).rg;
    let velU = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, ps.y), 0.0).rg;
    vel += viscosity * (velL + velR + velD + velU - 4.0 * vel);
    
    // === PRESSURE PROJECTION (Jacobi iteration) ===
    let pL = textureSampleLevel(readTexture, u_sampler, uv - vec2(ps.x, 0.0), 0.0).b;
    let pR = textureSampleLevel(readTexture, u_sampler, uv + vec2(ps.x, 0.0), 0.0).b;
    let pD = textureSampleLevel(readTexture, u_sampler, uv - vec2(0.0, ps.y), 0.0).b;
    let pU = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, ps.y), 0.0).b;
    let divergence = (velR.x - velL.x + velU.y - velD.y) * 0.5;
    pressure = (pL + pR + pD + pU - divergence) * 0.25;
    
    // Subtract pressure gradient from velocity (enforce incompressibility)
    vel -= vec2(pR - pL, pU - pD) * 0.5;
    
    // === MOUSE FORCE ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist);
    
    // Approximate mouse velocity from ripples or circular force
    let mouseForce = normalize(uv - mousePos) * mouseInfluence * -0.5 * mouseDown;
    vel += mouseForce * dt * 10.0;
    
    // Inject dye at ripple positions
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        let age = u.config.x - ripple.z;
        if (age < 2.0 && rippleDist < 0.05) {
            density += smoothstep(0.05, 0.0, rippleDist) * max(0.0, 1.0 - age);
        }
    }
    
    // === DECAY ===
    density *= 0.998; // Slow decay
    
    // === STORE STATE (all 4 channels are simulation data) ===
    textureStore(dataTextureA, gid.xy, vec4<f32>(vel, pressure, density));
    
    // === VISUALIZATION ===
    // Map fluid state to beautiful color
    let speed = length(vel);
    let hue = atan2(vel.y, vel.x) / 6.2832 + 0.5; // Direction → hue
    let sat = smoothstep(0.0, 0.01, speed);
    let val = density * 0.8 + 0.2;
    let displayColor = hsv2rgb(vec3<f32>(hue, sat * 0.8, val));
    
    // Tone-map and write display version
    textureStore(writeTexture, gid.xy, vec4<f32>(displayColor, density));
}
```

**Params:**
| Param | Name | Default | Range | Purpose |
|-------|------|---------|-------|---------|
| x | Viscosity | 0.3 | 0.0-1.0 | Fluid thickness |
| y | Dye Brightness | 0.7 | 0.0-1.0 | Dye visibility |
| z | Vorticity | 0.5 | 0.0-1.0 | Curl strength |
| w | Decay Rate | 0.5 | 0.0-1.0 | How fast dye fades |

---

#### 2. `alpha-reaction-diffusion-rgba.wgsl` — 4-Species Reaction-Diffusion
**Concept:** Standard Gray-Scott has 2 chemicals (A, B). This shader runs **4 chemicals** (one per RGBA channel) with inter-species reactions, creating far more complex and beautiful patterns than binary R-D.

**State packing:**
- R = Chemical A (activator 1)
- G = Chemical B (inhibitor 1)
- B = Chemical C (activator 2)
- A = Chemical D (inhibitor 2)

**Reaction rules:**
```wgsl
// 4-species reaction: A feeds B, C feeds D, B inhibits C, D inhibits A
let dA = dA_rate * laplacianA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
let dB = dB_rate * laplacianB + A * B * B - (feed + kill) * B;
let dC = dC_rate * laplacianC - C * D * D + feed2 * (1.0 - C) - crossInhibit * C * B;
let dD = dD_rate * laplacianD + C * D * D - (feed2 + kill2) * D;
```

**Visual output:** Each chemical maps to a color. The cross-species interactions create patterns impossible in 2-species systems: traveling waves, oscillating spots, labyrinthine channels with multiple colors.

---

#### 3. `alpha-magnetic-field-sim.wgsl` — Vector Field Simulation with RGBA Packing
**Concept:** Simulates a 2D magnetic field with sources and sinks:
- RG = Magnetic field vector B(x, y)
- B = Electric potential φ
- A = Current density J

Mouse clicks place magnetic sources (ripples with positive charge) and sinks (ripples with negative charge based on click count parity).

---

#### 4. `alpha-cellular-automata-state.wgsl` — Multi-State Cellular Automaton
**Concept:** Instead of binary (alive/dead) Game of Life, use 4 continuous states:
- R = Species 1 density (0.0 to 1.0+)
- G = Species 2 density
- B = Resource level
- A = Toxin concentration

Cells compete for resources, produce toxins, and evolve. The ecosystem dynamics produce endlessly varied patterns.

---

### Category B: HDR & Dynamic Range Artistry

#### 5. `alpha-hdr-bloom-chain.wgsl` — HDR Bloom with Alpha-as-Exposure
**Concept:** Instead of clamping bright pixels, let them bloom. The alpha channel stores the **exposure value** at each pixel — how many stops above the "white point" the pixel is. This allows a post-processing chain to create physically-correct bloom.

**Process:**
1. Sample input image
2. Identify pixels > 1.0 in any channel (overexposed)
3. Store the overexposure amount in alpha: `alpha = max(0.0, maxChannel - 1.0)`
4. Blur only the alpha-weighted excess (the bloom kernel)
5. Composite: `final = toneMap(color + bloomColor * bloomAlpha)`

```wgsl
// Step 1: Identify and store HDR information
let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
let maxChannel = max(color.r, max(color.g, color.b));
let exposure = max(0.0, maxChannel - 1.0); // Over-bright amount

// Step 2: Create bloom source (only over-exposed pixels contribute)
let bloomSource = color * step(1.0, maxChannel);

// Step 3: Gaussian-blur the bloom source (read neighbors)
var bloom = vec3<f32>(0.0);
for (var i = 0; i < 16; i++) {
    let angle = f32(i) * 6.2832 / 16.0;
    let radius = u.zoom_params.x * 0.1;
    let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
    let neighborUV = uv + offset / res;
    let neighbor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0);
    let neighborExposure = max(0.0, max(neighbor.r, max(neighbor.g, neighbor.b)) - 1.0);
    bloom += neighbor.rgb * neighborExposure;
}
bloom /= 16.0;

// Step 4: Composite with tone mapping
let hdrColor = color + bloom * u.zoom_params.y;
let ldrColor = toneMapACES(hdrColor);

textureStore(writeTexture, gid.xy, vec4<f32>(ldrColor, exposure));
```

---

#### 6. `alpha-spectral-decompose.wgsl` — Spectral Decomposition & Recomposition
**Concept:** Decompose the image into 4 spectral bands using oriented Gabor-like filters, store each band in RGBA, then recompose with user-controlled per-band gain. Creates "frequency equalizer for images" — boost fine detail, cut low frequency, shift mid-range hue.

**RGBA packing:**
- R = Low frequency band (large-scale structure)
- G = Mid-low frequency
- B = Mid-high frequency
- A = High frequency band (fine detail, edges)

**Recomposition:**
```wgsl
let bands = textureLoad(dataTextureC, coord, 0); // From decomposition pass
let recomposed = vec3<f32>(
    bands.r * u.zoom_params.x * 2.0 +  // Low freq gain
    bands.g * u.zoom_params.y * 2.0 +  // Mid freq gain
    bands.b * u.zoom_params.z * 2.0 +  // High freq gain
    bands.a * u.zoom_params.w * 2.0    // Ultra-high freq gain
);
```

---

#### 7. `alpha-luminance-history.wgsl` — Temporal Luminance History with Rolling Average
**Concept:** Alpha stores the **rolling average luminance** from the last N frames. This creates a "memory" of brightness — areas that were recently bright retain a glow even after darkening. Creates gorgeous light-painting effects with video input.

```wgsl
let currentLuma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
let prevAvgLuma = textureLoad(dataTextureC, coord, 0).a;
let decay = u.zoom_params.x; // 0.01 = long memory, 0.5 = short memory

let newAvgLuma = mix(prevAvgLuma, currentLuma, decay);
let glowAmount = max(0.0, newAvgLuma - currentLuma); // Glow where it WAS bright
let glowColor = color.rgb + vec3<f32>(1.0, 0.9, 0.7) * glowAmount * u.zoom_params.y;

textureStore(writeTexture, gid.xy, vec4<f32>(glowColor, newAvgLuma));
textureStore(dataTextureA, gid.xy, vec4<f32>(color.rgb, newAvgLuma));
```

---

### Category C: Alpha-Driven Visual Artistry

#### 8. `alpha-depth-fog-volumetric.wgsl` — Volumetric Fog with Depth-Dependent Alpha
**Concept:** Use depth texture to create volumetric fog layers. Alpha encodes the **optical depth** through the fog — a physically-based continuous value that determines both visibility and fog color.

**Beer-Lambert law for volumetric absorption:**
```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
let fogDensity = u.zoom_params.x;
let opticalDepth = fogDensity * (1.0 - depth) * 10.0; // Far = more fog
let transmittance = exp(-opticalDepth);

// Fog color shifts with depth (warm near, cool far)
let fogColor = mix(
    vec3<f32>(0.8, 0.7, 0.5),  // Warm near fog
    vec3<f32>(0.3, 0.4, 0.8),  // Cool far fog
    1.0 - depth
);

let sceneColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
let foggedColor = sceneColor * transmittance + fogColor * (1.0 - transmittance);

// Alpha = transmittance (how much of the scene is visible through fog)
textureStore(writeTexture, gid.xy, vec4<f32>(foggedColor, transmittance));
```

---

#### 9. `alpha-glass-refraction-layers.wgsl` — Multi-Layer Glass Refraction
**Concept:** Simulates looking through multiple layers of tinted glass. Each layer:
- Refracts the UV (displaces based on surface normal and IOR)
- Absorbs certain wavelengths (Beer's law per-channel)
- Reflects a fraction back (Fresnel)

Alpha stores the **accumulated transmittance** through all layers.

```wgsl
fn glassLayer(uv: vec2<f32>, normal: vec2<f32>, ior: f32, tint: vec3<f32>, thickness: f32) 
    -> GlassResult {
    // Snell's law refraction (2D approximation)
    let incident = vec2<f32>(0.0, 1.0); // Looking straight down
    let cosI = dot(incident, normal);
    let sinT2 = (1.0/ior) * (1.0/ior) * (1.0 - cosI*cosI);
    let refracted = uv + normal * (1.0/ior - 1.0) * thickness;
    
    // Fresnel reflectance (Schlick's approximation)
    let R0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
    let reflectance = R0 + (1.0 - R0) * pow(1.0 - abs(cosI), 5.0);
    
    // Beer's law absorption
    let absorption = exp(-tint * thickness * 5.0);
    
    return GlassResult(refracted, absorption, reflectance);
}
```

---

#### 10. `alpha-paint-thickness.wgsl` — Impasto Paint Thickness Simulation
**Concept:** The alpha channel represents paint thickness on a virtual canvas. Mouse drags deposit paint (thickness increases). The paint's visual appearance depends on thickness:
- Thin paint (alpha < 0.3): Transparent wash, canvas texture shows through
- Medium paint (alpha 0.3-0.7): Full color
- Thick paint (alpha > 0.7): Raised texture, catches specular highlights, casts micro-shadows

```wgsl
fn paintAppearance(color: vec3<f32>, thickness: f32, lightDir: vec2<f32>) -> vec3<f32> {
    // Thin: wash (multiply blend with canvas)
    let canvasColor = vec3<f32>(0.95, 0.92, 0.88);
    let washMix = smoothstep(0.0, 0.3, thickness);
    var result = mix(canvasColor * color, color, washMix);
    
    // Thick: specular highlight from impasto texture
    let thicknessMix = smoothstep(0.7, 1.5, thickness);
    let normal = estimateThicknessNormal(thickness); // From neighboring thickness values
    let specular = pow(max(0.0, dot(normal, lightDir)), 32.0);
    result += vec3<f32>(1.0, 0.98, 0.95) * specular * thicknessMix * 0.3;
    
    // Shadow from thick paint
    let shadow = smoothstep(1.0, 1.5, thickness) * 0.1;
    result *= 1.0 - shadow;
    
    return result;
}
```

---

#### 11. `alpha-fire-temperature.wgsl` — Fire Simulation with Temperature Field
**Concept:** RGBA = fire simulation state:
- R = Fuel amount (what's burning)
- G = Temperature (drives visual color via blackbody radiation)
- B = Smoke density
- A = Combustion age (how long this pixel has been burning)

Temperature field drives upward convection, fuel decreases as it burns, smoke rises and dissipates. Mouse adds fuel (click) or blows wind (drag).

---

#### 12. `alpha-watercolor-wetness.wgsl` — Watercolor Simulation with Wetness Map
**Concept:** Alpha = paper wetness. Wet areas allow pigment to flow and bleed. Dry areas lock color in place. Mouse drops water (increasing alpha), pigment flows from wet-to-dry boundaries. Creates authentic watercolor bleeding effects.

**RGBA packing:**
- RGB = Pigment concentration (color)
- A = Water level (0.0 = bone dry, 1.0 = soaking wet)

```wgsl
// Pigment flows toward lower water levels (capillary action)
let waterLevel = state.a;
let waterL = textureSampleLevel(readTexture, u_sampler, uv - vec2(ps.x, 0.0), 0.0).a;
let waterR = textureSampleLevel(readTexture, u_sampler, uv + vec2(ps.x, 0.0), 0.0).a;
let waterD = textureSampleLevel(readTexture, u_sampler, uv - vec2(0.0, ps.y), 0.0).a;
let waterU = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, ps.y), 0.0).a;

// Water flows downhill (gravity) and toward dry areas (capillary)
let waterGradX = (waterR - waterL) * 0.5;
let waterGradY = (waterU - waterD) * 0.5 - 0.01; // Gravity bias downward
let waterFlow = vec2<f32>(waterGradX, waterGradY);

// Advect pigment with water flow
let pigmentUV = uv - waterFlow * waterLevel * dt;
let advectedPigment = textureSampleLevel(readTexture, u_sampler, pigmentUV, 0.0).rgb;

// Dry over time
let newWater = waterLevel * (1.0 - u.zoom_params.z * 0.01);

// Mouse drops water
let mouseDist = length(uv - u.zoom_config.yz);
let mouseWater = smoothstep(0.08, 0.0, mouseDist) * u.zoom_config.w;
let finalWater = min(newWater + mouseWater, 1.5);

textureStore(writeTexture, gid.xy, vec4<f32>(advectedPigment, finalWater));
```

---

#### 13. `alpha-crystal-growth-phase.wgsl` — Crystal Growth with Phase Field
**Concept:** Phase-field model of crystal growth:
- R = Phase field (0 = liquid, 1 = solid)
- G = Temperature / supercooling
- B = Crystal orientation angle (determines facet direction)
- A = Impurity concentration (affects growth rate and color)

Creates beautiful dendritic crystal patterns that grow across the image, following temperature gradients set by the source image's luminance.

---

#### 14. `alpha-erosion-terrain.wgsl` — Hydraulic Erosion Simulation
**Concept:** Treats image luminance as a heightfield terrain:
- R = Height (from image luminance)
- G = Water depth
- B = Sediment carried by water
- A = Erosion amount (accumulated material removed)

Water flows downhill (computed from height gradient), picks up sediment, and deposits it in flat areas. Creates beautiful river valleys, deltas, and erosion patterns overlaid on the image.

---

#### 15. `alpha-aurora-bands.wgsl` — Aurora Borealis with Altitude Layers
**Concept:** Simulates aurora borealis with physically-motivated altitude layers:
- R = Emission intensity at 557.7nm (green oxygen line)
- G = Emission intensity at 630.0nm (red oxygen line)
- B = Emission intensity at 427.8nm (blue nitrogen line)
- A = Altitude/layer index (continuous f32 — determines which emission line dominates)

The aurora is rendered as overlapping curtains at different altitudes. Mouse position controls the "solar wind" direction. Ripples inject magnetic reconnection events that trigger bright auroral sub-storms.

```wgsl
fn auroraEmission(altitude: f32, particleEnergy: f32) -> vec3<f32> {
    // Oxygen green line: 100-200 km altitude
    let greenLine = exp(-pow((altitude - 150.0) / 30.0, 2.0)) * particleEnergy;
    // Oxygen red line: 200-400 km altitude
    let redLine = exp(-pow((altitude - 300.0) / 60.0, 2.0)) * particleEnergy * 0.5;
    // Nitrogen blue line: 80-100 km altitude
    let blueLine = exp(-pow((altitude - 90.0) / 15.0, 2.0)) * particleEnergy * 0.3;
    
    return vec3<f32>(redLine, greenLine, blueLine);
}
```

---

## HSV ↔ RGB Utility (Shared)

```wgsl
// ═══ CHUNK: hsv2rgb (Agent 4C) ═══
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x * 6.0;
    let s = hsv.y;
    let v = hsv.z;
    let c = v * s;
    let x = c * (1.0 - abs(h % 2.0 - 1.0));
    let m = v - c;
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3(x, 0.0, c); }
    else { rgb = vec3(c, 0.0, x); }
    return rgb + vec3(m);
}

// ═══ CHUNK: rgb2hsv (Agent 4C) ═══
fn rgb2hsv(rgb: vec3<f32>) -> vec3<f32> {
    let maxC = max(rgb.r, max(rgb.g, rgb.b));
    let minC = min(rgb.r, min(rgb.g, rgb.b));
    let delta = maxC - minC;
    var h = 0.0;
    if (delta > 0.0001) {
        if (maxC == rgb.r) { h = (rgb.g - rgb.b) / delta; }
        else if (maxC == rgb.g) { h = 2.0 + (rgb.b - rgb.r) / delta; }
        else { h = 4.0 + (rgb.r - rgb.g) / delta; }
    }
    h = fract(h / 6.0);
    let s = select(0.0, delta / maxC, maxC > 0.0001);
    return vec3<f32>(h, s, maxC);
}
```

---

## JSON Definition Template

```json
{
  "id": "alpha-navier-stokes-paint",
  "name": "Navier-Stokes Paint",
  "url": "shaders/alpha-navier-stokes-paint.wgsl",
  "category": "simulation",
  "description": "Full 2D incompressible fluid simulation packed into RGBA32FLOAT. Mouse creates vortices and injects dye. Velocity, pressure, and density are all computed in a single texture pass.",
  "tags": ["fluid", "simulation", "interactive", "mouse-driven", "navier-stokes", "psychedelic", "colorful"],
  "features": ["mouse-driven", "temporal", "rgba-state-machine"],
  "params": [
    { "id": "viscosity", "name": "Viscosity", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01 },
    { "id": "dyeBrightness", "name": "Dye Brightness", "default": 0.7, "min": 0.0, "max": 1.0, "step": 0.01 },
    { "id": "vorticity", "name": "Vorticity", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01 },
    { "id": "decayRate", "name": "Decay Rate", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01 }
  ]
}
```

---

## Implementation Guidelines

### Reading Previous Frame State
```wgsl
// dataTextureC holds the previous frame's dataTextureA output
let prevState = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
// OR for interpolated reads:
let prevState = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
```

### Writing State + Display
```wgsl
// Write simulation state to dataTextureA (persists to next frame via dataTextureC)
textureStore(dataTextureA, gid.xy, vec4<f32>(vel, pressure, density));

// Write display-ready color to writeTexture
let displayColor = stateToVisual(vel, pressure, density);
textureStore(writeTexture, gid.xy, vec4<f32>(displayColor, density));
```

### Depth Pass-Through
```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
```

---

## Deliverables

1. **15 WGSL shader files** in `public/shaders/alpha-*.wgsl`
2. **15 JSON definition files** in appropriate `shader_definitions/` category
3. **Each shader must:**
   - Use ALL 4 RGBA channels for meaningful data (document what each stores)
   - Require f32 precision (demonstrate why 8-bit would break it)
   - Include a visual mapping function (state → displayable color)
   - Be mouse-interactive (zoom_config and/or ripples)
   - Include at least 2 controllable params
4. **Utility chunks** added to `swarm-outputs/chunk-library.md`:
   - `hsv2rgb`, `rgb2hsv`
   - `toneMapACES` (share with Agent 3C)
   - `blackbodyColor`

---

## Success Criteria

- [ ] All 15 shaders compile without WGSL errors
- [ ] Each shader documents what RGBA channels store (in header comment)
- [ ] No shader has `alpha = 1.0` hardcoded
- [ ] Each shader's visual output is clearly different from standard alpha-blending effects
- [ ] Simulations are stable (no NaN/Inf divergence after 1000+ frames)
- [ ] Performance: 30+ FPS at 2048×2048
- [ ] Mouse interaction creates visible, immediate response
- [ ] JSON definitions include params, tags, description
