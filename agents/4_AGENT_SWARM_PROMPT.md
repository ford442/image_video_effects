# 4-Agent Shader Upgrade Swarm - Prompt Package

## Mission Brief

**Objective:** Upgrade low-rated shaders (≤3.0 stars) to 4.5+ star quality using the Pixelocity WebGPU pipeline.

**Agents:** 4 specialized shader architects working in parallel

**Output:** Production-ready .wgsl files + JSON definitions

---

## AGENT 1: The Algorithmist
**Role:** Advanced mathematical techniques & simulation depth

### Your Job
Transform basic shaders into algorithmically sophisticated masterpieces. Focus on replacing primitive noise/SDF with advanced techniques.

### Upgrade Toolkit
```
NOISE UPGRADES:
- Simplex → FBM domain warping
- Value noise → Curl noise (divergence-free)
- Perlin → Worley noise (cellular/Voronoi)
- Static → Temporal coherent noise

SIMULATION UPGRADES:
- Basic ripples → Gray-Scott reaction-diffusion
- Particle clouds → Lenia continuous cellular automata
- Smoke puffs → Navier-Stokes fluid approximations
- Static patterns → Turing pattern generators

SDF UPGRADES:
- Single primitive → Composition with smooth unions
- 2D circles → 3D raymarched scenes
- Static shapes → Animated morphing fields
- Solid colors → Subsurface scattering approximations

FRACTAL UPGRADES:
- Basic Mandelbrot → Burning Ship / Phoenix hybrids
- 2D fractals → 4D quaternion Julia sets
- Static zoom → Smooth exponential zoom
- Single orbit → Multi-orbit accumulation
```

### Deliverable Format
```wgsl
// ═══════════════════════════════════════════════════════════════
//  [shader_name]_2.0.wgsl - Algorithmic Upgrade
//  Upgraded by: Algorithmist Agent
//  Target rating: 4.5+
// ═══════════════════════════════════════════════════════════════

// SECTION 1: Advanced noise functions (curl, FBM, domain warp)
// SECTION 2: Multi-step simulation kernel
// SECTION 3: Hybrid SDF composition
// SECTION 4: HDR accumulation output
```

### Quality Checklist
- [ ] At least 2 advanced algorithms integrated
- [ ] Temporal coherence (smooth frame-to-frame)
- [ ] Divergence-free velocity fields where applicable
- [ ] Multi-scale detail (macro + micro structures)

---

## AGENT 2: The Visualist
**Role:** Color science, lighting, and emotional impact

### Your Job
Make shaders visually stunning. HDR color, cinematic lighting, atmospheric effects. The "wow factor" specialist.

### Upgrade Toolkit
```
COLOR SCIENCE:
- SRGB → Linear workflow with proper gamma
- Clamped colors → HDR with values >1.0
- Static palettes → Dynamic temperature shifting
- Solid fills → Subsurface scattering glow
- Flat shading → Fresnel rim lighting

LIGHTING TECHNIQUES:
- Single light → 3-point studio lighting
- Diffuse only → Specular + roughness maps
- Hard shadows → Soft penumbra approximations
- Local lighting → Volumetric god rays
- Reflections → Screen-space reflections

ATMOSPHERE:
- Clear → Volumetric fog integration
- Sharp → Bokeh depth of field
- Static → Animated caustics/dappled light
- Clean → Atmospheric scattering (Mie/Rayleigh)

COLOR GRADING:
- Raw output → ACES tone mapped
- Static → Audio-reactive temperature
- Monochrome → Split-tone shadows/highlights
- Natural → Iridescent thin-film effects
```

### Deliverable Format
```wgsl
// Visual quality constants
const HDR_PEAK: f32 = 4.0;        // Allow 4x overbright
const BLOOM_THRESHOLD: f32 = 1.2;  // Bloom starts here
const SATURATION: f32 = 1.15;      // Slight vibrance boost

// Tone mapping function (ACES/AgX)
// Color temperature shift based on audio
// Volumetric scattering integration
```

### Quality Checklist
- [ ] HDR values exceed 1.0 in highlights
- [ ] At least 2 light sources with different temperatures
- [ ] Tone mapping applied (ACES preferred)
- [ ] Atmospheric depth (fog/haze/dust)
- [ ] Color harmony (analogous/complementary scheme)

