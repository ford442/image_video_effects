# Lighting, Plasma & Glow Shader Upgrade Plan

## Executive Summary

This document outlines computational and artistic upgrades for 35 shaders across the LIGHTING, PLASMA, and GLOW categories in Pixelocity. The goal is to elevate visual fidelity by incorporating physically-based lighting phenomena while maintaining real-time performance.

---

## Current Shader Inventory Analysis

### Category Breakdown

| Category | Count | Bytes Range | Key Characteristics |
|----------|-------|-------------|---------------------|
| **Neon Effects** | 20 | 2,959 - 5,063 | Edge detection, Sobel filters, mouse interaction |
| **Volumetric** | 5 | 3,478 - 7,956 | Ray marching, radial blur, 3D noise |
| **Lens/Optics** | 4 | 4,410 - 5,638 | Anamorphic flares, ghosting, chromatic aberration |
| **Plasma/Nebula** | 3 | 5,390 - 10,202 | FBM noise, domain warping, metaballs |
| **Holographic** | 3 | 3,524 - 4,848 | Scanlines, glitch effects, RGB shift |

### Current Technical Patterns

**Strengths:**
- Consistent Sobel edge detection across neon family
- Effective use of FBM (Fractal Brownian Motion) for organic patterns
- Proper radial blur implementation for god rays
- Multi-pass architecture for complex effects

**Opportunities:**
- Color generation uses simple cosine-based HSV (aesthetically limited)
- Glow falloff uses basic exponential decay (not physically accurate)
- Missing spectral rendering for prism effects
- No temperature-based blackbody radiation
- Fresnel implementations are simplified Schlick approximations only

---

## Scientific Concept Integration Roadmap

### 1. Blackbody Radiation Curves for Realistic Glow

**Applicable Shaders:**
- `neon-pulse`, `neon-light`, `neon-strings`, `neon-echo`
- `plasma`, `stellar-plasma`, `volumetric-cloud-nebula`
- `divine-light`, `divine-light-gpt52`

**Computational Approach:**

```
Current: hue = fract(time * 0.2 + dist * 2.0)
         color = vec3(0.5 + 0.5 * cos(6.28318 * (hue + offset)))

Upgrade:  temperature = mix(1000.0, 12000.0, param) // Kelvin
         color = blackbody(temperature)
```

**Planck's Law Approximation for GPU:**

Use a polynomial approximation for efficiency:

```
xyz = vec3(
    (temperature <= 4000) ? -0.2661239e9/t^3 - 0.2343580e6/t^2 + 0.8776956e3/t + 0.179910 : ...,
    ...
)
```

Or simpler: Precompute 256-entry LUT texture for blackbody curve lookup.

**Artistic Impact:**
- Warm candlelight (1800K) to cool skylight (12000K) range
- Realistic metal heating visualization
- Scientifically accurate star/plasma temperatures
- Removes "cartoon" look from current cosine-based colors

**Implementation Notes:**
- Add `blackbody_temperature` parameter (0.0-1.0 maps to 1000K-15000K)
- Combine with existing hue shift for artistic override
- Use in `neon-strings` for "heated wire" effect
- Apply to `stellar-plasma` for accurate star colors

---

### 2. Volumetric Lighting (Ray Marching, Dust Scattering)

**Applicable Shaders:**
- `volumetric-god-rays` (current: 64 samples, basic radial blur)
- `volumetric-cloud-nebula` (current: 60 steps, absorption model)
- `volumetric-rainbow-clouds` (current: 3 layers, depth-based)
- `divine-light`, `divine-light-gpt52`

**Current Limitations:**
- Fixed 32-64 ray samples (no adaptive stepping)
- Missing Mie scattering phase function
- No dust density variation
- Homogeneous medium assumption

**Upgrade: Henyey-Greenstein Phase Function**

```
float hg_phase(float cos_theta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5) * (1.0 / 4.0 * PI);
}
```

Where `g` is asymmetry parameter:
- g = -0.5: Back scattering (sunsets)
- g = 0.0: Isotropic (fog)
- g = 0.7: Forward scattering (god rays through dust)

**Upgrade: Adaptive Step Sizing**

