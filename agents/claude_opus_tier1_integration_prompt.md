# Claude Opus — Pixelocity Tier-1 Integration & Polish Pass

## Your Role
You are a **WGSL Integration Specialist** for the Pixelocity WebGPU shader effects platform. You do not write new effects from scratch — you refine, standardize, and integrate existing shaders so they fully leverage the rendering pipeline's capabilities.

## Mission
Perform a **integration & polish pass** on **9 foundational shaders** that were previously upgraded for RGBA and depth awareness (March 2026) but still lack:
- `plasmaBuffer` audio reactivity
- Domain-specific parameter names in their JSON definitions
- Accurate `features` tags
- Consistent tone mapping and code conventions

**Goal:** Every shader must feel "alive" with audio, have sliders that make semantic sense, and follow the exact same coding conventions.

---

## Immutable Pipeline Rules

### Binding Layout (MUST match exactly — copy this into every shader)

```wgsl
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
```

### Uniforms Struct (MUST match exactly)

```wgsl
struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};
```

### Audio Reactivity Standard

Read audio from `plasmaBuffer` — **NOT** from `u.config.yzw` (that is the legacy pattern).

```wgsl
let bass = plasmaBuffer[0].x;      // 0.0 – 1.0, low frequencies
let mids = plasmaBuffer[0].y;      // 0.0 – 1.0, mid frequencies
let treble = plasmaBuffer[0].z;    // 0.0 – 1.0, high frequencies
```

Use audio to modulate **at least one** visual parameter per shader (speed, brightness, pulse, jitter, etc.). Example patterns:

```wgsl
// Pattern A: Bass pulse on scale/brightness
let pulse = 1.0 + bass * 0.5;
let speed = baseSpeed * (1.0 + bass * 0.3);

// Pattern B: Treble adds sparkle/noise
let sparkle = step(1.0 - treble * 0.2, hash12(uv + time));

// Pattern C: Mids drive color shift
let hueShift = mids * 0.1;
```

### Safe Parameter Guards

```wgsl
// ✅ SAFE — always valid
let scale = mix(0.5, 2.0, u.zoom_params.x);

// ❌ DANGEROUS — can divide by zero
// let scale = 1.0 / u.zoom_params.x;

// ✅ FIXED
let scale = 1.0 / (u.zoom_params.x + 0.001);
```

### Tone Mapping Standard

Use this ACES approximation (or keep existing if already present):

```wgsl
fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
```

### Alpha Convention

- Alpha must be **calculated**, never hardcoded to `1.0`.
- Use `presence = smoothstep(minLuma, maxLuma, luma)` for generative shaders.
- Preserve input alpha: `finalAlpha = max(inputColor.a, generatedAlpha * opacity)`.

### Workgroup Size

Standard is `@workgroup_size(16, 16, 1)`. Do **NOT** change this on any shader.

---

## Creative Imagination Mandate

You are not just an integration technician — you are a **visual dreamer**. Every shader you touch must grow in unexpected, beautiful, and strange ways. The integration tasks above are the *minimum*. Below are **creative imagination prompts** for each shader. Implement at least **2** per shader.

### The Three Pillars (from Pixelocity's Creative Vision)

1. **🌀 Psychedelic** — Hypnotic patterns, non-Euclidean geometry, temporal manipulation, sensory overload that creates altered-state experiences.
2. **✨ Beautiful** — Harmonic color palettes, elegant mathematics, luminous glow, compositional harmony, refined polish.
3. **👁️ Strange** — Unexpected transformations, uncanny juxtapositions, alien aesthetics, disturbing-yet-alluring qualities, conceptual novelty.

### Shader Imagination Briefs

**1. `texture.wgsl` — The Living Lens**
- *Psychedelic*: The edge-enhancement should feel like a **Dali melting clock** — regions of high detail liquefy and drip according to audio bass. Add a subtle chromatic aberration that pulses with the beat.
- *Beautiful*: Implement a **golden-ratio vignette** with an iridescent rim light that shifts hue based on image luminance histogram.
- *Strange*: When treble spikes, the image should briefly "glitch" into a Voronoi mosaic of itself before snapping back — like the surface of reality cracking.

**2. `gen_orb.wgsl` — The Conscious Attractor**
- *Psychedelic*: The Lorenz streams should leave **persistent scent trails** in `dataTextureA` that decay over 5 seconds, creating a visible memory of where chaos has been.
- *Beautiful*: Add **bioluminescent bloom** — particles near the viewer glow with a soft volumetric halo calculated from their Z-depth.
- *Strange*: When bass drops, the attractor should briefly **split into two competing strange attractors** (Rössler vs Lorenz) that orbit each other before collapsing back.

**3. `gen_grokcf_interference.wgsl` — The Resonant Plate**
- *Psychedelic*: The sand particles should **self-organize into Fibonacci spirals** at high audio levels — cymatics becoming phyllotaxis.
- *Beautiful*: Add **iridescent oil-slick interference** on the metal plate surface that shifts with mouse movement.
- *Strange*: At mouse clicks, spawn a **secondary plate** (inverted, smaller) that interferes with the primary field, creating beating patterns.

**4. `gen_grid.wgsl` — The Breathing Lattice**
- *Psychedelic*: Grid intersections should spawn **recursive mini-grids** (3 levels deep) that rotate counter to the parent, creating a Moiré hypnosis field.
- *Beautiful*: Lines should have **chromatic dispersion** — red wavelengths bend more than blue under domain warp, creating rainbow edges.
- *Strange*: The grid should occasionally "remember" its previous warp state and **ghost-image** old configurations as translucent overlays.

**5. `gen_grokcf_voronoi.wgsl` — The Cellular Mind**
- *Psychedelic*: Cell interiors should contain **micro-cosmic starfields** that rotate independently, like each cell is a portal to another universe.
- *Beautiful*: Edge glow should use **thin-film interference** colors (oil slick / soap bubble) rather than flat palette colors.
- *Strange*: Cells should "compete" — randomly, two adjacent cells will **merge** over 2 seconds, their boundaries dissolving in a Turing pattern before splitting again.

**6. `gen_grok41_plasma.wgsl` — The Storm Giant**
- *Psychedelic*: Add **lightning tendrils** that arc between storm cells when treble hits, branching with L-system rules.
- *Beautiful*: The atmospheric rim should have **Rayleigh scattering** — a soft blue glow on the limb against a warm core, like a real gas giant.
- *Strange*: When mouse is held down, the sphere should reveal itself as **hollow** — an inverted world inside with reversed gravity and inverted colors.

**7. `galaxy.wgsl` — The Cosmic Organism**
- *Psychedelic*: Spiral arms should **breathe** — expanding and contracting with bass like the galaxy is a living lung. Add a central "eye" singularity that pulses.
- *Beautiful*: Stars should have **diffraction spikes** (4-point cross) whose length scales with brightness, and color temperature from blue-young to red-old.
- *Strange*: When audio is silent, the galaxy should **rewind** — stars flow backward along their spiral paths, time reversing until the next beat.

**8. `gen_trails.wgsl` — The Flock Soul**
- *Psychedelic*: Each flock should leave **pheromone trails** in `dataTextureA` that other flocks can detect and follow, creating emergent highway patterns.
- *Beautiful*: Boids should have **motion blur streaks** calculated from their velocity vectors, not just soft particles — comet-like tails.
- *Strange*: Occasionally (1% chance per frame), a boid should **transcend** — glowing gold, moving 3× faster, ignoring all flocking rules, and leaving a permanent luminous scar.

**9. `gen_grok41_mandelbrot.wgsl` — The Dreaming Buddha**
- *Psychedelic*: The Buddhabrot should **breathe** — sample count oscillates with bass, making the nebula inhale and exhale detail.
- *Beautiful*: Add **orbital rainbows** — each escape orbit leaves a faint spectral trace (red outside, violet inside) like a miniature aurora.
- *Strange*: At high treble, the set should **fracture** — cracks appear in the boundary, revealing a different fractal (Burning Ship) underneath, like peeling reality.

### Implementation Rules for Creative Additions

