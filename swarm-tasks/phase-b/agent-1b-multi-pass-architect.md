# Agent 1B: Multi-Pass Architecture Specialist
## Task Specification - Phase B, Agent 1

**Role:** Complex Shader Refactoring Engineer  
**Priority:** CRITICAL  
**Target:** 3 huge shaders + 50 complex shader optimizations  
**Estimated Duration:** 5-7 days

---

## Mission

Refactor oversized shaders into multi-pass pipelines and optimize complex shaders for better performance. Target the "Huge" shaders (>16KB) and complex shaders (5-8KB) that need architectural improvements.

---

## Target Shader Files

### Tier 1: Huge Shaders - COMPLETE REFACTOR (3 shaders)
These need to be split into multi-pass pipelines:

| # | Shader | Size | Strategy |
|---|--------|------|----------|
| 1 | quantum-foam | 20,542 B | Split into 3 passes: field gen → particle sim → compositing |
| 2 | aurora-rift-2 | 20,873 B | Split into 2 passes: raymarch → color grading |
| 3 | aurora-rift | 20,891 B | Split into 2 passes: raymarch → color grading |

### Tier 2: Complex Shaders - OPTIMIZATION (50 shaders)
Selected high-value targets for optimization:

| Shader | Current Size | Optimization Strategy |
|--------|--------------|----------------------|
| tensor-flow-sculpting | 268 lines | Add early-exit, reduce FBM octaves based on distance |
| hyperbolic-dreamweaver | 124 lines | Add LOD, cache hyperbolic coords |
| stellar-plasma | 144 lines | Precompute noise, add audio reactivity hooks |
| liquid-metal | 193 lines | Add parameter randomization, optimize normal calc |
| quantum-superposition | 115 lines | Add depth integration, optimize loops |
| infinite-fractal-feedback | ~300 lines | Optimize feedback buffer usage |
| voronoi-glass | ~150 lines | Add chromatic dispersion, optimize cell calc |
| kimi_liquid_glass | ~170 lines | Add hybrid features, optimize refraction |
| gen-xeno-botanical-synth-flora | 287 lines | Add more params, optimize raymarch |
| chromatographic-separation | ~200 lines | Add new color modes, optimize separation |
| ethereal-swirl | ~400 lines | Multi-pass decomposition |
| gen-celestial-forge | ~350 lines | Optimize particle systems |
| gen-biomechanical-hive | ~320 lines | SDF optimization, early exit |
| chromatic-folds | ~350 lines | Geometric simplification |
| neural-resonance | ~320 lines | Neural pattern optimization |
| ... (35 more) | | |

---

## Multi-Pass Architecture

### What is Multi-Pass?

Multi-pass shaders split computation across multiple compute shader dispatches:

```
Pass 1: Generate intermediate data → writeTexture/dataTextureA
Pass 2: Read intermediate → process → writeTexture
```

### When to Use Multi-Pass

| Scenario | Solution |
|----------|----------|
| Shader >15KB | Split into multiple passes |
| Expensive noise generation | Pass 1: Precompute, Pass 2: Sample |
| Multiple independent effects | Each effect = one pass |
| Feedback/iteration required | Ping-pong between textures |
| Complex SDF scenes | Pass 1: SDF, Pass 2: Shading |

### Multi-Pass JSON Schema

```json
{
  "id": "my-shader-pass1",
  "name": "My Shader (Pass 1)",
  "url": "shaders/my-shader-pass1.wgsl",
  "category": "simulation",
  "features": ["multi-pass-1"],
  "multipass": {
    "pass": 1,
    "totalPasses": 2,
    "nextShader": "my-shader-pass2"
  }
}
```

---

## Refactoring Strategies

### Strategy 1: Data Generation + Compositing (quantum-foam)

**Current:** Single 20KB monolithic shader
**Refactored:** 3-pass pipeline