```
// Current: fixed step
for (i = 0; i < 60; i++) { t += 0.15; }

// Upgrade: exponential stepping for depth efficiency
float t = 0.1;
for (i = 0; i < steps && t < tMax; i++) {
    float density = sample_cloud(p);
    t += stepSize * (1.0 + t * 0.1) / (density * densityMul + 0.1);
}
```

**Dust Density Texture:**
- Use existing `dataTextureA` as 3D noise lookup
- Tile 2D slice with temporal offset for animated dust
- Parameter: `dust_density` (0.0-1.0)

**Artistic Impact:**
- `volumetric-god-rays`: Crepuscular rays through cathedral windows
- `volumetric-cloud-nebula`: Self-shadowing volumetric nebulae
- `divine-light`: Dust motes in spiritual light beams

---

### 3. Caustics from Wave Optics

**Applicable Shaders:**
- `photonic-caustics` (already advanced - needs refinement)
- New shader opportunity: `underwater-caustics`
- New shader opportunity: `glass-caustics`

**Current Implementation Analysis:**
`photonic-caustics.wgsl` already implements:
- Photon tracing (32 photons)
- Chromatic dispersion (3 wavelength IOR)
- Fresnel via Schlick
- Temporal accumulation

**Upgrade Path:**

**A. Keller's Photon Mapping Approximation**

Replace random photon distribution with low-discrepancy sequence:

```
// Current: random angle via hash
// Upgrade: Hammersley sequence for better coverage
float phi = (float(i) + 0.5) / float(PHOTON_COUNT) * 2.0 * PI * golden_ratio;
```

**B. Wavefront Curvature for Caustic Intensity**

Current convergence check is simplified. Add:

```
// Compute Jacobian of ray transformation for intensity
float jacobian = length(cross(dp/du, dp/dv));
intensity *= 1.0 / (jacobian + epsilon);
```

**C. Caustic Pattern Synthesis (Performance Alternative)**

For real-time performance on lower-end GPUs, replace photon tracing with procedural caustics:

```
// Voronoi-based caustic approximation
float caustic(vec2 uv) {
    vec2 p = uv * scale;
    float c = 0.0;
    for (int i = 0; i < 3; i++) {
        vec2 voronoi = voronoi(p + time * speed);
        c += exp(-voronoi.y * sharpness) * intensity;
        p *= 2.0;
    }
    return c;
}
```

**Artistic Impact:**
- Swimming pool water caustics on submerged objects
- Light through wine glass creating dancing patterns
- Diamond sparkle with spectral dispersion

---

### 4. Fresnel Equations for Edge Highlighting

**Applicable Shaders:**
- All 20 neon shaders (currently use simple edge detection)
- `holographic-projection`, `holographic-prism`
- `anamorphic-flare`

**Current State:**
Most neon shaders use Sobel edge detection:

```
let edgeX = length(l - r);
let edgeY = length(t - b);
let edge = sqrt(edgeX * edgeX + edgeY * edgeY);
```

**Upgrade: Full Fresnel-Schlick with IOR Control**

```
// View-dependent edge glow
vec3 viewDir = normalize(vec3(0.0, 0.0, 1.0));
vec3 normal = compute_normal_from_depth(uv);
float cos_theta = dot(viewDir, normal);

// Schlick approximation with IOR
float r0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
float fresnel = r0 + (1.0 - r0) * pow(1.0 - cos_theta, 5.0);

// Anisotropic roughness for brushed metal look
float roughness = mix(0.01, 0.5, param);
fresnel *= ggx_distribution(cos_theta, roughness);
```

**Normal from Depth Enhancement:**

```
// Current uses immediate neighbors
// Upgrade: larger kernel for smoother normals
vec3 compute_normal_from_depth(vec2 uv) {
    float c = sample_depth(uv);
    float l = sample_depth(uv + vec2(-2.0, 0.0) * texel);
    float r = sample_depth(uv + vec2(2.0, 0.0) * texel);
    float t = sample_depth(uv + vec2(0.0, -2.0) * texel);
    float b = sample_depth(uv + vec2(0.0, 2.0) * texel);
    
    // Sobel filter for normal
    float dx = (r - l) * 0.5;
    float dy = (b - t) * 0.5;
    return normalize(vec3(-dx, -dy, 0.01));
}
```

**Artistic Applications:**
- `neon-edges`: Glass-like edge glow with view dependency
- `holographic-projection`: Fresnel rim lighting for sci-fi UI
- `neon-topology`: Terrain edge highlighting with material IOR