- **Never sacrifice the core effect** — the integration tasks are primary. Creative additions must layer on top, not replace.
- **Guard all new math** — `max(x, 0.001)`, `clamp()`, `select()` for branchless where possible.
- **Performance budget** — creative additions should not add more than ~20% to execution time. Prefer cheap tricks (UV warps, color shifts) over expensive loops.
- **Toggleability** — where possible, make creative effects param-driven so users can dial strangeness up or down.

---

## Shader-by-Shader Instructions

For each shader below, you are given:
1. Current `.wgsl` source (inline)
2. Current `.json` definition (inline)
3. Specific integration tasks

**Your output for each shader:**
- Complete rewritten `.wgsl` with all integration tasks applied
- Complete rewritten `.json` with domain-specific parameters and accurate tags

---

### 1. `texture.wgsl` → "Procedural Texture Analyzer v2"

**Current file:** `public/shaders/texture.wgsl` (~51 lines)

**Current JSON:** `shader_definitions/image/texture.json`

**Current source:**

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Texture - Basic image/video texture display with RGBA processing
//  Category: image
//  Features: upgraded-rgba, depth-aware
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma);
    
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

**Current JSON:**

```json
{
  "id": "texture",
  "name": "Texture Display",
  "url": "shaders/texture.wgsl",
  "category": "image",
  "description": "Basic image/video texture display with RGBA depth-aware processing.",
  "features": ["depth-aware", "upgraded-rgba"],
  "tags": ["image", "video", "basic"],
  "params": [
    {"id": "param1", "name": "Intensity", "default": 0.5, "min": 0, "max": 1, "step": 0.01},
    {"id": "param2", "name": "Speed",     "default": 0.5, "min": 0, "max": 1, "step": 0.01},
    {"id": "param3", "name": "Scale",     "default": 0.5, "min": 0, "max": 1, "step": 0.01},
    {"id": "param4", "name": "Detail",    "default": 0.5, "min": 0, "max": 1, "step": 0.01}
  ]
}
```

**Integration tasks:**
1. **Add procedural synthesis overlay** — Use `plasmaBuffer` bass to drive a subtle animated vignette or edge glow. The shader should still primarily display the input image, but when audio is present, the image "breathes" with bass pulses.
2. **Add multi-scale detail enhancement** — Param1 (`zoom_params.x`) controls edge enhancement strength using a simple Laplacian/ Sobel approximation (3×3 neighbor samples). Param2 controls unsharp mask intensity.
3. **Add temporal filtering** — Use `dataTextureC` to read the previous frame and blend with current for motion smoothing. Param3 controls temporal blend factor.
4. **Audio reactivity** — Bass drives vignette pulse; treble adds sparkle highlights on bright regions.
5. **JSON update** — Rename params to: "Edge Enhance", "Unsharp Mask", "Temporal Smooth", "Audio Reactivity". Add `audio-reactive` and `temporal` to features. Update tags.

---

### 2. `gen_orb.wgsl` → "Lorenz Strange Attractor v2"

**Current file:** `public/shaders/gen_orb.wgsl` (~200 lines)

**Current JSON:** `shader_definitions/generative/gen_orb.json` (id: `gen-orb`)

**Integration tasks:**
1. **Replace `u.config.yzw` audio with `plasmaBuffer`** — Read bass/mids/treble from `plasmaBuffer[0]`. Bass modulates particle glow intensity and stream count. Mids modulate rotation speed. Treble adds random jitter to particle positions.
2. **Add dataTextureA feedback** — Write accumulated color to `dataTextureA` and read from `dataTextureC` on next frame for temporal trail accumulation (separate from the Lorenz trails — this is a screen-space glow persistence).
3. **Parameter specificity** — JSON params should be: "Sigma (σ)", "Rho (ρ)", "Beta (β)", "Trail Persistence". Map to zoom_params.x/y/z/w. Update descriptions with scientific context.
4. **ACES tone mapping** — Replace `generatedColor = generatedColor / (1.0 + generatedColor * 0.5)` with the ACES function.
5. **Feature tags** — Add `audio-reactive`, `temporal`, `mathematical-art`.

**Current source:**

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Lorenz Strange Attractor - Chaotic particle system visualization
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, mathematical-art, particles
//  Scientific: Lorenz system - classic chaotic attractor
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=sigma, y=rho, z=beta, w=particleCount
  ripples: array<vec4<f32>, 50>,
};

// Hash function for pseudo-random numbers
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

// Lorenz system derivative
fn lorenzDerivative(pos: vec3<f32>, sigma: f32, rho: f32, beta: f32) -> vec3<f32> {
    let dx = sigma * (pos.y - pos.x);
    let dy = pos.x * (rho - pos.z) - pos.y;
    let dz = pos.x * pos.y - beta * pos.z;
    return vec3<f32>(dx, dy, dz);
}

