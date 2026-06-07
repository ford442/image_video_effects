# Shader Pipeline Enhancement Plan
## Multi-Pass, 64-bit Color, Dynamic Configuration

---

## Current System (Immutable Baseline)

```
Input → Slot 0 Shader → Slot 1 Shader → Slot 2 Shader → texture.wgsl → Screen
              ↓              ↓              ↓
         pingPong1      pingPong2      writeTexture
```

**Fixed:** 3 compute slots + 1 render pass, 13 bindings, uniform structure
**Variable:** WGSL shader code, JSON definition

---

## Enhancement Strategy: "Shader-Managed Pipeline"

Instead of modifying Renderer.ts, we encode pipeline instructions in the shader definition JSON. The shader uses the existing `dataTextureA/B/C` and `extraBuffer` for multi-pass state.

### 1. Multi-Pass Within Single Shader (Pseudo-Passes)

Use ping-pong inside one compute shader for iterative effects:

```wgsl
// ═══════════════════════════════════════════════════════════════
// Multi-Pass Simulation Shader
// Iterates 4 times per frame using dataTextureA for state
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = global_id.xy;
    let resolution = u.config.zw;
    
    // Load previous state from dataTextureA
    var state = textureLoad(dataTextureC, coord, 0);
    
    // PASS 1: Reaction-Diffusion Gray-Scott
    let gs = grayScottIteration(coord, resolution);
    
    // PASS 2: Curl noise advection
    let velocity = curlNoise(vec2<f32>(coord) / resolution);
    
    // PASS 3: Color mapping based on concentration
    let color = mapConcentrationToColor(gs);
    
    // PASS 4: Bloom accumulation into dataTextureA
    let bloom = calculateBloom(coord, resolution);
    
    // Store state for next frame
    textureStore(dataTextureA, coord, vec4<f32>(gs, 0.0, 1.0));
    
    // Write final output
    textureStore(writeTexture, coord, color + bloom);
}
```

### 2. 64-bit High-Gamut Color Pipeline

WebGPU doesn't support 64-bit floats in textures, BUT we can:
- Use `rgba32float` (32-bit per channel = 128-bit per pixel!)
- Store HDR values > 1.0
- Tone-map in the final pass

```wgsl
// HDR Accumulation - values can exceed 1.0
var hdrColor: vec4<f32> = vec4<f32>(0.0);

// Accumulate multiple light sources
hdrColor += light1 * 2.5;  // Overbright
hdrColor += light2 * 4.0;  // Super bright
hdrColor += bloom * 0.5;

// Tone mapping (ACES-like)
let ldrColor = acesToneMap(hdrColor);

textureStore(writeTexture, coord, vec4<f32>(ldrColor, 1.0));
```

### 3. Dynamic Pass Configuration (JSON-Driven)

Extend shader JSON with pipeline hints:

```json
{
  "id": "quantum-plasma-2.0",
  "name": "Quantum Plasma 2.0",
  "category": "generative",
  "pipeline": {
    "iterations_per_frame": 4,
    "use_data_texture_a": true,
    "use_data_texture_b": true,
    "accumulation_mode": "additive",
    "tonemap": "aces",
    "output_format": "hdr"
  },
  "uniforms": {
    "param1": { "label": "Quantum Foam", "default": 0.5 },
    "param2": { "label": "Entanglement", "default": 0.3 },
    "param3": { "label": "Bloom Strength", "default": 0.4 },
    "param4": { "label": "Iterations", "default": 0.5 }
  },
  "features": ["multi-pass", "hdr", "audio-reactive"]
}
```

### 4. Post-Processing Stack (Slot-Based)

Use the 3 slots as a post-processing pipeline:

```
Slot 0: Base Effect (e.g., reaction-diffusion)
Slot 1: Bloom/Blur pass (reads from Slot 0)
Slot 2: Color grading + Vignette (reads from Slot 1)
```

Dedicated post-processing shaders:

```json
{
  "id": "pp-bloom",
  "name": "Bloom Post-Process",
  "category": "post-processing",
  "type": "effect",
  "inputs": ["previous_slot"],
  "uniforms": {
    "param1": { "label": "Bloom Radius", "default": 0.3 },
    "param2": { "label": "Intensity", "default": 0.5 }
  }
}
```

---

## Advanced Techniques Within Constraints

### A. Temporal Accumulation (Path Tracing-Style)