---

### 5. Phosphorescence and Persistence

**Applicable Shaders:**
- `neon-echo` (already has persistence - upgradeable)
- `neon-cursor-trace`
- `neon-contour-drag`
- `neon-pulse-stream`

**Physical Model:**

Phosphorescence follows exponential decay with color shifting:

```
// Current: simple fade
fadedHistory = history * (1.0 - decay * 0.1);

// Upgrade: wavelength-dependent decay (physics-based)
// Blue phosphors fade faster than green, green faster than red
vec3 phosphor_decay(vec3 color, float dt, vec3 decay_rates) {
    // Typical phosphor: P22 (CRT) - red: 1ms, green: 10ms, blue: 100ms
    // Normalize to frame time
    return color * exp(-dt * decay_rates);
}

// Chromatic phosphorescence color shift
// As phosphor fades, color shifts toward red (lower energy)
vec3 afterglow = phosphor_color * exp(-age * decay_rate);
afterglow = mix(afterglow, vec3(1.0, 0.3, 0.0), 1.0 - exp(-age * 0.5));
```

**Phosphor Types (User Selectable):**

| Type | Decay RGB | Color Shift | Use Case |
|------|-----------|-------------|----------|
| P1 (Zinc Sulfide) | (0.1, 0.15, 0.3) | Green to yellow | Oscilloscope |
| P22 (CRT) | (0.5, 0.3, 0.1) | White to amber | Retro monitor |
| P31 (Persistent) | (0.05, 0.08, 0.12) | Green | Radar |
| P45 (Blue) | (0.2, 0.25, 0.4) | Blue to cyan | Medical imaging |

**Implementation in `neon-echo`:**

```
// Add to params: phosphor_type (0-3)
vec3 decay_rates = get_phosphor_params(param);
vec3 faded = phosphor_decay(history.rgb, delta_time, decay_rates);

// Add saturation shift during decay (phosphor "burn-in" look)
vec3 hsv = rgb_to_hsv(faded);
hsv.y *= 1.0 + age * 0.1; // Increase saturation with age
faded = hsv_to_rgb(hsv);
```

**Artistic Impact:**
- `neon-echo`: Authentic CRT monitor trails
- `neon-cursor-trace`: Oscilloscope-style phosphor glow
- `neon-pulse-stream`: Radar sweep persistence

---

### 6. Fluorescence and Excitation Spectra

**Applicable Shaders:**
- `neon-pulse`, `neon-pulse-edge`, `neon-edge-pulse`
- `neon-flashlight`
- `volumetric-rainbow-clouds`

**Physical Model:**

Fluorescence absorbs high-energy (UV/blue) and re-emits lower energy:

```
// Stokes shift: emission is always longer wavelength than excitation
float excitation = dot(input_color, vec3(0.1, 0.3, 0.6)); // Weight toward blue/UV
float quantum_yield = 0.8; // Efficiency
float stokes_shift = 0.15; // Wavelength shift amount

// Absorption spectrum (Gaussian)
float absorption = gaussian(wavelength, peak_absorption, width);

// Emission spectrum (Gaussian, shifted)
float emission = gaussian(wavelength, peak_absorption + stokes_shift, width * 1.2);

// Fluorescence output
vec3 fluorescence = input_color * absorption * quantum_yield * emission_color;
```

**UV Light Source Mode:**

```
// When in "UV flashlight" mode
vec3 uv_light = vec3(0.0, 0.0, 1.0) * intensity;
vec3 visible_light = vec3(0.0);

// Only UV excites fluorescence
float excitation = dot(uv_light, vec3(0.1, 0.2, 0.7)); // UV absorption

// Fluorescent materials emit visible light
vec3 emission = fluorescent_response(excitation, material_type);
```

**Fluorescent Dye Library:**

| Dye | Absorption Peak | Emission Peak | Color |
|-----|-----------------|---------------|-------|
| Fluorescein | 494nm (blue) | 521nm (green) | Bright green |
| Rhodamine B | 543nm (green) | 565nm (orange) | Pink-orange |
| DAPI | 358nm (UV) | 461nm (blue) | Blue |
| GFP | 488nm (blue) | 507nm (green) | Yellow-green |