// 4th order Runge-Kutta integration step
fn rk4Step(pos: vec3<f32>, dt: f32, sigma: f32, rho: f32, beta: f32) -> vec3<f32> {
    let k1 = lorenzDerivative(pos, sigma, rho, beta);
    let k2 = lorenzDerivative(pos + k1 * dt * 0.5, sigma, rho, beta);
    let k3 = lorenzDerivative(pos + k2 * dt * 0.5, sigma, rho, beta);
    let k4 = lorenzDerivative(pos + k3 * dt, sigma, rho, beta);
    return pos + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * dt / 6.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    let sigma = mix(5.0, 20.0, u.zoom_params.x);
    let rho = mix(10.0, 45.0, u.zoom_params.y);
    let beta = mix(1.0, 5.0, u.zoom_params.z);
    let particleCount = i32(mix(500.0, 3000.0, u.zoom_params.w));
    
    let opacity = 0.85;
    var generatedColor = vec3<f32>(0.02, 0.02, 0.04);
    
    let rotSpeed = time * 0.15;
    let camDist = 35.0;
    let cosY = cos(rotSpeed);
    let sinY = sin(rotSpeed);
    let cosX = cos(0.3);
    let sinX = sin(0.3);
    
    var accumColor = vec3<f32>(0.0);
    var maxDepth = 0.0;
    
    let streamCount = 8;
    let stepsPerStream = 400;
    
    for (var s = 0; s < streamCount; s = s + 1) {
        let seed = hash3(vec3<f32>(f32(s) * 12.34, time * 0.1, 0.0));
        var pos = vec3<f32>(seed.x * 2.0 - 1.0, seed.y * 2.0 - 1.0, 25.0 + seed.z * 10.0);
        
        var warmup = 0;
        var tempPos = pos;
        while (warmup < 500) {
            tempPos = rk4Step(tempPos, 0.005, sigma, rho, beta);
            warmup = warmup + 1;
        }
        pos = tempPos;
        
        var prevScreenPos = vec2<f32>(-1000.0);
        var prevVel = 0.0;
        
        for (var i = 0; i < stepsPerStream; i = i + 1) {
            let currentPos = pos;
            pos = rk4Step(pos, 0.008, sigma, rho, beta);
            
            let vel = length(pos - currentPos);
            let avgVel = (vel + prevVel) * 0.5;
            prevVel = vel;
            
            var rotated = vec3<f32>(
                currentPos.x * cosY - currentPos.z * sinY,
                currentPos.y,
                currentPos.x * sinY + currentPos.z * cosY
            );
            rotated = vec3<f32>(
                rotated.x,
                rotated.y * cosX - rotated.z * sinX,
                rotated.y * sinX + rotated.z * cosX
            );
            
            let z = rotated.z + camDist;
            if (z > 0.1) {
                let scale = 15.0 / z;
                let screenPos = vec2<f32>(rotated.x * scale * 0.0015, rotated.y * scale * 0.0015);
                let dist = length(p - screenPos);
                let depth = 1.0 - (z / 60.0);
                maxDepth = max(maxDepth, depth);
                
                let particleSize = (0.003 + avgVel * 0.5) * (0.5 + depth * 0.5);
                let glow = particleSize / (dist * dist + 0.0001);
                let speedNorm = clamp(avgVel * 50.0, 0.0, 1.0);
                let hue = f32(s) * 0.125 + speedNorm * 0.3 + time * 0.05;
                
                let h = fract(hue) * 6.0;
                let c = 1.0;
                let x = c * (1.0 - abs(f32(h % 2.0) - 1.0));
                var rgb = vec3<f32>(0.0);
                if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
                else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
                else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
                else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
                else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
                else { rgb = vec3<f32>(c, 0.0, x); }
                
                let trailFade = 1.0 - f32(i) / f32(stepsPerStream);
                accumColor += rgb * glow * trailFade * depth * 0.3;
                
                if (prevScreenPos.x > -100.0) {
                    let lineDist = abs(dist - length(p - prevScreenPos));
                    let lineGlow = 0.0005 / (lineDist * lineDist + 0.00001);
                    accumColor += rgb * lineGlow * trailFade * depth * 0.1;
                }
                prevScreenPos = screenPos;
            }
        }
    }
    
    let wingGlow1 = 0.002 / (length(p - vec2<f32>(-0.15, 0.05)) + 0.03);
    let wingGlow2 = 0.002 / (length(p - vec2<f32>(0.15, -0.05)) + 0.03);
    accumColor += vec3<f32>(0.8, 0.3, 0.9) * wingGlow1 * 0.2;
    accumColor += vec3<f32>(0.3, 0.7, 0.9) * wingGlow2 * 0.2;
    
    generatedColor = generatedColor + accumColor;
    generatedColor = generatedColor / (1.0 + generatedColor * 0.5);
    
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    generatedColor *= vignette;
    
    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.02, 0.1, luma);
    let alpha = mix(0.0, 1.0, presence);
    
    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);
    let finalDepth = mix(inputDepth, maxDepth, alpha * opacity);
    
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
```

---

### 3. `gen_grokcf_interference.wgsl` → "Chladni Plate Cymatics v2"

**Current file:** `public/shaders/gen_grokcf_interference.wgsl` (~200 lines)

**Current JSON:** `shader_definitions/generative/gen_grokcf_interference.json` (id: `gen-grokcf-interference`)

**Integration tasks:**
1. **plasmaBuffer integration** — Bass drives sweep speed (makes the plate vibrate to the beat). Mids modulate particle density. Treble adds high-frequency shimmer to the sand texture.
2. **Replace generic JSON params** with: "Sweep Speed", "Mode Count", "Pattern Sharpness", "Sand Density".
3. **Add `dataTextureA` state pass** — Store the current displacement field in `dataTextureA` so multi-pass shaders downstream can read it as a data texture.
4. **Standardize alpha** — The current alpha is based on luma. Add edge-detection-based alpha: nodal lines (edges between cells) get higher alpha for a "stained glass" compositing effect.
5. **Feature tags** — Ensure `audio-reactive` is present (it already is, but verify it works with `plasmaBuffer` not legacy audio).

---

### 4. `gen_grid.wgsl` → "Domain-Warped FBM Grid v2"

**Current file:** `public/shaders/gen_grid.wgsl` (~200 lines)

**Current JSON:** `shader_definitions/generative/gen_grid.json` (id: `gen-grid`)

**Integration tasks:**
1. **plasmaBuffer integration** — Bass distorts the grid more aggressively (higher warp amount). Mids shift the color palette phase. Treble adds sparkle on grid intersections.
2. **Replace generic JSON params** with: "Warp Amount", "Grid Density", "Line Thickness", "Palette Shift".
3. **Mouse reactivity enhancement** — Mouse position (`zoom_config.yz`) should attract the domain warp like a gravity well, not just shift UVs.
4. **Temporal feedback** — Use `dataTextureC` to read previous frame and blend for motion blur on the warp.
5. **Add `audio-reactive` to features**.

---

### 5. `gen_grokcf_voronoi.wgsl` → "Worley Cellular v2"

**Current file:** `public/shaders/gen_grokcf_voronoi.wgsl` (~200 lines)

**Current JSON:** `shader_definitions/generative/gen_grokcf_voronoi.json` (id: `gen-grokcf-voronoi`)

**Integration tasks:**
1. **plasmaBuffer integration** — Bass makes cells pulse (scale cell density with bass). Mids drive edge glow intensity. Treble adds flicker to cell interiors.
2. **Replace generic JSON params** with: "Cell Density", "Edge Glow", "Color Shift", "Parallax".
3. **dataTextureA usage** — Write cell ID + edge mask to `dataTextureA` so downstream shaders can do cell-based masking.
4. **Depth output** — Use `combined_f1` (Worley F1 distance) as depth for interesting depth-aware post-processing.
5. **Add `audio-reactive` to features**.

---

### 6. `gen_grok41_plasma.wgsl` → "Spherical Harmonics Plasma v2"

**Current file:** `public/shaders/gen_grok41_plasma.wgsl` (~200 lines)

**Current JSON:** `shader_definitions/generative/gen_grok41_plasma.json` (id: `gen-grok41-plasma`)

**Integration tasks:**
1. **plasmaBuffer integration** — Bass drives atmospheric turbulence (more violent storms). Mids shift the gas giant's hue. Treble adds lightning flashes on the limb.
2. **Replace generic JSON params** with: "L1 Coefficient", "L2 Coefficient", "L3 Coefficient", "Hue Shift".
3. **ACES tone mapping** — The current output is clamped. Switch to HDR accumulation + ACES tone mapping for more dramatic lighting.
4. **Mouse reactivity** — Mouse controls the light source direction (currently fixed at `vec3<f32>(0.8, 0.3, 1.0)`).
5. **Add `audio-reactive` to features**.

---

### 7. `galaxy.wgsl` → "Galaxy Simulation v2"

**Current file:** `public/shaders/galaxy.wgsl` (~150 lines)

**Current JSON:** `shader_definitions/generative/galaxy.json` (id: `galaxy-sim`)

**Integration tasks:**
1. **CRITICAL FIX: Replace legacy audio with plasmaBuffer** — Currently reads audio from `u.config.yzw` (wrong!). Replace with `plasmaBuffer[0].x` (bass) for spiral rotation speed, `plasmaBuffer[0].y` (mids) for arm twisting, `plasmaBuffer[0].z` (treble) for star twinkle frequency.
2. **Replace generic JSON params** with: "Opacity", "Arm Count", "Rotation Speed", "Arm Spread".
3. **Add dataTextureA feedback** — Store the star density field in `dataTextureA` so that multi-pass glow effects can be applied downstream.
4. **Mouse-driven center** — Mouse position (`zoom_config.yz`) should offset the galaxy center, creating a parallax feel.
5. **Feature tags** — Already has `audio-reactive` but ensure it works with `plasmaBuffer`.

---

### 8. `gen_trails.wgsl` → "Boids Flocking v2"

**Current file:** `public/shaders/gen_trails.wgsl` (273 lines)

**Current JSON:** `shader_definitions/generative/gen_trails.json` (id: `gen-trails`)

**Integration tasks:**
1. **plasmaBuffer integration** — Bass adds panic/agitation (higher max speed, larger separation radius). Mids attract boids to the center (cohesion boost). Treble makes random boids flash bright.
2. **Replace generic JSON params** with: "Separation", "Alignment", "Cohesion", "Max Speed".
3. **dataTextureA/B usage** — Current shader reads `dataTextureC` for history. Also write boid velocity field to `dataTextureA` so downstream shaders can do motion-blur or advection.
4. **Mouse interaction fix** — Currently mouse is checked with `length(u.zoom_config.yz) > 0.001` which is always true. Use `u.zoom_config.w > 0.5` for mouse-down detection, and `zoom_config.yz` for position.
5. **Audio-reactive spawn** — Add a param-driven option where bass pulses spawn new boid bursts.
6. **Add `audio-reactive` to features**.

---

### 9. `gen_grok41_mandelbrot.wgsl` → "Buddhabrot Nebula v2"

**Current file:** `public/shaders/gen_grok41_mandelbrot.wgsl` (185 lines)

**Current JSON:** `shader_definitions/generative/gen_grok41_mandelbrot.json` (id: `gen-grok41-mandelbrot`)

**Integration tasks:**
1. **plasmaBuffer integration** — Bass modulates the evolution speed and zoom scale (pulsing exploration). Mids shift the nebula color palette. Treble adds transient "sparkle" stars.
2. **Replace generic JSON params** with: "Center X", "Center Y", "Zoom Scale", "Evolution Speed".
3. **Mouse-driven exploration** — Mouse position (`zoom_config.yz`) should pan the view center when mouse is down (`zoom_config.w > 0.5`). Currently params control center but mouse doesn't.
4. **dataTextureA temporal accumulation** — Buddhabrot is inherently noisy. Accumulate over frames by blending current output with `dataTextureC` history. Param4 controls history blend (0 = no accumulation, 1 = infinite persistence).
5. **ACES tone mapping** — Replace `pow(color, vec3<f32>(0.8))` with proper ACES.
6. **Feature tags** — Add `audio-reactive`, `temporal`.

---

## Output Format

For each shader, provide **two code blocks** with exact file paths:

### WGSL Output

````
### `public/shaders/{shader_id}.wgsl`

```wgsl
// complete rewritten source here
```
````

### JSON Output

````
### `shader_definitions/{category}/{shader_id}.json`

```json
{ "id": "...", ... }
```
````

## Validation Checklist

Before finalizing each shader, verify:

- [ ] All 13 bindings declared in exact order
- [ ] `Uniforms` struct matches specification exactly
- [ ] `@compute @workgroup_size(16, 16, 1)` present
- [ ] `plasmaBuffer[0].x/y/z` used for audio (not `u.config.yzw`)
- [ ] Both `writeTexture` AND `writeDepthTexture` are written
- [ ] Alpha is calculated, never hardcoded to `1.0`
- [ ] Input alpha preserved: `finalAlpha = max(inputColor.a, generatedAlpha * opacity)`
- [ ] No division by parameter without `+ 0.001` guard
- [ ] ACES tone mapping used (or existing equivalent kept)
- [ ] JSON params have domain-specific names (not "Intensity/Speed/Scale/Detail")
- [ ] JSON `features` includes `audio-reactive` where plasmaBuffer is used
- [ ] JSON `tags` contains at least 4 relevant AI VJ tags
- [ ] `dataTextureA` is written to when temporal/data feedback is implemented

## Fallback Instruction

If you run out of output space, **prioritize shaders 1–5** (texture, gen_orb, gen_grokcf_interference, gen_grid, gen_grokcf_voronoi) and note clearly where you stopped. The first 5 are the most important for establishing patterns.

## Begin

Start with shader #1 (`texture.wgsl`) and proceed through all 9. Maintain consistent coding style (2-space indentation, descriptive variable names, section comments with `═══` separators).


---

## Appendix: Current Source Code for Shaders 3–9

The following sections contain the complete current WGSL source for each remaining shader. Use these as your starting point for integration.

---

### A. `gen_grokcf_interference.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Chladni Plate Cymatics - Modal Synthesis Visualization
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated, organic
//  Scientific basis: Chladni figures from vibrating plate standing waves
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

