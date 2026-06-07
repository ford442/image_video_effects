# Agent 1A: Alpha Channel Specialist
## Task Specification - Phase A, Agent 1

**Role:** RGB → RGBA Upgrade Engineer  
**Priority:** CRITICAL - FIRST WAVE  
**Target:** 61 shaders (9 Tiny + 52 Small)  
**Estimated Duration:** 3-4 days

---

## Mission

Upgrade all Tiny and Small shaders to properly handle RGBA channels instead of just RGB. Ensure alpha values are calculated dynamically rather than hardcoded to 1.0.

---

## Target Shader Files

### Tier 1: Tiny Shaders (< 2KB) - START HERE
| # | Shader | Size | File Path |
|---|--------|------|-----------|
| 1 | texture | 719 B | `public/shaders/texture.wgsl` |
| 2 | gen_orb | 1,402 B | `public/shaders/gen_orb.wgsl` |
| 3 | gen_grokcf_interference | 1,535 B | `public/shaders/gen_grokcf_interference.wgsl` |
| 4 | gen_grid | 1,594 B | `public/shaders/gen_grid.wgsl` |
| 5 | gen_grokcf_voronoi | 1,630 B | `public/shaders/gen_grokcf_voronoi.wgsl` |
| 6 | gen_grok41_plasma | 1,648 B | `public/shaders/gen_grok41_plasma.wgsl` |
| 7 | galaxy | 1,682 B | `public/shaders/galaxy.wgsl` |
| 8 | gen_trails | 1,878 B | `public/shaders/gen_trails.wgsl` |
| 9 | gen_grok41_mandelbrot | 1,883 B | `public/shaders/gen_grok41_mandelbrot.wgsl` |

### Tier 2: Small Shaders (2-3KB) - SECOND WAVE
Key targets:
- imageVideo, gen_julia_set, quantized-ripples, scanline-wave
- luma-flow-field, phantom-lag, frosty-window, parallax-shift
- ion-stream, liquid-jelly, anamorphic-flare, kaleidoscope
- (See `shaders_upgrade_plan.md` for complete list)

---

## Alpha Upgrade Patterns

### Pattern 1: Simple Luminance Alpha
Use for: Most image-processing shaders

```wgsl
// AFTER processing, calculate alpha from luminance
let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
let alpha = mix(0.7, 1.0, luma);

// Depth awareness (if depth texture available)
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
alpha = mix(alpha * 0.8, alpha, depth);

textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
```

### Pattern 2: Effect Intensity Alpha
Use for: Distortion/warp shaders

```wgsl
// Alpha based on how much effect is applied
let effectStrength = length(displacement);
let alpha = mix(0.5, 1.0, smoothstep(0.0, 0.1, effectStrength));

// Add edge fade for smooth blending
let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
alpha = alpha * smoothstep(0.0, 0.05, edgeDist);
```

### Pattern 3: Generative/Procedural Alpha
Use for: Generative shaders (gen_*)

```wgsl
// For generative shaders, alpha can be based on "presence" of content
let presence = smoothstep(0.1, 0.3, length(color));
let alpha = mix(0.0, 1.0, presence);

// Or always full alpha for generative content
let alpha = 1.0;
```

### Pattern 4: Depth-Layered Alpha
Use for: Depth-aware shaders

```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

// Foreground = more opaque
let depthAlpha = mix(0.6, 1.0, depth);

// Combine with luminance
let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
let lumaAlpha = mix(0.7, 1.0, luma);

let alpha = (depthAlpha + lumaAlpha) * 0.5;
```

---

## Required Header Template

Every upgraded shader MUST use this exact header:

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {SHADER_NAME}
//  Category: {CATEGORY}
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
```

---

## Checklist Per Shader

For each shader you upgrade:

- [ ] Read original shader completely
- [ ] Identify current alpha handling (probably hardcoded to 1.0)
- [ ] Choose appropriate alpha pattern from above
- [ ] Add ALL 13 bindings in correct order
- [ ] Add Uniforms struct if missing
- [ ] Implement alpha calculation
- [ ] Add `textureStore(writeDepthTexture, ...)` call
- [ ] Update header comment with upgrade info
- [ ] Verify shader still compiles (syntax check)
- [ ] Update JSON definition (add "depth-aware" feature if applicable)

---

## Output Format

For each shader, provide:

1. **Upgraded WGSL file** at `public/shaders/{name}.wgsl`
2. **Brief change summary** in your response:
   ```
   Shader: {name}
   Alpha Pattern Used: {pattern}
   Key Changes:
   - Added depth texture sampling
   - Implemented luminance-based alpha
   - Added depth write pass
   ```

---

## Common Issues to Watch For

1. **Missing non_filtering_sampler** - Add as binding(5)
2. **vec3 output** - Must change to vec4 with calculated alpha
3. **No depth write** - ALWAYS add writeDepthTexture store
4. **Wrong workgroup size** - Must be `@workgroup_size(8, 8, 1)`

---

## Priority Order

1. Start with `texture.wgsl` (smallest, core shader)
2. Then `gen_orb`, `gen_grid` (generative, easier to test)
3. Then other tiny shaders
4. Finally small shaders

---

## Success Criteria

- All 61 shaders upgraded with proper RGBA handling
- No hardcoded `alpha = 1.0` (unless generative and intentional)
- All shaders write to both writeTexture AND writeDepthTexture
- Consistent header format across all files