**Artistic Applications:**
- `neon-flashlight`: UV flashlight revealing hidden fluorescent patterns
- `neon-pulse`: Biological fluorescence microscopy look
- `volumetric-rainbow-clouds`: Atmospheric fluorescence (airglow)

---

### 7. Electroluminescence Patterns

**Applicable Shaders:**
- `neon-edges`, `neon-light`, `neon-poly-grid`
- `neon-topology`

**Physical Model:**

Electroluminescence creates characteristic "corona" discharge patterns:

```
// Electric field strength from voltage gradient
float field_strength = length(gradient(potential_field, uv));

// Dielectric breakdown threshold
float threshold = mix(1000.0, 5000.0, air_density); // V/mm

// Lichtenberg figure branching
float lichtenberg(vec2 uv, vec2 seed) {
    float f = 0.0;
    vec2 p = uv;
    for (int i = 0; i < 8; i++) {
        p += noise(p * 10.0 + seed) * 0.1;
        f += noise(p * pow(2.0, float(i)));
    }
    return smoothstep(0.6, 0.7, f);
}

// Corona discharge around high-field points
float corona(vec2 uv, vec2 center, float voltage) {
    float dist = distance(uv, center);
    float field = voltage / (dist * dist); // 1/r^2 falloff
    
    // Ionization glow
    float glow = exp(-dist * 10.0) * smoothstep(threshold * 0.8, threshold, field);
    
    // Streamers (fractal branches)
    float streamers = lichtenberg(uv, center) * smoothstep(threshold, threshold * 1.2, field);
    
    return glow + streamers;
}
```

**Plasma Ball Simulation:**

The existing `plasma.wgsl` uses metaballs. Upgrade with:

```
// Add to PlasmaBall struct
float voltage;
float frequency; // For AC electroluminescence flicker

// Filament simulation
vec3 plasma_filament(vec2 from, vec2 to, float voltage) {
    vec2 mid = (from + to) * 0.5;
    float dist = distance(uv, mid);
    
    // Wandering filament path
    float path_noise = fbm(uv * 20.0 + time * 5.0);
    float filament = exp(-dist * 50.0) * path_noise;
    
    // Ionization color (temperature-based)
    float temp = 4000.0 + voltage * 1000.0;
    vec3 color = blackbody(temp);
    
    return color * filament * voltage;
}
```

**Artistic Applications:**
- `neon-edges`: Electric arc along detected edges
- `neon-poly-grid`: Tesla coil discharge between grid points
- `neon-topology`: Lightning simulation on terrain heightmaps

---

### 8. Bioluminescence Chemical Reactions

**Applicable Shaders:**
- `neon-cursor-trace`
- `neon-ripple-split`
- `neon-contour-interactive`

**Physical Model:**

Bioluminescence involves luciferin-luciferase reaction with oxygen:

```
// Reaction kinetics
float luciferin = initial_concentration * exp(-time / decay_constant);
float oxygen = saturate(oxygen_supply - consumption_rate * time);
float enzyme_activity = gaussian(temperature, optimal_temp, temp_width);

// Light output (Michaelis-Menten kinetics)
float reaction_rate = (Vmax * luciferin) / (Km + luciferin);
float light_output = reaction_rate * oxygen * enzyme_activity;

// Bioluminescence color (species-dependent)
vec3 firefly_glow = vec3(0.55, 0.95, 0.15); // Yellow-green (550-570nm)
vec3 jellyfish_glow = vec3(0.2, 0.6, 1.0);  // Blue (480nm)
vec3 dinoflagellate = vec3(0.1, 0.8, 0.6); // Cyan (474nm)

// Reaction fronts (traveling waves)
float reaction_front(vec2 uv, vec2 source, float time) {
    float dist = distance(uv, source);
    float wave = sin(dist * 50.0 - time * 10.0);
    float envelope = exp(-dist * 3.0) * exp(-time * 0.5);
    return saturate(wave * envelope);
}
```

**Luciferin Diffusion Simulation:**