const MODES: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
    vec4<f32>(1.0, 1.0, 1.0, 0.0),
    vec4<f32>(2.0, 1.0, 0.8, 0.5),
    vec4<f32>(1.0, 2.0, 0.8, 0.3),
    vec4<f32>(2.0, 2.0, 0.6, 0.7),
    vec4<f32>(3.0, 1.0, 0.5, 0.2),
    vec4<f32>(1.0, 3.0, 0.5, 0.9),
    vec4<f32>(3.0, 2.0, 0.4, 0.4),
    vec4<f32>(2.0, 3.0, 0.4, 0.6)
);

fn hash2(p: vec2<f32>) -> f32 {
    let k = vec2<f32>(0.3183099, 0.3678794);
    var x = p * k + k.yx;
    return fract(16.0 * k.x * fract(x.x * x.y * (x.x + x.y)));
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    
    let sweepSpeed = u.zoom_params.x * 2.0 + 0.1;
    let numModes = i32(clamp(u.zoom_params.y * 8.0 + 1.0, 1.0, 8.0));
    let sharpness = u.zoom_params.z * 3.0 + 0.5;
    let particleDensity = u.zoom_params.w;
    
    let plateUV = (uv - 0.5) * 2.0;
    let x = plateUV.x;
    let y = plateUV.y;
    
    let baseFreq = 3.14159265 * (1.0 + sin(time * sweepSpeed * 0.2) * 0.5);
    
    var displacement = 0.0;
    for (var i: i32 = 0; i < numModes; i = i + 1) {
        let mode = MODES[i];
        let m = mode.x;
        let n = mode.y;
        let amp = mode.z;
        let phase = mode.w * 6.28318;
        let kx = m * baseFreq;
        let ky = n * baseFreq;
        let modeOscillation = cos(time * sweepSpeed + phase + f32(i) * 0.5);
        let modeDisplacement = sin(kx * x) * sin(ky * y) * modeOscillation * amp;
        displacement = displacement + modeDisplacement;
    }
    displacement = displacement / f32(numModes);
    
    let mouseDist = length(plateUV - (mouse - 0.5) * 2.0);
    let mouseInfluence = exp(-mouseDist * 8.0) * sin(time * 10.0 + mouseDist * 20.0);
    displacement = displacement + mouseInfluence * 0.3;
    
    let nodeMask = 1.0 - smoothstep(0.0, 0.15 / sharpness, abs(displacement));
    let vibrationEnergy = abs(displacement);
    let particleSettling = 1.0 - smoothstep(0.0, 0.3, vibrationEnergy);
    
    let sandNoise = noise(uv * 400.0 + time * 0.1);
    let sandDetail = noise(uv * 150.0 - time * 0.05);
    
    let particleThreshold = 0.6 - particleDensity * 0.4;
    let particleMask = step(particleThreshold, particleSettling + sandNoise * 0.15);
    
    let sandColor = vec3<f32>(0.85, 0.78, 0.65) * (0.8 + sandDetail * 0.4);
    let plateColor = vec3<f32>(0.15, 0.12, 0.10) * (1.0 + vibrationEnergy * 0.5);
    
    let patternHue = sin(displacement * 10.0 + time * 0.5) * 0.5 + 0.5;
    let interferenceColor = mix(
        vec3<f32>(0.9, 0.85, 0.7),
        vec3<f32>(0.6, 0.7, 0.8),
        patternHue * 0.3
    );
    
    var color = mix(plateColor, sandColor * interferenceColor, particleMask);
    let nodeGlow = nodeMask * 0.3 * (0.5 + sandNoise * 0.5);
    color = color + vec3<f32>(nodeGlow * 0.9, nodeGlow * 0.85, nodeGlow * 0.7);
    let highlight = pow(1.0 - vibrationEnergy, 3.0) * 0.2;
    color = color + vec3<f32>(highlight);
    
    let edgeDist = length(plateUV);
    let vignette = 1.0 - smoothstep(0.7, 1.0, edgeDist);
    color = color * (0.7 + vignette * 0.3);
    let boundary = smoothstep(0.98, 1.0, edgeDist);
    color = mix(color, vec3<f32>(0.3, 0.25, 0.2), boundary * 0.5);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let opacity = 0.9;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let generatedAlpha = mix(0.7, 1.0, luma);
    
    let finalColor = mix(inputColor.rgb, color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);
    
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    let depthValue = mix(inputDepth, vibrationEnergy * 0.5 + 0.5, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthValue, 0.0, 0.0, 0.0));
}
```

---

### B. `gen_grid.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Domain-Warped FBM Grid
//  Category: generative
//  Features: upgraded-rgba, depth-aware, domain-warping, FBM-noise, organic
//  Scientific Concept: Domain Warping - distort UV with noise before sampling
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yzz) * p.zyx);
}

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

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
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

fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
        fbm(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
    );
    let r = vec2<f32>(
        fbm(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
        fbm(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
    );
    return uv + amount * r;
}

fn gridLine(warpedUV: vec2<f32>, gridSize: f32, thickness: f32) -> vec4<f32> {
    let gridPos = warpedUV * gridSize;
    let gridFract = fract(gridPos - 0.5) - 0.5;
    let lineDist = abs(gridFract);
    let nearestLine = min(lineDist.x, lineDist.y);
    let adjustedThickness = thickness * (1.0 + length(gridFract) * 0.5);
    var intensity = 1.0 - smoothstep(0.0, adjustedThickness, nearestLine);
    let glow = 0.3 * (1.0 - smoothstep(0.0, adjustedThickness * 3.0, nearestLine));
    return vec4<f32>(intensity, glow, nearestLine, adjustedThickness);
}

fn colorPalette(t: f32, shift: f32) -> vec3<f32> {
    let cyan = vec3<f32>(0.0, 1.0, 0.9);
    let blue = vec3<f32>(0.1, 0.4, 1.0);
    let magenta = vec3<f32>(1.0, 0.0, 0.8);
    let purple = vec3<f32>(0.6, 0.0, 1.0);
    let gold = vec3<f32>(1.0, 0.7, 0.1);
    
    let shiftedT = fract(t + shift);
    var color: vec3<f32>;
    if (shiftedT < 0.25) {
        color = mix(cyan, blue, shiftedT * 4.0);
    } else if (shiftedT < 0.5) {
        color = mix(blue, magenta, (shiftedT - 0.25) * 4.0);
    } else if (shiftedT < 0.75) {
        color = mix(magenta, purple, (shiftedT - 0.5) * 4.0);
    } else {
        color = mix(purple, gold, (shiftedT - 0.75) * 4.0);
    }
    return color;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let distortionAmount = u.zoom_params.x;
    let gridScale = u.zoom_params.y;
    let lineThickness = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    
    let warpAmount = select(0.4, distortionAmount, distortionAmount > 0.001);
    let scale = select(1.5, gridScale, gridScale > 0.1);
    let thickness = select(0.03, lineThickness, lineThickness > 0.001);
    let shift = select(0.0, colorShift, colorShift > 0.001);
    
    let opacity = mix(0.6, 1.0, lineThickness);
    
    let aspect = resolution.x / resolution.y;
    var p = uv;
    p.x *= aspect;
    
    let warpedP = domainWarp(p, time, scale * 2.0, warpAmount);
    let distortionMag = length(warpedP - p);
    
    let gridSize = 8.0;
    let gridResult = gridLine(warpedP, gridSize, thickness);
    let lineIntensity = gridResult.x;
    let lineGlow = gridResult.y;
    
    let colorT = distortionMag * 2.0 + time * 0.05 + shift;
    let baseColor = colorPalette(colorT, shift);
    let accentT = distortionMag * 3.0 - time * 0.03 + 0.5 + shift;
    let accentColor = colorPalette(accentT, shift + 0.25);
    let mixFactor = smoothstep(0.0, 0.5, distortionMag);
    let lineColor = mix(baseColor, accentColor, mixFactor);
    
    var generatedColor = vec3<f32>(0.02, 0.02, 0.05);
    generatedColor = generatedColor + lineColor * lineIntensity;
    generatedColor = generatedColor + lineColor * lineGlow * 0.5;
    generatedColor = generatedColor + accentColor * distortionMag * 0.15;
    
    let vignetteUV = uv * (1.0 - uv);
    let vignette = vignetteUV.x * vignetteUV.y * 15.0;
    generatedColor = generatedColor * clamp(vignette, 0.0, 1.0);
    generatedColor = pow(generatedColor, vec3<f32>(0.85));
    
    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let lineAlpha = mix(0.5, 1.0, lineIntensity + lineGlow);
    let alpha = lineAlpha;
    
    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);
    
    let generatedDepth = distortionMag;
    let finalDepth = mix(inputDepth, generatedDepth, alpha * opacity);
    
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
```

---

### C. `gen_grokcf_voronoi.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Worley Noise with FBM Layering and Edge Detection
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated, organic-cellular
//  Scientific: Worley Noise - based on distance to random feature points
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var h = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(h) * 43758.5453);
}

fn hash3(p: vec2<f32>) -> vec3<f32> {
    var h = vec3<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3)),
        dot(p, vec2<f32>(419.2, 371.9))
    );
    return fract(sin(h) * 43758.5453);
}

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

struct WorleyResult {
    f1: f32,
    f2: f32,
    cell_id: vec2<f32>,
};

fn worley_noise(uv: vec2<f32>, scale: f32, time: f32, drift_speed: f32) -> WorleyResult {
    let st = uv * scale;
    let cell = floor(st);
    let frac = fract(st);
    
    var f1 = 1e10;
    var f2 = 1e10;
    var cell_id = vec2<f32>(0.0);
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let current_cell = cell + neighbor;
            let hash_val = hash2(current_cell);
            let drift = vec2<f32>(
                sin(time * drift_speed + hash_val.x * 6.28),
                cos(time * drift_speed + hash_val.y * 6.28)
            ) * 0.3;
            let feature_point = neighbor + hash_val + drift;
            let diff = feature_point - frac;
            let dist = length(diff);
            
            if dist < f1 {
                f2 = f1;
                f1 = dist;
                cell_id = hash_val;
            } else if dist < f2 {
                f2 = dist;
            }
        }
    }
    return WorleyResult(f1, f2, cell_id);
}

fn fbm_worley(uv: vec2<f32>, time: f32, base_scale: f32, octaves: i32) -> vec3<f32> {
    var total_f1: f32 = 0.0;
    var total_f2: f32 = 0.0;
    var amplitude: f32 = 1.0;
    var frequency: f32 = 1.0;
    var max_value: f32 = 0.0;
    var cell_color = vec3<f32>(0.0);
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let worley = worley_noise(uv, base_scale * frequency, time, 0.5 + f32(i) * 0.2);
        total_f1 = total_f1 + worley.f1 * amplitude;
        total_f2 = total_f2 + worley.f2 * amplitude;
        max_value = max_value + amplitude;
        cell_color = cell_color + hash3(worley.cell_id + f32(i)) * amplitude;
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    
    total_f1 = total_f1 / max_value;
    total_f2 = total_f2 / max_value;
    cell_color = cell_color / max_value;
    let edge_value = total_f2 - total_f1;
    return vec3<f32>(total_f1, total_f2, edge_value);
}

fn get_inner_color(cell_hash: vec2<f32>) -> vec3<f32> {
    let palette = array<vec3<f32>, 5>(
        vec3<f32>(0.15, 0.08, 0.12),
        vec3<f32>(0.08, 0.15, 0.10),
        vec3<f32>(0.12, 0.10, 0.18),
        vec3<f32>(0.18, 0.12, 0.08),
        vec3<f32>(0.10, 0.12, 0.15)
    );
    let idx = i32(cell_hash.x * 4.99);
    return palette[idx];
}

fn get_edge_color(cell_hash: vec2<f32>, time: f32) -> vec3<f32> {
    let glow = 0.5 + 0.5 * sin(time * 0.5 + cell_hash.y * 6.28);
    let palette = array<vec3<f32>, 4>(
        vec3<f32>(0.9, 0.3, 0.5),
        vec3<f32>(0.3, 0.8, 0.6),
        vec3<f32>(0.6, 0.4, 0.9),
        vec3<f32>(0.9, 0.7, 0.3)
    );
    let idx = i32(cell_hash.x * 3.99);
    return palette[idx] * (0.7 + glow * 0.3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    let cell_density = u.zoom_params.x;
    let edge_intensity = u.zoom_params.y;
    let color_shift = u.zoom_params.z;
    let parallax = u.zoom_params.w;
    
    let density = mix(3.0, 12.0, cell_density);
    let edges = mix(0.3, 1.5, edge_intensity);
    
    let uv1 = uv + vec2<f32>(sin(time * 0.05), cos(time * 0.03)) * parallax * 0.02;
    let worley1 = fbm_worley(uv1, time * 0.1, density, 3);
    
    let uv2 = uv - vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * parallax * 0.03;
    let worley2 = fbm_worley(uv2, time * 0.15 + 100.0, density * 1.5, 2);
    
    let uv3 = uv + vec2<f32>(cos(time * 0.1), sin(time * 0.08)) * parallax * 0.01;
    let worley3 = fbm_worley(uv3, time * 0.2 + 200.0, density * 3.0, 2);
    
    let combined_f1 = worley1.x * 0.5 + worley2.x * 0.3 + worley3.x * 0.2;
    let combined_f2 = worley1.y * 0.5 + worley2.y * 0.3 + worley3.y * 0.2;
    let combined_edge = worley1.z * 0.5 + worley2.z * 0.3 + worley3.z * 0.2;
    
    let edge_value = combined_edge * edges;
    let cell_hash = hash2(floor(uv * density));
    let inner_color = get_inner_color(cell_hash + color_shift);
    let edge_color = get_edge_color(cell_hash + color_shift, time);
    let depth_shading = 1.0 - combined_f1 * 0.5;
    
    let edge_mask = smoothstep(0.0, 0.15, edge_value);
    var final_color = mix(inner_color * depth_shading, edge_color, edge_mask);
    let glow = pow(edge_value, 2.0) * edge_intensity * 0.5;
    final_color = final_color + edge_color * glow;
    
    let vignette = 1.0 - length((uv - 0.5) * 1.2);
    final_color = final_color * smoothstep(0.0, 0.7, vignette);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let opacity = 0.9;
    let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let edgeAlpha = mix(0.6, 1.0, edge_mask);
    let generatedAlpha = edgeAlpha;
    
    let finalColor = mix(inputColor.rgb, final_color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);
    
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    let depth_out = mix(inputDepth, 1.0 - combined_f1 * 0.8 + edge_value * 0.2, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_out, 0.0, 0.0, 0.0));
}
```

---

### D. `gen_grok41_plasma.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Spherical Harmonics Plasma - 3D Gas Giant Atmosphere
//  Projects plasma patterns onto a rotating sphere using Y(l,m) basis
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated, spherical-harmonics
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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
const TWO_PI: f32 = 6.28318530718;