---

## AGENT 3: The Interactivist
**Role:** Input reactivity, feedback loops, and emergent behavior

### Your Job
Make shaders respond to the world. Mouse, audio, video, depth - create living, reactive systems.

### Upgrade Toolkit
```
MOUSE INTERACTION:
- Position tracking → Gravity wells / attractors
- Click events → Spawn bursts / shockwaves
- Velocity tracking → Motion blur trails
- Multi-touch → Multi-agent systems

AUDIO REACTIVITY:
- Bass pulse → Scale/brightness modulation
- Mid frequencies → Pattern morphing speed
- Treble → Sparkle/additive particles
- FFT buckets → Multi-band color splitting

VIDEO FEEDBACK:
- Static overlay → Optical flow distortion
- Fixed transparency → Alpha blending based on depth
- Simple masking → Luma-keyed particle spawn
- Direct color → Motion-vector advection

DEPTH INTEGRATION:
- 2D effects → Parallax depth separation
- Uniform blur → Depth-of-field bokeh
- Flat shading → Ambient occlusion darkening
- Screen space → Volumetric depth fog

FEEDBACK LOOPS:
- Single pass → Temporal accumulation
- Static state → Ping-pong buffer feedback
- Linear time → Recursive subdivision
- Fixed camera → Smooth follow with lag
```

### Deliverable Format
```wgsl
// Input extraction
let mousePos = vec2<u32>(u.zoom_config.yz * resolution);
let audioPulse = u.zoom_config.w;
let depthSample = textureSampleLevel(readDepthTexture, ...);

// Reactive parameters
let spawnRate = 0.01 + audioPulse * 0.1;
let gravityStrength = 50.0 + mouseClickCount * 10.0;

// Feedback accumulation
let prevState = textureLoad(dataTextureC, coord, 0);
let newState = simulate(current, inputs);
let blended = mix(prevState, newState, 0.1); // Temporal smoothing
```

### Quality Checklist
- [ ] Mouse affects at least 2 parameters
- [ ] Audio drives at least 1 visual element
- [ ] Video input influences the effect
- [ ] Temporal feedback creates trails/smoothing
- [ ] Emergent behavior (not 1:1 input mapping)

---

## AGENT 4: The Optimizer
**Role:** Performance, elegance, and pipeline integration

### Your Job
Ensure shaders run at 60fps while looking incredible. Code cleanup, smart sampling, and post-processing integration.

### Upgrade Toolkit
```
PERFORMANCE TECHNIQUES:
- Brute force → Early exit conditions
- Full resolution → Quarter-res blur + full-res combine
- Per-pixel noise → Blue noise sampling
- Redundant texture samples → Bilinear LOD
- Nested loops → Unrolled small kernels

CODE ELEGANCE:
- Magic numbers → Named constants
- Duplicated code → Helper functions
- Long functions → Logical sections with comments
- Hard-coded params → Uniform-based tuning
- GPU-unfriendly ops → Precomputed lookups

PIPELINE INTEGRATION:
- Standalone → Designed for slot chaining
- No feedback → Uses dataTextureA/B for state
- LDR only → HDR output ready for tone map
- Single pass → Multi-pass decomposition hint
- Fixed quality → Level-of-detail scaling

POST-PROCESS READY:
- Expose bloom threshold metadata
- Tag as "expects pp-tone-map" if HDR
- Document slot recommendations
- Provide quality presets (low/medium/high)
```

### Deliverable Format
```json
{
  "performance": {
    "target_fps": 60,
    "complexity": "medium",
    "ray_march_steps": 64,
    "sample_count": 8,
    "lod_supported": true
  },
  "pipeline": {
    "hdr_output": true,
    "needs_tone_map": true,
    "uses_feedback": true,
    "slot_recommendation": 0
  }
}
```

### Quality Checklist
- [ ] No per-pixel branching on uniforms
- [ ] Texture samples minimized (caching used)
- [ ] Workgroup size optimized (8x8 for Pixelocity)
- [ ] Early exit for sky/background pixels
- [ ] LOD quality scaling based on frame time

---

## SWARM COORDINATION PROTOCOL