```
// Use dataTextureA as concentration field
// Advection-diffusion equation
vec2 velocity = vec2(0.0); // Or flow field from noise
float diffusion_coefficient = 0.1;
float decay = 0.95;

// Update concentration
float concentration = textureLoad(dataTextureC, coord).r;
float laplacian = sample_neighbors(dataTextureC, coord) - 4.0 * concentration;
concentration += diffusion_coefficient * laplacian;
concentration *= decay;

// Light emitted where luciferin meets oxygen (mouse interaction)
float oxygen = smoothstep(0.3, 0.0, distance(uv, mouse));
float light = concentration * oxygen * enzyme_activity;
```

**Artistic Applications:**
- `neon-cursor-trace`: Firefly trail following mouse
- `neon-ripple-split`: Dinoflagellate bioluminescence in water
- `neon-contour-interactive`: Glowing bacteria responding to touch

---

### 9. Neon Discharge Tube Physics

**Applicable Shaders:**
- All 20 neon shaders (base upgrade)
- `neon-light`, `neon-pulse`, `neon-pulse-stream`

**Physical Model:**

Real neon signs exhibit specific electrical and optical characteristics:

```
// Gas discharge color (noble gas dependent)
vec3 neon_color(float gas_mixture) {
    // 0.0 = pure neon (red-orange)
    // 0.5 = argon-mercury (blue)
    // 1.0 = helium (pink-white)
    vec3 neon = vec3(1.0, 0.2, 0.0);     // 640nm
    vec3 argon = vec3(0.0, 0.4, 1.0);    // 450nm
    vec3 helium = vec3(1.0, 0.8, 0.9);   // White-pink
    
    return mix(mix(neon, argon, saturate(gas_mixture * 2.0)), 
               helium, saturate((gas_mixture - 0.5) * 2.0));
}

// Cathode dark space (Fresnel near tube walls)
float cathode_dark_space(float dist_from_wall, float pressure) {
    // Thickness increases with decreasing pressure
    float thickness = 1.0 / pressure * 0.01;
    return smoothstep(0.0, thickness, dist_from_wall);
}

// Striations (Faraday dark spaces)
float striations(float distance_along_tube, float pressure) {
    float wavelength = 0.1 / pressure; // Striation spacing
    return 0.8 + 0.2 * sin(distance_along_tube / wavelength * 2.0 * PI);
}

// 60Hz flicker (AC powered)
float ac_flicker(float time, float depth) {
    float ac = abs(sin(time * 60.0 * 2.0 * PI)); // 60Hz rectified
    float persistence = exp(-depth * 0.5); // Inner tube brighter
    return mix(0.7, 1.0, ac) * persistence;
}
```

**Neon Tube Geometry Shader:**

```
// Distance to line segment (for tube rendering)
float sd_segment(vec2 uv, vec2 a, vec2 b) {
    vec2 pa = uv - a;
    vec2 ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Neon tube with proper glow falloff
vec3 neon_tube(vec2 uv, vec2 start, vec2 end, float width, vec3 color) {
    float dist = sd_segment(uv, start, end);
    
    // Core (saturated)
    float core = smoothstep(width * 0.3, width * 0.2, dist);
    
    // Glow (inverse square falloff - physically correct)
    float glow = 1.0 / (1.0 + dist * dist * 100.0 / (width * width));
    
    // Combine with striations along tube length
    float t = length(uv - start) / length(end - start);
    float striation = striations(t, 0.5);
    
    return color * (core + glow * 0.5) * striation * ac_flicker(time, dist);
}
```

**Artistic Applications:**
- `neon-light`: True-to-life neon sign simulation
- `neon-pulse`: Pulsing neon with realistic AC flicker
- `neon-pulse-stream`: Animated neon tubing with Faraday striations

---

### 10. Lens Flare Hexagonal Diffraction (Aperture Blades)

**Applicable Shaders:**
- `dynamic-lens-flares` (current: circular ghosts only)
- `anamorphic-flare`
- `lens-flare-brush`

**Current Limitations:**
- Ghosts are circular (soft circles)
- No aperture blade diffraction
- Missing rainbow diffraction spikes

**Upgrade: Aperture Diffraction Shape:**