```wgsl
// Accumulate over time for smoother results
let frameCount = u.config.y; // Mouse click count as frame counter
let previous = textureLoad(dataTextureC, coord, 0);
let current = renderScene(coord);

// Progressive blend
let blend = 1.0 / f32(frameCount + 1);
let accumulated = mix(previous, current, blend);

textureStore(dataTextureA, coord, accumulated);
textureStore(writeTexture, coord, accumulated);
```

### B. Multi-Species Ecosystems

Use different color channels for different species:

```wgsl
// dataTextureA.r = Species A (predator)
// dataTextureA.g = Species B (prey)  
// dataTextureA.b = Chemical signal
// dataTextureA.a = Energy/diffusion rate

let ecosystem = textureLoad(dataTextureC, coord, 0);

// Predator-prey dynamics
let predator = ecosystem.r;
let prey = ecosystem.g;

let newPredator = predator + dt * (predatorGrowth(predator, prey) - predatorDeath(predator));
let newPrey = prey + dt * (preyGrowth(prey) - predation(predator, prey));

textureStore(dataTextureA, coord, vec4<f32>(newPredator, newPrey, ecosystem.b, ecosystem.a));
```

### C. Audio-Reactive Birth/Death

```wgsl
// Audio drives spawn rate
let audioPulse = u.zoom_config.z; // Audio bass
let spawnRate = 0.01 + audioPulse * 0.1;

// Random spawn based on audio
if (random(coord + u.config.x) < spawnRate) {
    state = vec4<f32>(1.0, 0.0, 0.0, 1.0); // Spawn new agent
}
```

---

## Implementation Roadmap

### Phase 1: Enhanced Shader Templates (This Week)

Create template shaders demonstrating:
- [ ] Multi-iteration within compute shader
- [ ] HDR accumulation + tone mapping
- [ ] Temporal smoothing
- [ ] Multi-species simulation

### Phase 2: Post-Processing Library (Next Week)

Create dedicated post-process shaders:
- [ ] `pp-bloom.wgsl` - Gaussian blur bloom
- [ ] `pp-chromatic.wgsl` - RGB shift aberration
- [ ] `pp-vignette.wgsl` - Vignette + film grain
- [ ] `pp-tone-map.wgsl` - ACES/Hable/Uncharted tone mapping

### Phase 3: Pipeline Presets

JSON presets for common pipelines:
```json
{
  "preset": "cinematic-glow",
  "slots": [
    { "shader": "reaction-diffusion", "params": {...} },
    { "shader": "pp-bloom", "params": {"intensity": 0.6} },
    { "shader": "pp-tone-map", "params": {"curve": "aces"} }
  ]
}
```

### Phase 4: UI Integration

- Show "Pipeline Depth" indicator in Controls.tsx
- Visual pass chain diagram
- "One-click presets" for common looks

---

## 64-bit Precision Simulation

While we can't use f64 in WGSL, we can simulate higher precision:

```wgsl
// Double-single arithmetic for critical calculations
struct f64 {
  high: f32,  // Upper bits
  low: f32,   // Lower bits
};

// Or use integer coordinates for precise positioning
let preciseCoord = vec2<i32>(global_id.xy);
let worldPos = vec2<f32>(preciseCoord) / 1000000.0; // Sub-pixel precision
```

---

## Wide Gamut Color Spaces

Output in Rec.2020 or DCI-P3:

```wgsl
// Linear to Rec.2020
fn srgbToRec2020(c: vec3<f32>) -> vec3<f32> {
    let r = dot(c, vec3<f32>(0.6274, 0.3293, 0.0433));
    let g = dot(c, vec3<f32>(0.0691, 0.9195, 0.0114));
    let b = dot(c, vec3<f32>(0.0164, 0.0880, 0.8956));
    return vec3<f32>(r, g, b);
}
```

---

## Success Metrics

An upgrade is successful if:
1. ✅ Visual richness increases (more layers, depth, "living" quality)
2. ✅ HDR values exceed [0,1] and tone-map gracefully
3. ✅ Multi-frame accumulation creates smoother results
4. ✅ Frame rate stays >30fps on mid-tier GPU
5. ✅ Code elegance improves (not just longer)

---

## Next Actions

1. **Create template shader** demonstrating all techniques
2. **Upgrade 3 low-rated shaders** using the new patterns
3. **Add "Pipeline Info"** display to Controls.tsx
4. **Create post-processing shader library** (5 core effects)

Want me to:
- A) Create the master template shader with all techniques?
- B) Upgrade a specific shader (e.g., gen_orb) to 2.0?
- C) Create the post-processing shader library?
- D) Add pipeline visualization to Controls.tsx?