```
Pass 1 (quantum-foam-field):
  - Generate quantum field
  - Output to dataTextureA
  - ~6KB

Pass 2 (quantum-foam-particles):
  - Advect particles through field
  - Sample dataTextureA
  - Output to dataTextureB
  - ~8KB

Pass 3 (quantum-foam-composite):
  - Read particle data from dataTextureB
  - Apply color grading, glow
  - Final output to writeTexture
  - ~6KB
```

**Implementation:**
```wgsl
// PASS 1: quantum-foam-field.wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    
    // Generate complex field
    let field = generateQuantumField(uv, u.config.x);
    
    // Store for Pass 2
    textureStore(dataTextureA, gid.xy, field);
    
    // Minimal color output
    textureStore(writeTexture, gid.xy, vec4<f32>(0.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(0.0));
}

// PASS 2: quantum-foam-particles.wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    
    // Read field from Pass 1
    let field = textureLoad(dataTextureA, gid.xy, 0);
    
    // Advect particles
    let particles = advectParticles(uv, field, u.config.x);
    
    // Store for Pass 3
    textureStore(dataTextureB, gid.xy, particles);
    
    // Pass-through color
    textureStore(writeTexture, gid.xy, vec4<f32>(0.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(0.0));
}

// PASS 3: quantum-foam-composite.wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    
    // Read particles from Pass 2
    let particles = textureLoad(dataTextureB, gid.xy, 0);
    
    // Final compositing
    let color = compositeParticles(particles, uv);
    
    // Get depth (if applicable)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    textureStore(writeTexture, gid.xy, color);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

### Strategy 2: Raymarch + Post (aurora-rift)

**Current:** Single massive raymarcher
**Refactored:** 2-pass pipeline

```
Pass 1 (aurora-rift-raymarch):
  - Raymarch volumetric aurora
  - Store: color + density + depth
  - ~12KB

Pass 2 (aurora-rift-grade):
  - Apply atmospheric scattering
  - Color grading, tone mapping
  - Final composite
  - ~8KB
```

### Strategy 3: Optimization Without Multi-Pass

For shaders that don't need multi-pass but can be optimized:

#### Early Exit Optimization
```wgsl
// BEFORE: Full calculation for all pixels
fn expensiveFunction(uv: vec2<f32>) -> vec3<f32> {
    // ... 100 lines of math ...
}

// AFTER: Early exit for edge cases
fn expensiveFunction(uv: vec2<f32>) -> vec3<f32> {
    // Early exit for off-screen or simple cases
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec3<f32>(0.0);
    }
    
    // Check if effect applies to this region
    let effectMask = getEffectMask(uv);
    if (effectMask < 0.01) {
        return textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }
    
    // ... rest of calculation ...
}
```

#### Distance-Based LOD
```wgsl
// Reduce octaves based on distance from camera/interest point
let dist = length(uv - center);
let octaves = i32(mix(8.0, 2.0, smoothstep(0.0, 0.5, dist)));
let noise = fbmLOD(uv, octaves);
```

#### Precompute Constants
```wgsl
// BEFORE: Computing inside loop
for (var i = 0; i < 100; i++) {
    let angle = f32(i) * 6.28318 / 100.0 + u.config.x;
    // ...
}

// AFTER: Precompute outside loop
let time = u.config.x;
let invCount = 1.0 / 100.0;
for (var i = 0; i < 100; i++) {
    let angle = f32(i) * 6.28318 * invCount + time;
    // ...
}
```

#### Branchless Where Possible
```wgsl
// BEFORE: Branch
if (condition) {
    color = colorA;
} else {
    color = colorB;
}

// AFTER: Mix (branchless)
color = mix(colorB, colorA, f32(condition));

// Or using WGSL select
color = select(colorB, colorA, condition);
```

---

## Specific Shader Refactoring Plans

### quantum-foam → 3-Pass System

**Analysis:** 20KB shader likely has:
- Complex field generation
- Particle system
- Volumetric rendering

**Refactoring:**
```yaml
Pass 1 (quantum-foam-field):
  Purpose: Generate quantum probability field
  Outputs: dataTextureA (field RGBA)
  Size Estimate: 6KB
  