```
// Distance to n-gon (aperture shape)
float sd_ngon(vec2 uv, float radius, int n) {
    float angle = atan2(uv.y, uv.x);
    float sector = 2.0 * PI / float(n);
    float local_angle = mod(angle, sector) - sector * 0.5;
    float dist = radius * cos(PI / float(n)) / cos(local_angle);
    return length(uv) - dist;
}

// Ghost with aperture shape
float aperture_ghost(vec2 uv, vec2 center, float size, int blades) {
    vec2 local = uv - center;
    float dist = sd_ngon(local, size, blades);
    return smoothstep(0.02, 0.0, dist);
}

// Diffraction spikes (starburst)
float diffraction_spikes(vec2 uv, vec2 light_pos, int blades) {
    vec2 dir = uv - light_pos;
    float angle = atan2(dir.y, dir.x);
    float sector = 2.0 * PI / float(blades);
    
    // Spike intensity varies with angle
    float spike = pow(abs(cos(angle * float(blades) * 0.5)), 16.0);
    
    // Radial falloff
    float falloff = 1.0 / (1.0 + length(dir) * 2.0);
    
    return spike * falloff;
}
```

**Chromatic Aberration in Flares:**

```
// Current: simple RGB shift
// Upgrade: wavelength-dependent refraction through lens elements
vec3 chromatic_flare(vec2 uv, vec2 center) {
    vec3 color;
    float dist = length(uv - center);
    
    // Different focal lengths for R, G, B
    float focal_r = 50.0 * 1.001; // Slight variation
    float focal_g = 50.0;
    float focal_b = 50.0 * 0.999;
    
    vec2 offset_r = (uv - center) * (focal_r / focal_g - 1.0) * aberration;
    vec2 offset_b = (uv - center) * (focal_b / focal_g - 1.0) * aberration;
    
    color.r = sample_flare(uv + offset_r, center);
    color.g = sample_flare(uv, center);
    color.b = sample_flare(uv + offset_b, center);
    
    return color;
}
```

**Artistic Applications:**
- `dynamic-lens-flares`: Cinematic anamorphic flares with 8-point stars
- `anamorphic-flare`: Accurate oval bokeh from anamorphic lenses
- `lens-flare-brush`: Paintable lens artifacts

---

### 11. Anisotropic Specular Highlights

**Applicable Shaders:**
- `holographic-projection`, `holographic-prism`, `holographic-edge-ripple`
- `photonic-caustics`

**Physical Model:**

Anisotropic reflection stretches highlights along surface grain:

```
// Ward anisotropic model
float ward_anisotropic(vec3 L, vec3 V, vec3 N, vec3 T, float ax, float ay) {
    vec3 H = normalize(L + V);
    float TH = dot(T, H);
    float BH = dot(cross(N, T), H);
    float NH = max(dot(N, H), 0.0);
    float NV = max(dot(N, V), 0.0);
    float NL = max(dot(N, L), 0.0);
    
    float exponent = -2.0 * (TH * TH / (ax * ax) + BH * BH / (ay * ay));
    float denom = 4.0 * PI * ax * ay * sqrt(NV * NL);
    
    return exp(exponent) / denom;
}

// Tangent direction from brush strokes or surface pattern
vec3 compute_tangent(vec2 uv) {
    // From texture or procedural
    float angle = fbm(uv * 5.0) * 2.0 * PI;
    return vec3(cos(angle), sin(angle), 0.0);
}

// Holographic rainbow effect
vec3 holographic_color(vec3 view, vec3 normal, float film_thickness) {
    // Thin film interference
    float cos_theta = dot(view, normal);
    float optical_path = 2.0 * film_thickness * sqrt(1.0 - cos_theta * cos_theta);
    
    // Phase shift for interference
    float phase = 2.0 * PI * optical_path / wavelength;
    
    // Constructive interference for each wavelength
    vec3 phase_rgb = vec3(
        2.0 * PI * optical_path / 650.0, // Red
        2.0 * PI * optical_path / 530.0, // Green
        2.0 * PI * optical_path / 460.0  // Blue
    );
    
    return 0.5 + 0.5 * cos(phase_rgb);
}
```

**Holographic Film Simulation:**

```
// Authentic holographic material look
vec3 holographic_film(vec2 uv, vec3 view_dir, vec3 normal) {
    // Rainbow color shift based on view angle
    float angle = dot(view_dir, normal);
    vec3 rainbow = rainbow_gradient(angle * 2.0 + time * 0.1);
    
    // Micro-prismatic structure (bumps)
    float micro_structure = noise(uv * 1000.0) * 0.1;
    angle += micro_structure;
    
    // Specular highlight with anisotropic stretch
    vec3 tangent = compute_tangent(uv);
    float specular = ward_anisotropic(light_dir, view_dir, normal, tangent, 0.1, 0.01);
    
    return rainbow * (0.5 + specular * 2.0);
}
```