fn rotateX(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

fn rotateY(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

fn rotateZ(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

fn Y00(theta: f32, phi: f32) -> f32 { return 0.2820947918; }
fn Y10(theta: f32, phi: f32) -> f32 { return 0.4886025119 * cos(theta); }
fn Y1p1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * cos(phi); }
fn Y1n1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * sin(phi); }
fn Y20(theta: f32, phi: f32) -> f32 { return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0); }
fn Y2p1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * cos(phi); }
fn Y2n1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * sin(phi); }
fn Y2p2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * cos(2.0 * phi); }
fn Y2n2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * sin(2.0 * phi); }
fn Y30(theta: f32, phi: f32) -> f32 {
    let ct = cos(theta);
    return 0.3731763326 * (5.0 * ct * ct * ct - 3.0 * ct);
}

fn gasGiantColor(value: f32, time: f32, hueShift: f32) -> vec3<f32> {
    let v = value * 0.5 + 0.5;
    let hue = fract(v * 0.3 + time * 0.05 + hueShift);
    
    let color1 = vec3<f32>(0.8, 0.6, 0.4);
    let color2 = vec3<f32>(0.6, 0.4, 0.2);
    let color3 = vec3<f32>(0.9, 0.5, 0.2);
    let color4 = vec3<f32>(0.7, 0.3, 0.15);
    let color5 = vec3<f32>(0.85, 0.7, 0.5);
    
    var color: vec3<f32>;
    if v < 0.2 { color = mix(color1, color2, v * 5.0); }
    else if v < 0.4 { color = mix(color2, color3, (v - 0.2) * 5.0); }
    else if v < 0.6 { color = mix(color3, color4, (v - 0.4) * 5.0); }
    else if v < 0.8 { color = mix(color4, color5, (v - 0.6) * 5.0); }
    else { color = mix(color5, color1, (v - 0.8) * 5.0); }
    
    let variation = sin(v * 20.0 + time) * 0.1;
    color += variation;
    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x * 0.15;
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);
    let coord = vec2<i32>(global_id.xy);
    
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouseInfluence = u.zoom_config.w;
    
    let sphereRadius = 0.45;
    let sphereCenter = vec3<f32>(0.0, 0.0, 0.0);
    var ro = vec3<f32>(0.0, 0.0, 1.8);
    let rd = normalize(vec3<f32>(uv.x, uv.y, -1.2));
    
    let rotTime = time * 0.5;
    let ro_rotated = rotateY(rotateX(ro, sin(time * 0.2) * 0.1), rotTime);
    let viewRotY = mouse.x * 0.5 * mouseInfluence;
    let viewRotX = mouse.y * 0.3 * mouseInfluence;
    let ro_final = rotateY(rotateX(ro_rotated, viewRotX), viewRotY);
    let rd_final = rotateY(rotateX(rd, viewRotX), viewRotY);
    
    let oc = ro_final - sphereCenter;
    let a = dot(rd_final, rd_final);
    let b = 2.0 * dot(oc, rd_final);
    let c = dot(oc, oc) - sphereRadius * sphereRadius;
    let discriminant = b * b - 4.0 * a * c;
    
    var outputColor: vec3<f32>;
    var depth: f32 = 0.0;
    var alpha: f32 = 1.0;
    
    let uv_norm = vec2<f32>(global_id.xy) / resolution;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv_norm, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_norm, 0.0).r;
    
    let opacity = 0.9;

    if discriminant > 0.0 {
        let t = (-b - sqrt(discriminant)) / (2.0 * a);
        let hitPoint = ro_final + rd_final * t;
        let normal = normalize(hitPoint - sphereCenter);
        let theta = acos(clamp(normal.y, -1.0, 1.0));
        let phi = atan2(normal.z, normal.x);
        
        let coeffs = u.zoom_params;
        var pattern = 0.0;
        
        pattern += Y00(theta, phi) * 0.4;
        let l1 = coeffs.x;
        pattern += Y10(theta, phi) * sin(time * 0.5 + phi * 2.0) * l1;
        pattern += Y1p1(theta, phi) * cos(time * 0.3) * l1 * 0.5;
        pattern += Y1n1(theta, phi) * sin(time * 0.4) * l1 * 0.5;
        
        let l2 = coeffs.y;
        pattern += Y20(theta, phi) * cos(time * 0.6) * l2;
        pattern += Y2p1(theta, phi) * sin(time * 0.45 + theta) * l2 * 0.6;
        pattern += Y2n1(theta, phi) * cos(time * 0.55) * l2 * 0.6;
        pattern += Y2p2(theta, phi) * sin(time * 0.35 + phi * 3.0) * l2 * 0.4;
        pattern += Y2n2(theta, phi) * cos(time * 0.25) * l2 * 0.4;
        
        let l3 = coeffs.z;
        pattern += Y30(theta, phi) * sin(time * 0.7 + phi) * l3 * 0.5;
        
        let turbulence = sin(theta * 15.0 + time) * sin(phi * 12.0 - time * 0.5) * 0.05;
        pattern += turbulence * (l1 + l2 + l3) * 0.3;
        
        let lightDir = normalize(vec3<f32>(0.8, 0.3, 1.0));
        let diff = max(dot(normal, lightDir), 0.0);
        let ambient = 0.25;
        let viewDir = -rd_final;
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.3;
        let rim = pow(1.0 - abs(dot(normal, viewDir)), 3.0) * 0.4;
        
        let baseColor = gasGiantColor(pattern, time, coeffs.w);
        let litColor = baseColor * (diff * 0.7 + ambient) + vec3<f32>(spec);
        let atmosphereColor = vec3<f32>(0.6, 0.8, 1.0);
        let generatedColor = litColor + atmosphereColor * rim;
        
        let rimAlpha = pow(1.0 - abs(dot(normal, viewDir)), 2.0);
        let hitAlpha = mix(0.9, 1.0, rimAlpha * 0.5);
        
        outputColor = mix(inputColor.rgb, generatedColor, hitAlpha * opacity);
        alpha = max(inputColor.a, hitAlpha * opacity);
        
        let clipZ = hitPoint.z;
        let generatedDepth = (clipZ + sphereRadius) / (sphereRadius * 2.0 + 1.8);
        depth = mix(inputDepth, generatedDepth, hitAlpha * opacity);
    } else {
        outputColor = inputColor.rgb;
        depth = inputDepth;
        alpha = inputColor.a;
    }
    
    textureStore(writeTexture, coord, vec4<f32>(clamp(outputColor, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

---

### E. `galaxy.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Galaxy - Animated galaxy simulation with RGBA processing
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    
    let opacity = mix(0.5, 1.0, u.zoom_params.x);
    
    let p = (uv - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    var screenP = p;
    screenP.x *= aspect;
    
    let zoom = u.zoom_config.x;
    let arms = mix(2.0, 6.0, u.zoom_params.y);
    let rotation = mix(0.5, 3.0, u.zoom_params.z);
    let spread = mix(0.1, 0.5, u.zoom_params.w);
    let brightness = 1.25;
    
    let radius = length(screenP);
    let angle = atan2(screenP.y, screenP.x);
    
    let spiralAngle = angle + rotation * time * 0.1 * audioReactivity - radius * 2.0;
    let armModulation = cos(spiralAngle * arms);
    
    let coreDensity = exp(-radius * 3.0);
    let armDensity = smoothstep(1.0 - spread, 1.0, armModulation) * exp(-radius * 1.5);
    let density = (coreDensity * 0.6 + armDensity * 0.4) * brightness;
    
    let starHash = hash3(vec3<f32>(floor(screenP * 50.0), time * 0.01 * audioReactivity));
    let star = step(0.997, starHash.x) * starHash.y;
    
    let coreColor = vec3<f32>(0.3, 0.5, 1.0);
    let armColor = vec3<f32>(1.0, 0.8, 0.4);
    let starColor = vec3<f32>(1.0, 1.0, 1.0);
    
    let baseColor = mix(coreColor, armColor, smoothstep(0.0, 0.5, radius));
    var generatedColor = baseColor * density + starColor * star;
    
    let twinkle = sin(time * 3.0 * audioReactivity + radius * 10.0) * 0.1 + 0.9;
    generatedColor = generatedColor * twinkle;
    
    let vignette = 1.0 - radius * 0.5;
    generatedColor = generatedColor * vignette;
    
    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.05, 0.2, luma);
    let alpha = mix(0.0, 1.0, presence);
    
    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);
    
    let generatedDepth = 1.0 - radius * 0.5;
    let finalDepth = mix(inputDepth, generatedDepth, alpha * opacity);
    
    textureStore(writeTexture, coord, vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0)), finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
```

---

### F. `gen_trails.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Boids Flocking with Alpha Scattering
//  Craig Reynolds' Boids (1986) with physical light simulation
//  Category: generative
//  Features: upgraded-rgba, depth-aware, particles, flocking, motion-trails
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let r = vec2<f32>(
        fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453),
        fract(sin(dot(p + 0.5, vec2<f32>(93.9898, 67.345))) * 23421.631)
    );
    return r;
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let r = vec3<f32>(
        fract(sin(dot(p.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453),
        fract(sin(dot(p.yz + 0.5, vec2<f32>(93.9898, 67.345))) * 23421.631),
        fract(sin(dot(p.zx + 1.0, vec2<f32>(43.212, 12.123))) * 54235.231)
    );
    return r;
}

fn getBoidPosition(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let seed = vec3<f32>(idf * 0.1, time * 0.01, idf * 0.01);
    let h = hash3(seed);
    return h.xy * 2.0 - 1.0;
}

fn getBoidVelocity(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let seed = vec3<f32>(idf * 0.2 + 100.0, time * 0.02, idf * 0.05);
    let h = hash3(seed);
    let angle = h.x * 6.28318530718;
    return vec2<f32>(cos(angle), sin(angle)) * (0.3 + h.y * 0.5);
}

fn getBoidColor(id: u32, time: f32) -> vec3<f32> {
    let flockId = id / 30u;
    let flockCount = 6u;
    let hue = (f32(flockId % flockCount) / f32(flockCount)) + time * 0.05;
    
    let c = vec3<f32>(fract(hue) * 6.0, 1.0, 1.0);
    let i = vec3<i32>(vec3<f32>(c.x, c.x, c.x));
    let f = c.x - f32(i.x);
    let p = c.z * (1.0 - c.y);
    let q = c.z * (1.0 - f * c.y);
    let t = c.z * (1.0 - (1.0 - f) * c.y);
    
    if (i.x % 6 == 0) { return vec3<f32>(c.z, t, p); }
    if (i.x % 6 == 1) { return vec3<f32>(q, c.z, p); }
    if (i.x % 6 == 2) { return vec3<f32>(p, c.z, t); }
    if (i.x % 6 == 3) { return vec3<f32>(p, q, c.z); }
    if (i.x % 6 == 4) { return vec3<f32>(t, p, c.z); }
    return vec3<f32>(c.z, p, q);
}

fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 2.0);
}

fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

fn toneMap(hdr: vec3<f32>) -> vec3<f32> {
    return hdr / (1.0 + hdr);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let px = vec2<i32>(global_id.xy);
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    let aspect = resolution.x / resolution.y;
    var screenUV = uv * 2.0 - 1.0;
    screenUV.x *= aspect;
    
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.x *= aspect;
    let mouseActive = length(u.zoom_config.yz) > 0.001;
    
    let separationWeight = u.zoom_params.x * 2.0;
    let alignmentWeight = u.zoom_params.y * 1.5;
    let cohesionWeight = u.zoom_params.z * 1.0;
    let maxSpeed = 0.5 + u.zoom_params.w * 1.5;
    
    let neighborRadius = 0.25;
    let separationRadius = 0.08;
    let numBoids = 180u;
    
    let particle_radius = 0.015;
    let particle_opacity = 0.7;
    
    let history = textureLoad(dataTextureC, px, 0);
    
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;
    
    for (var i: u32 = 0u; i < numBoids; i = i + 1u) {
        var boidPos = getBoidPosition(i, time);
        var boidVel = getBoidVelocity(i, time);
        let boidColor = getBoidColor(i, time);
        
        var separation = vec2<f32>(0.0);
        var alignment = vec2<f32>(0.0);
        var cohesion = vec2<f32>(0.0);
        var neighborCount: u32 = 0u;
        var separationCount: u32 = 0u;
        
        for (var j: u32 = 0u; j < numBoids; j = j + 1u) {
            if (i == j) { continue; }
            let neighborPos = getBoidPosition(j, time);
            let neighborVel = getBoidVelocity(j, time);
            let diff = boidPos - neighborPos;
            let dist = length(diff);
            
            if (dist < separationRadius && dist > 0.001) {
                separation = separation + normalize(diff) / dist;
                separationCount = separationCount + 1u;
            }
            if (dist < neighborRadius) {
                alignment = alignment + neighborVel;
                cohesion = cohesion + neighborPos;
                neighborCount = neighborCount + 1u;
            }
        }
        
        if (separationCount > 0u) { separation = separation / f32(separationCount); }
        if (neighborCount > 0u) {
            alignment = alignment / f32(neighborCount);
            cohesion = (cohesion / f32(neighborCount)) - boidPos;
        }
        
        if (length(separation) > 0.0) { separation = normalize(separation) * separationWeight; }
        if (length(alignment) > 0.0) { alignment = normalize(alignment - boidVel) * alignmentWeight; }
        if (length(cohesion) > 0.0) { cohesion = normalize(cohesion) * cohesionWeight; }
        
        var mouseForce = vec2<f32>(0.0);
        if (mouseActive) {
            let toMouse = mouse - boidPos;
            let distToMouse = length(toMouse);
            if (distToMouse > 0.01) { mouseForce = normalize(toMouse) * 0.5; }
        }
        
        boidVel = boidVel + separation + alignment + cohesion + mouseForce;
        let speed = length(boidVel);
        if (speed > maxSpeed) { boidVel = normalize(boidVel) * maxSpeed; }
        boidPos = boidPos + boidVel * 0.016;
        
        if (boidPos.x > aspect) { boidPos.x = -aspect; }
        if (boidPos.x < -aspect) { boidPos.x = aspect; }
        if (boidPos.y > 1.0) { boidPos.y = -1.0; }
        if (boidPos.y < -1.0) { boidPos.y = 1.0; }
        
        let pixelToBoid = screenUV - boidPos;
        let dist = length(pixelToBoid);
        let current_speed = length(boidVel);
        
        let body_alpha = softParticleAlpha(dist, particle_radius);
        
        let velNorm = normalize(boidVel);
        let trailDir = -velNorm;
        let trailLen = 0.15 * (current_speed / maxSpeed);
        let alongTrail = dot(pixelToBoid, trailDir);
        let perpTrail = length(pixelToBoid - trailDir * alongTrail);
        
        var trail_alpha: f32 = 0.0;
        if (alongTrail > 0.0 && alongTrail < trailLen) {
            let t = alongTrail / trailLen;
            let trailWidth = particle_radius * (1.0 - t * 0.8);
            trail_alpha = (1.0 - t * t) * softParticleAlpha(perpTrail, trailWidth);
        }
        
        let perpVel = vec2<f32>(-velNorm.y, velNorm.x);
        let wingOffset = abs(dot(pixelToBoid, perpVel));
        let wingShape = 1.0 - smoothstep(0.0, particle_radius * 2.0, wingOffset);
        let headDist = length(pixelToBoid - velNorm * particle_radius * 0.5);
        let wing_alpha = wingShape * (1.0 - smoothstep(0.0, particle_radius, headDist)) * 0.5;
        
        let total_alpha = body_alpha * 1.5 + trail_alpha * 0.7 + wing_alpha * 0.3;
        let emission = 1.0 + current_speed * 2.0;
        let hdr_color = boidColor * emission;
        
        accumulated_color += hdr_color * total_alpha * particle_opacity;
        accumulated_density += total_alpha * particle_opacity;
        total_energy += total_alpha * emission;
    }
    
    accumulated_color = toneMap(accumulated_color * 0.5);
    
    let trans = transmittance(accumulated_density * 0.3);
    let final_alpha = 1.0 - trans;
    let energy_boost = min(total_energy * 0.01, 0.3);
    let final_alpha_boosted = min(final_alpha + energy_boost, 1.0);
    
    let trailDecay = 0.92;
    let history_contrib = history.rgb * trailDecay;
    let new_color = history_contrib + accumulated_color * 0.3;
    
    if (u.zoom_config.w > 0.5) { accumulated_color = accumulated_color * 1.3; }
    
    let output_color = mix(history_contrib, accumulated_color, final_alpha_boosted);
    let output = vec4<f32>(clamp(output_color, vec3<f32>(0.0), vec3<f32>(3.0)), final_alpha_boosted);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let opacity = 0.85;
    
    let finalColor = mix(inputColor.rgb, output_color, final_alpha_boosted * opacity);
    let finalAlpha = max(inputColor.a, final_alpha_boosted * opacity);
    let finalOutput = vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(3.0)), finalAlpha);
    
    textureStore(writeTexture, coord, finalOutput);
    textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalOutput);
}
```

---

### G. `gen_grok41_mandelbrot.wgsl` (current)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Buddhabrot Nebula - Orbit accumulation rendering
//  Based on Melinda Green's Buddhabrot technique (1993)
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated-accumulation
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(p2) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(p3) * 43758.5453);
}

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn escapes(c: vec2<f32>, max_iter: u32) -> bool {
    var z = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < max_iter; i = i + 1u) {
        z = cmul(z, z) + c;
        if (dot(z, z) > 4.0) { return true; }
    }
    return false;
}

fn random_c(uv: vec2<f32>, seed: vec3<f32>, view_center: vec2<f32>, view_scale: f32) -> vec2<f32> {
    let rnd = hash3(seed);
    let c = view_center + (rnd.xy - 0.5) * view_scale * 3.0;
    return c;
}

fn nebula_color(density: f32, time: f32) -> vec3<f32> {
    let d = clamp(density * 0.5, 0.0, 1.0);
    let t = time * 0.1;
    
    let deep_purple = vec3<f32>(0.1, 0.05, 0.2);
    let cosmic_blue = vec3<f32>(0.05, 0.15, 0.35);
    let nebula_cyan = vec3<f32>(0.1, 0.4, 0.5);
    let ethereal_pink = vec3<f32>(0.6, 0.3, 0.5);
    let stellar_gold = vec3<f32>(0.9, 0.7, 0.3);
    let white_core = vec3<f32>(1.0, 0.95, 0.9);
    
    var color = deep_purple;
    color = mix(color, cosmic_blue, smoothstep(0.05, 0.15, d));
    color = mix(color, nebula_cyan, smoothstep(0.1, 0.25, d) * (0.8 + 0.2 * sin(t + d * 5.0)));
    color = mix(color, ethereal_pink, smoothstep(0.15, 0.35, d) * (0.6 + 0.4 * cos(t * 0.7 + d * 3.0)));
    color = mix(color, stellar_gold, smoothstep(0.3, 0.6, d) * (0.5 + 0.5 * sin(t * 0.5)));
    color = mix(color, white_core, smoothstep(0.5, 1.0, d));
    color = color * (0.9 + 0.1 * sin(d * 10.0 + t));
    
    let glow = pow(d, 2.0) * 0.5;
    color = color + vec3<f32>(glow * 0.5, glow * 0.6, glow * 0.8);
    return color;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
    let coord = vec2<i32>(global_id.xy);
    let aspect = resolution.x / resolution.y;
    
    let zoom_center = vec2<f32>(u.zoom_params.x, u.zoom_params.y);
    let zoom_scale = u.zoom_params.z;
    let evolution_speed = u.zoom_params.w;
    
    let view_center = select(vec2<f32>(-0.5, 0.0), zoom_center, zoom_center.x != 0.0 || zoom_center.y != 0.0);
    let view_scale = select(1.0, zoom_scale, zoom_scale > 0.0);
    let speed = select(0.5, evolution_speed, evolution_speed > 0.0);
    
    let t = time * speed * 0.1;
    let c_pixel = view_center + vec2<f32>(uv.x * aspect, uv.y) * view_scale;
    
    var density: f32 = 0.0;
    var sample_count: u32 = 32u;
    let pixel_seed = vec2<f32>(f32(global_id.x), f32(global_id.y));
    
    for (var s: u32 = 0u; s < sample_count; s = s + 1u) {
        let seed = vec3<f32>(pixel_seed, f32(s) + t * 100.0);
        let c_rand = random_c(uv, seed, view_center, view_scale);
        
        if (escapes(c_rand, 64u)) {
            var z = vec2<f32>(0.0);
            var orbit_points: array<vec2<f32>, 64>;
            var orbit_len: u32 = 0u;
            
            for (var i: u32 = 0u; i < 64u && orbit_len < 64u; i = i + 1u) {
                z = cmul(z, z) + c_rand;
                if (dot(z, z) > 4.0) { break; }
                orbit_points[orbit_len] = z;
                orbit_len = orbit_len + 1u;
            }
            
            for (var i: u32 = 0u; i < orbit_len; i = i + 1u) {
                let orbit_p = orbit_points[i];
                let dist = length(orbit_p - c_pixel);
                let contribution = 1.0 / (1.0 + dist * dist * 1000.0 * view_scale);
                density = density + contribution;
            }
        }
    }
    
    let evolution = sin(t + length(c_pixel) * 3.0) * 0.1 + 1.0;
    density = density * evolution / f32(sample_count);
    density = density * 50.0;
    density = density / (1.0 + density);
    
    var color = nebula_color(density, t);
    
    let star_noise = hash3(vec3<f32>(pixel_seed * 0.01, t * 0.01));
    if (star_noise.x > 0.998) {
        let star_brightness = hash2(pixel_seed + vec2<f32>(t)).x;
        color = mix(color, vec3<f32>(1.0), star_brightness * 0.8);
    }
    
    let vignette = 1.0 - length(uv) * 0.3;
    color = color * vignette;
    color = pow(color, vec3<f32>(0.8));
    
    let presence = smoothstep(0.05, 0.2, density);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    
    let uv_norm = vec2<f32>(global_id.xy) / resolution;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv_norm, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_norm, 0.0).r;
    
    let opacity = 0.9;
    
    let generatedAlpha = mix(0.0, 1.0, presence);
    let finalColor = mix(inputColor.rgb, color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);
    
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    let finalDepth = mix(inputDepth, density, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
```

---

## Appendix: Current JSON Definitions (all generic)

All 9 shaders currently use identical generic parameter names. Replace these with domain-specific names per the integration tasks above.

### Generic template (currently used for all 9):

```json
{
  "params": [
    {"id": "param1", "name": "Intensity", "default": 0.5, "min": 0, "max": 1, "step": 0.01},
    {"id": "param2", "name": "Speed",     "default": 0.5, "min": 0, "max": 1, "step": 0.01},
    {"id": "param3", "name": "Scale",     "default": 0.5, "min": 0, "max": 1, "step": 0.01},
    {"id": "param4", "name": "Detail",    "default": 0.5, "min": 0, "max": 1, "step": 0.01}
  ]
}
```

---

*End of prompt. Ready for Claude Opus execution.*