Pass 2 (quantum-foam-particles):
  Purpose: Particle advection through field
  Inputs: dataTextureA (field)
  Outputs: dataTextureB (particle RGBA)
  Size Estimate: 8KB
  
Pass 3 (quantum-foam-render):
  Purpose: Volumetric rendering + compositing
  Inputs: dataTextureB (particles)
  Outputs: writeTexture, writeDepthTexture
  Size Estimate: 6KB
```

### aurora-rift → 2-Pass System

**Analysis:** Complex volumetric raymarching with atmospheric effects

**Refactoring:**
```yaml
Pass 1 (aurora-rift-volumetric):
  Purpose: Raymarch aurora volume
  Outputs: writeTexture (RGBA color + density), writeDepthTexture
  Size Estimate: 12KB
  
Pass 2 (aurora-rift-atmosphere):
  Purpose: Atmospheric scattering + grading
  Inputs: readTexture (Pass 1 output)
  Outputs: writeTexture (final), writeDepthTexture
  Size Estimate: 8KB
```

### tensor-flow-sculpting → Optimized Single Pass

**Analysis:** 268 lines, uses tensor math but can be optimized

**Optimizations:**
1. Early exit for flat regions
2. Reduce FBM octaves based on effect strength
3. Cache eigenvalue calculations
4. Precompute rotation matrices

**Expected:** 268 lines → ~200 lines, 20% performance boost

---

## Output Requirements

### For Multi-Pass Refactors (3 huge shaders)

1. **WGSL Files:** `{name}-pass1.wgsl`, `{name}-pass2.wgsl`, etc.
2. **JSON Definitions:** Each pass gets its own JSON with `multipass` metadata
3. **Documentation:** Refactoring notes explaining the split

### For Optimized Shaders (50 complex shaders)

1. **Optimized WGSL:** Same filename, improved code
2. **Optimization Report:** Before/after comparison
3. **Performance Notes:** Expected FPS improvement

---

## Deliverables Checklist

### Multi-Pass Refactoring
- [ ] quantum-foam-pass1.wgsl + JSON
- [ ] quantum-foam-pass2.wgsl + JSON
- [ ] quantum-foam-pass3.wgsl + JSON
- [ ] aurora-rift-pass1.wgsl + JSON
- [ ] aurora-rift-pass2.wgsl + JSON
- [ ] aurora-rift-2-pass1.wgsl + JSON
- [ ] aurora-rift-2-pass2.wgsl + JSON

### Optimized Shaders (sample)
- [ ] tensor-flow-sculpting.wgsl (optimized)
- [ ] hyperbolic-dreamweaver.wgsl (optimized)
- [ ] stellar-plasma.wgsl (optimized)
- [ ] liquid-metal.wgsl (optimized)
- [ ] quantum-superposition.wgsl (optimized)
- [ ] ... (45 more)

### Documentation
- [ ] Multi-pass refactoring guide
- [ ] Optimization patterns document
- [ ] Performance comparison report

---

## Success Criteria

- All 3 huge shaders refactored to multi-pass
- 50 complex shaders optimized
- Average 20% performance improvement
- No visual regression
- Multi-pass shaders chain correctly
- All maintain randomization safety

---

## Key Patterns Reference

### Multi-Pass Data Flow
```
Slot 0 (Pass 1) → pingPongTexture1
Slot 1 (Pass 2) → pingPongTexture2  
Slot 2 (Pass 3) → writeTexture
```

### Texture Binding in Multi-Pass
Pass 2 reads from `readTexture` (which contains Pass 1 output)
Pass 3 reads from `readTexture` (which contains Pass 2 output)

### Data Texture Usage
Use `dataTextureA`, `dataTextureB` for intermediate data that isn't color
