# Phase B: Advanced Enhancement & Innovation - Swarm Launch

**Phase Timeline:** Weeks 4-8  
**Total Shaders:** ~170 (50 upgraded + 10 new + multi-pass refactors)  
**Goal:** Upgrade complex shaders, create advanced hybrids, add audio reactivity

---

## Quick Start

```bash
# Navigate to Phase B tasks
cd projects/image_video_effects/swarm-tasks/phase-b

# View agent tasks
cat agent-1b-multi-pass-architect.md
cat agent-2b-advanced-alpha.md
cat agent-3b-advanced-hybrid-creator.md
cat agent-4b-audio-reactivity.md
cat agent-5b-final-integration.md
```

---

## Agent Task Summary

| Agent | Role | Target | Duration | Dependencies |
|-------|------|--------|----------|--------------|
| **1B** | Multi-Pass Architect | 3 huge + 50 complex | 5-7 days | Phase A complete |
| **2B** | Advanced Alpha | 50 shaders | 4-5 days | Phase A complete |
| **3B** | Advanced Hybrid Creator | 10 advanced hybrids | 5-6 days | Phase A complete |
| **4B** | Audio Reactivity | 50+ shaders | 3-4 days | 1B, 2B, 3B |
| **5B** | Final Integration | ALL outputs | 3-4 days | ALL other agents |

---

## Execution Order

### Wave 1: Foundation (Days 1-7)
Launch simultaneously:
- **Agent 1B:** Start with quantum-foam (highest priority)
- **Agent 2B:** Start with depth-layered alpha shaders
- **Agent 3B:** Start with hyper-tensor-fluid (proves concept)

### Wave 2: Volume (Days 7-14)
- **Agent 1B:** Continue with aurora-rift shaders + optimizations
- **Agent 2B:** Continue with remaining alpha modes
- **Agent 3B:** Remaining 9 advanced hybrids

### Wave 3: Enhancement (Days 14-18)
- **Agent 4B:** Audio reactivity across all suitable shaders

### Wave 4: Final QA (Days 18-22)
- **Agent 5B:** Comprehensive system review

---

## Key Technical Challenges

### Multi-Pass Architecture
```
quantum-foam-pass1.wgsl → dataTextureA
quantum-foam-pass2.wgsl → dataTextureB  
quantum-foam-pass3.wgsl → writeTexture
```

**Critical:** Passes must chain correctly through the render pipeline.

### Advanced Alpha Modes
| Mode | Complexity | Use Case |
|------|-----------|----------|
| Depth-Layered | Medium | Atmospheric effects |
| Edge-Preserve | Low | Outline/sketch effects |
| Accumulative | High | Feedback/temporal |
| Physical | High | Volumetric/glass |

### Advanced Hybrids
| Shader | FPS Target | Techniques |
|--------|-----------|------------|
| hyper-tensor-fluid | 45-60 | Tensor + Navier-Stokes |
| neural-raymarcher | 30-45 | SDF + Neural patterns |
| gravitational-lensing | 30-45 | Raytracing + Physics |
| cellular-automata-3d | 30-45 | CA + Volume raymarch |

---

## Output Locations

| Agent | Output | Location |
|-------|--------|----------|
| 1B | Multi-pass WGSL | `public/shaders/*-pass*.wgsl` |
| 1B | Optimized WGSL | `public/shaders/*.wgsl` (updates) |
| 1B | JSONs | `shader_definitions/*/*-pass*.json` |
| 2B | Advanced alpha WGSL | `public/shaders/*.wgsl` (updates) |
| 3B | Advanced hybrid WGSL | `public/shaders/*.wgsl` |
| 3B | JSONs | `shader_definitions/*/*.json` |
| 4B | Audio-reactive WGSL | `public/shaders/*.wgsl` (updates) |
| 5B | Final reports | `swarm-outputs/*` |

---

## Target Shader Lists

### Huge Shaders - Multi-Pass (Agent 1B)
1. quantum-foam (20,542 B) → 3 passes
2. aurora-rift-2 (20,873 B) → 2 passes
3. aurora-rift (20,891 B) → 2 passes

### Complex Shaders - Optimization (Agent 1B)
- tensor-flow-sculpting
- hyperbolic-dreamweaver
- stellar-plasma
- liquid-metal
- quantum-superposition
- infinite-fractal-feedback
- voronoi-glass
- kimi_liquid_glass
- gen-xeno-botanical-synth-flora
- chromatographic-separation
- ethereal-swirl
- gen-celestial-forge
- gen-biomechanical-hive
- chromatic-folds
- neural-resonance
- ... (35 more)

### Advanced Hybrids (Agent 3B)
1. hyper-tensor-fluid
2. neural-raymarcher
3. chromatic-reaction-diffusion
4. audio-voronoi-displacement
5. fractal-boids-field
6. holographic-interferometry
7. gravitational-lensing
8. cellular-automata-3d
9. spectral-flow-sorting
10. multi-fractal-compositor
11. sim-fluid-feedback-field (multi-pass fluid)
12. sim-heat-haze-field (thermal convection)
13. sim-sand-dunes (falling sand)
14. sim-ink-diffusion (reaction-diffusion ink)
15. sim-smoke-trails (volumetric smoke)
16. sim-slime-mold-growth (physarum)
17. sim-volumetric-fake (fake god rays)
18. sim-decay-system (corrosion/decay)

---

## Success Metrics

- [ ] 3 huge shaders refactored to multi-pass
- [ ] 50 complex shaders optimized
- [ ] 50 shaders with advanced alpha
- [ ] 18 advanced hybrid/simulation shaders created
- [ ] 50+ shaders with audio reactivity
- [ ] 8 multi-pass simulation effects
- [ ] 90%+ meet performance targets
- [ ] Final integration report complete
- [ ] System approved for release

---

## Gate Criteria for Completion

Project complete when:
1. All 5 Phase B agents complete tasks
2. Agent 5B approves final integration
3. No critical issues in final report
4. Performance benchmarks pass
5. All deliverables generated

---

## Questions?

See the main specification: `swarm-spec-shader-upgrade-phases.yaml`

See technical reference: `swarm-technical-reference.md`

See Phase A docs: `swarm-tasks/phase-a/README.md`