**Artistic Applications:**
- `holographic-projection`: Authentic security hologram look
- `holographic-prism`: CD/DVD rainbow diffraction
- `holographic-edge-ripple`: Liquid crystal display effects

---

### 12. Subsurface Scattering Approximation

**Applicable Shaders:**
- `neon-edge-diffusion`
- `neon-echo`
- `volumetric-cloud-nebula`

**Physical Model:**

SSS simulates light penetrating and bouncing within materials:

```
// Burley's normalized diffusion model (simplified)
float subsurface_scatter(float dist, float scatter_distance) {
    // Sum of two exponentials
    float d = dist / scatter_distance;
    float s1 = exp(-d * 3.0);
    float s2 = exp(-d * 1.0);
    return (s1 + s2) * 0.5;
}

// Pre-integrated skin diffusion (for wax/plant material look)
vec3 preintegrated_sss(vec3 normal, vec3 light, float thickness) {
    float NdotL = dot(normal, light);
    
    // LUT-based lookup would be ideal
    // Approximation:
    float wrap = 0.5;
    float scatter = saturate((NdotL + wrap) / (1.0 + wrap));
    
    // Color-bleed (red travels further in skin-like materials)
    vec3 scatter_color = vec3(1.0, 0.6, 0.4); // Red-shifted
    return mix(vec3(scatter), scatter_color * scatter, thickness);
}

// Back-lighting (translucency)
float translucency(vec3 normal, vec3 light, float thickness) {
    float back_light = saturate(-dot(normal, light));
    return exp(-thickness * 5.0) * back_light;
}
```

**Jade/Wax Material Shader:**

```
// Use depth as thickness proxy
float thickness = 1.0 - sample_depth(uv);

// Diffuse base
vec3 diffuse = base_color * max(dot(normal, light), 0.0);

// Subsurface contribution
vec3 sss = subsurface_color * subsurface_scatter(distance, scatter_dist);

// Rim lighting from translucency
float rim = translucency(normal, view, thickness);
vec3 translucency_glow = base_color * rim * 2.0;

// Combine
vec3 final = diffuse + sss + translucency_glow;
```

**Artistic Applications:**
- `neon-edge-diffusion`: Wax candle glow effect
- `neon-echo`: Translucent material trails
- `volumetric-cloud-nebula`: Back-lit cloud edges

---

## Implementation Priority Matrix

### Phase 1: Quick Wins (High Impact, Low Complexity)

| Shader | Upgrade | Est. Lines | Performance |
|--------|---------|------------|-------------|
| `neon-pulse` | Blackbody temperature | +15 | No impact |
| `neon-light` | Neon discharge physics | +30 | +5% GPU |
| `volumetric-god-rays` | Henyey-Greenstein phase | +20 | No impact |
| `anamorphic-flare` | Aperture blade shapes | +25 | +2% GPU |
| `neon-echo` | Phosphor decay types | +40 | +3% GPU |

### Phase 2: Medium Effort (Enhanced Fidelity)

| Shader | Upgrade | Est. Lines | Performance |
|--------|---------|------------|-------------|
| `photonic-caustics` | Wavefront curvature | +50 | +15% GPU |
| `neon-edges` | Fresnel with IOR | +35 | +5% GPU |
| `holographic-projection` | Anisotropic highlights | +45 | +8% GPU |
| `neon-topology` | Electroluminescence | +60 | +10% GPU |
| `plasma` | Enhanced metaball physics | +40 | +5% GPU |

### Phase 3: Advanced Features (Maximum Realism)

| Shader | Upgrade | Est. Lines | Performance |
|--------|---------|------------|-------------|
| `volumetric-cloud-nebula` | Full SSS + dust scattering | +80 | +25% GPU |
| `neon-cursor-trace` | Bioluminescence simulation | +70 | +15% GPU |
| `dynamic-lens-flares` | Full lens simulation | +100 | +20% GPU |
| `neon-ripple-split` | Fluorescence + wave optics | +60 | +12% GPU |

---

## New Shader Opportunities