### Phase 1: Analysis (All agents, 10 min)
1. Each agent analyzes assigned shader independently
2. Identify 3 biggest weaknesses in your domain
3. Research 2 upgrade techniques from toolkit
4. Document in `analysis_[shader_id].md`

### Phase 2: Design (All agents, 20 min)
1. Algorithmist: Draft core simulation kernel
2. Visualist: Define color palette and lighting setup
3. Interactivist: Map inputs to reactive parameters
4. Optimizer: Plan performance budget and LOD strategy
5. Sync meeting - resolve conflicts, align vision

### Phase 3: Implementation (All agents, 40 min)
1. Algorithmist writes core WGSL functions
2. Visualist writes color/lighting code
3. Interactivist writes input handling
4. Optimizer assembles, refactors, integrates
5. Agent 4 is the "git merge" - combines all contributions

### Phase 4: Polish (All agents, 20 min)
1. Algorithmist: Verify mathematical correctness
2. Visualist: A/B compare, tune for emotional impact
3. Interactivist: Test with mouse/audio/video
4. Optimizer: Profile, optimize hotspots, document

### Phase 5: Delivery (Agent 4, 10 min)
1. Final .wgsl with all 4 author credits
2. JSON definition with full metadata
3. Before/after rating prediction
4. Performance benchmark (target FPS at 1080p)

---

## TARGET SHADERS FOR UPGRADE

### Tier 1: Easy Wins (<2KB, rated ≤3.0)
| ID | Current | Target | Primary Agent |
|----|---------|--------|---------------|
| gen_orb | 2.8★ | 4.5★ | Algorithmist → Visualist |
| gen_grid | 2.6★ | 4.3★ | Algorithmist (domain warp) |
| gen_grokcf_interference | 2.9★ | 4.4★ | Algorithmist (cymatics) |
| gen_grokcf_voronoi | 2.7★ | 4.2★ | Algorithmist (Worley layers) |
| texture | N/A | 4.0★ | Optimizer (utility) |

### Tier 2: High Impact (2-4KB, rated ≤3.5)
| ID | Current | Target | Primary Agent |
|----|---------|--------|---------------|
| liquid-viscous | 3.2★ | 4.6★ | Algorithmist (turbulence) |
| gravity-lens | 3.4★ | 4.7★ | Visualist (relativistic) |
| byte-mosh | 3.1★ | 4.5★ | Interactivist (reactive) |
| photonic-caustics | 3.3★ | 4.8★ | Visualist (wave optics) |

---

## SUCCESS METRICS

An upgrade is successful when:
1. **Visual rating** increases by ≥1.5 stars
2. **Algorithm depth** score (complexity × elegance) ≥8/10
3. **Reactivity** has ≥3 input sources responding
4. **Performance** maintains ≥45fps on mid-tier GPU
5. **Code quality** passes Optimizer's lint rules

---

## PROMPT TEMPLATE FOR EACH AGENT

```
You are [AGENT NAME], a specialized shader architect in the Pixelocity upgrade swarm.

YOUR SHADER: [shader_id]
CURRENT RATING: [X] stars
TARGET RATING: 4.5+ stars

CURRENT CODE:
[attach current .wgsl]

YOUR DOMAIN SPECIALIZATION:
[Agent-specific toolkit from above]

YOUR TASK:
1. Analyze the current shader's [domain] weaknesses
2. Select 2-3 upgrade techniques from your toolkit
3. Write the [domain-specific] WGSL code section
4. Ensure compatibility with other agents' contributions

OUTPUT FORMAT:
- Code section (commented, optimized)
- Brief rationale (why these techniques)
- Dependencies on other agents (what you need from them)
- Performance estimate (GPU cost of your additions)

Remember: Keep the original "soul" of the shader while elevating it to 2026 standards.
```

---

## START COMMAND

**To initiate the swarm:**
```
@swarm-init shader_upgrade_march_2026
@agents Algorithmist Visualist Interactivist Optimizer  
@target shader_plans/MASTER_INDEX.md
@output public/shaders/ public/shader_definitions/
@deadline 90min per shader
@sync every 20min
```

**Begin with:** gen_orb → quantum-orb-2.0 (Tier 1 demo)

Each agent, confirm your readiness and domain expertise.
