# Phase A: Foundation & Seeding - Swarm Launch

**Phase Timeline:** Weeks 1-3  
**Total Shaders:** 81 (61 upgraded + 20 new)  
**Goal:** Upgrade smallest shaders with RGBA support, create new hybrid/generative shaders

---

## Quick Start

```bash
# Navigate to swarm tasks
cd projects/image_video_effects/swarm-tasks/phase-a

# View agent tasks
cat agent-1a-alpha-channel-specialist.md
cat agent-2a-shader-surgeon.md
cat agent-3a-parameter-randomization.md
cat agent-4a-generative-creator.md
cat agent-5a-quality-assurance.md
```

---

## Agent Task Summary

| Agent | Role | Target | Duration | Dependencies |
|-------|------|--------|----------|--------------|
| **1A** | Alpha Channel Specialist | 61 shaders (Tiny + Small) | 3-4 days | None |
| **2A** | Shader Surgeon | 10 hybrid shaders | 4-5 days | None |
| **3A** | Randomization Engineer | All Phase A shaders | 2-3 days | 1A, 2A, 4A |
| **4A** | Generative Creator | 10 generative shaders | 4-5 days | None |
| **5A** | Quality Assurance | All outputs | 2-3 days | 1A, 2A, 3A, 4A |

---

## Execution Order

### Wave 1: Parallel Development (Days 1-4)
Launch simultaneously:
- Agent 1A: RGBA upgrades on tiny shaders first
- Agent 2A: Chunk extraction + first hybrid
- Agent 4A: First 5 generative shaders

### Wave 2: Parallel Development (Days 4-7)
- Agent 1A: Continue with small shaders
- Agent 2A: Remaining hybrids
- Agent 4A: Remaining generative shaders

### Wave 3: Validation (Days 7-10)
- Agent 3A: Randomization validation on all outputs

### Wave 4: Final QA (Days 10-13)
- Agent 5A: Comprehensive review

---

## Output Locations

| Agent | Output | Location |
|-------|--------|----------|
| 1A | Upgraded WGSL files | `public/shaders/*.wgsl` |
| 1A | Updated JSON defs | `shader_definitions/{category}/*.json` |
| 2A | Chunk library doc | `swarm-outputs/chunk-library.md` |
| 2A | Hybrid WGSL files | `public/shaders/hybrid-*.wgsl` |
| 2A | Hybrid JSON defs | `shader_definitions/*/hybrid-*.json` |
| 3A | Validation report | `swarm-outputs/randomization-report.md` |
| 3A | Fixed shader files | `public/shaders/*.wgsl` (updates) |
| 4A | Generative WGSL files | `public/shaders/gen-*.wgsl` |
| 4A | Generative JSON defs | `shader_definitions/generative/gen-*.json` |
| 5A | QA report | `swarm-outputs/phase-a-qa-report.md` |
| 5A | Integration summary | `swarm-outputs/phase-a-complete.md` |

---

## Key Technical References

### Standard Header (ALL shaders must use)
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {SHADER_NAME}
//  Category: {CATEGORY}
//  Features: {features}
//  {Upgraded/Created}: 2026-03-22
//  By: {AGENT}
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
```

### Alpha Calculation Patterns

**Luminance-based:**
```wgsl
let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
let alpha = mix(0.7, 1.0, luma);
```

**Depth-aware:**
```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
let alpha = mix(0.6, 1.0, depth);
```

**Effect intensity:**
```wgsl
let alpha = mix(0.5, 1.0, effectStrength);
```

### Randomization-Safe Parameters

```wgsl
// Safe division
let scale = 1.0 / (param + 0.001);

// Safe log
let val = log(param + 0.001);

// Safe sqrt
let dist = sqrt(max(value, 0.0));

// Safe alpha
let alpha = max(calculatedAlpha, 0.1);
```

---

## Target Shader Lists

### Tiny Shaders (< 2KB) - Agent 1A Priority 1
1. texture (719 B)
2. gen_orb (1,402 B)
3. gen_grokcf_interference (1,535 B)
4. gen_grid (1,594 B)
5. gen_grokcf_voronoi (1,630 B)
6. gen_grok41_plasma (1,648 B)
7. galaxy (1,682 B)
8. gen_trails (1,878 B)
9. gen_grok41_mandelbrot (1,883 B)

### Hybrid Shaders to Create - Agent 2A
1. hybrid-noise-kaleidoscope
2. hybrid-sdf-plasma
3. hybrid-chromatic-liquid
4. hybrid-cyber-organic
5. hybrid-voronoi-glass
6. hybrid-fractal-feedback
7. hybrid-magnetic-field
8. hybrid-particle-fluid
9. hybrid-reaction-diffusion-glass
10. hybrid-spectral-sorting

### Generative + Temporal Shaders to Create - Agent 4A
1. gen-neural-fractal
2. gen-voronoi-crystal
3. gen-audio-spirograph
4. gen-topology-flow
5. gen-string-theory
6. gen-supernova-remnant
7. gen-quasicrystal
8. gen-mycelium-network
9. gen-magnetic-field-lines
10. gen-bifurcation-diagram
11. gen-temporal-motion-smear (motion trails)
12. gen-velocity-bloom (velocity-sensitive bloom)
13. gen-feedback-echo-chamber (multi-layer echo)

---

## Success Metrics

- [ ] 61 shaders upgraded with RGBA support
- [ ] 10 hybrid shaders created
- [ ] 13 generative/temporal shaders created
- [ ] 100% randomization-safe parameters
- [ ] 0 compilation errors
- [ ] All shaders pass QA review
- [ ] Phase A QA report complete

---

## Phase B Gate Criteria

Phase B can begin when:
1. All 5 agents complete their tasks
2. QA report shows 0 critical issues
3. Integration summary approved
4. All output files in correct locations

---

## Questions?

See the main specification: `swarm-spec-shader-upgrade-phases.yaml`

See technical reference: `swarm-technical-reference.md`