### 1. `blackbody-radiator`
**Concept:** Interactive blackbody radiation visualization
**Features:**
- Temperature slider (1000K-20000K)
- Wien's displacement law visualization
- Stefan-Boltzmann intensity curve
- UV/visible/IR spectrum indicator

### 2. `aurora-borealis`
**Concept:** Volumetric aurora with solar wind simulation
**Features:**
- Ray-marched curtains of light
- Oxygen (green/red) and nitrogen (blue/purple) emission
- Magnetic field line influence
- Real-time solar wind intensity parameter

### 3. `candle-flame`
**Concept:** Physically-based candle with blackbody emission
**Features:**
- Temperature gradient (wick 1400K to outer 800K)
- Soot particle illumination
- Flicker physics (air disturbance model)
- Wax pool caustics

### 4. `metal-heating`
**Concept:** Steel heating visualization
**Features:**
- Temperature gradient from black to white heat
- Accurate oxidation colors (straw, brown, purple, blue)
- Heat haze distortion
- Spark emission at high temperatures

### 5. `fiber-optic-cable`
**Concept:** Total internal visualization
**Features:**
- Fresnel reflection at cable boundaries
- Chromatic dispersion through glass
- Evanescent wave glow at bends
- Attenuation over distance

---

## Technical Implementation Notes

### Shared Utilities

Create `public/shaders/lib/lighting_physics.wgsl`:

```wgsl
// Blackbody radiation
fn blackbody(temperature: f32) -> vec3<f32> { ... }

// Fresnel equations
fn fresnel_full(cos_theta: f32, ior: f32) -> vec3<f32> { ... }

// Phase functions
fn henyey_greenstein(cos_theta: f32, g: f32) -> f32 { ... }

// Color space conversions
fn xyz_to_rgb(xyz: vec3<f32>) -> vec3<f32> { ... }
fn srgb_to_linear(srgb: vec3<f32>) -> vec3<f32> { ... }
```

*Note: WGSL does not support #include - consider code generation or copy-paste utility functions.*

### Parameter Standardization

| Param | Range | Usage |
|-------|-------|-------|
| `zoom_params.x` | 0.0-1.0 | Primary effect intensity/strength |
| `zoom_params.y` | 0.0-1.0 | Secondary parameter (speed/scale) |
| `zoom_params.z` | 0.0-1.0 | Tertiary parameter (glow/density) |
| `zoom_params.w` | 0.0-1.0 | Quaternary parameter (color/temperature) |

### Performance Budgets

- **Neon shaders:** Target <0.5ms per frame at 1080p
- **Volumetric shaders:** Target <2.0ms per frame with 64 samples
- **Caustics shaders:** Target <1.5ms with 32 photons
- **Plasma shaders:** Target <1.0ms with 50 metaballs

---

## Artistic Vision Summary

### Neon Family Evolution
Transform from "digital outline" aesthetic to "authentic light emission":
- **Before:** Flat, uniform color outlines
- **After:** Temperature-varying, flickering, phosphor-persistent light sources

### Volumetric Family Evolution
Transform from "screen-space blur" to "atmospheric simulation":
- **Before:** Radial blur with tint
- **After:** Physics-based scattering with dust and phase functions

### Optical Family Evolution
Transform from "overlay effects" to "lens simulation":
- **Before:** Circular sprites with glow
- **After:** Aperture-shaped ghosts with chromatic aberration and diffraction

### Plasma Family Evolution
Transform from "procedural noise" to "energetic phenomena":
- **Before:** Domain-warped FBM clouds
- **After:** Electrodynamic plasma with field lines and discharge physics

---

## Conclusion

This upgrade plan provides a roadmap for transforming Pixelocity's lighting shaders from visually pleasing approximations to physically-grounded simulations. The key principles:

1. **Physics-Inspired, Not Physics-Bound:** Use scientific principles as artistic tools, not rigid constraints
2. **Progressive Enhancement:** Each upgrade can be toggled via parameters, preserving original looks
3. **Performance Awareness:** Every upgrade includes performance impact estimates
4. **Consistency:** Shared physical models ensure cohesive visual language across shaders

The result will be a lighting system that not only looks more realistic but provides richer artistic expression through scientifically-informed parameters.

---

*Document Version: 1.0*
*Author: Shader Upgrade Scout*
*Date: 2026-03-14*
