# Agent 2B: Advanced Alpha Compositor
## Task Specification - Phase B, Agent 2

**Role:** Complex RGBA Logic Specialist  
**Priority:** HIGH  
**Target:** 50 complex shaders with advanced alpha  
**Estimated Duration:** 4-5 days

---

## Mission

Implement advanced alpha channel techniques for complex shaders. Go beyond simple luminance-based alpha to create sophisticated transparency systems: depth-layered, edge-preserve, accumulative, and physical transmittance.

---

## Alpha Mode Catalog

### Mode 1: Depth-Layered Alpha
**Use for:** Atmospheric effects, depth-of-field hybrids

**Concept:** Alpha varies based on depth buffer - farther objects more transparent

```wgsl
// Implementation
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>) -> f32 {
    // Sample depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Luminance for content-based alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    
    // Depth factor: foreground (depth=1) = more opaque
    let depthAlpha = mix(0.4, 1.0, depth);
    
    // Luminance factor: brighter = more opaque
    let lumaAlpha = mix(0.5, 1.0, luma);
    
    // Combine with parameter control
    let depthWeight = u.zoom_params.z; // Control depth influence
    let alpha = mix(lumaAlpha, depthAlpha, depthWeight);
    
    return alpha;
}

// Usage
let color = processEffect(uv);
let alpha = depthLayeredAlpha(color, uv);
textureStore(writeTexture, coord, vec4<f32>(color, alpha));
```

**Visual Effect:** Creates atmospheric perspective - distant parts of the effect fade into the background.

---

### Mode 2: Edge-Preserve Alpha
**Use for:** Outline effects, sketch filters, edge-detection shaders

**Concept:** Edges are fully opaque, smooth areas become transparent

```wgsl
// Implementation
fn edgePreserveAlpha(color: vec3<f32>, uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
    // Sample neighboring pixels for depth edge detection
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    
    // Depth edge magnitude
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    
    // Color edge (optional, for color-based edge detection)
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let cL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let colorEdge = length(cR - cL);
    
    // Combine edges
    let totalEdge = depthEdge * 2.0 + colorEdge;
    
    // Edge = opaque, smooth = transparent
    let edgeMask = smoothstep(0.02, 0.1, totalEdge);
    let alpha = mix(0.3, 1.0, edgeMask);
    
    return alpha;
}
```

**Visual Effect:** Only edges of objects show the effect, interiors remain mostly transparent.

---

### Mode 3: Accumulative Alpha (Feedback Systems)
**Use for:** Temporal echo, reaction-diffusion, feedback loops

**Concept:** Alpha accumulates over time like paint on canvas

```wgsl
// Implementation for feedback shaders
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    uv: vec2<f32>,
    accumulationRate: f32
) -> vec4<f32> {
    // Read previous frame
    let prev = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Accumulate alpha
    // Old alpha fades slightly, new alpha adds on top
    let accumulatedAlpha = prev.a * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    
    // Color blends based on alpha contribution
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let color = mix(prev.rgb, newColor, newAlpha * accumulationRate / totalAlpha);
    
    return vec4<f32>(color, totalAlpha);
}

// Usage in feedback shader
let newEffect = computeEffect(uv);
let newAlpha = computeEffectAlpha(uv);
let accumulated = accumulativeAlpha(newEffect, newAlpha, uv, 0.3);

textureStore(writeTexture, coord, accumulated);
```

**Visual Effect:** Effect builds up over time like layers of transparent paint.

---

### Mode 4: Physical Transmittance (Beer's Law)
**Use for:** Volumetric effects, glass, liquid simulations

**Concept:** Simulates light absorption through colored medium

```wgsl
// Implementation
fn physicalTransmittance(
    baseColor: vec3<f32>,
    opticalDepth: f32,
    absorptionCoeff: vec3<f32>
) -> vec3<f32> {
    // Beer's Law: I = I0 * exp(-σ * d)
    // σ = absorption coefficient per color channel
    // d = optical depth (distance through medium)
    
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    // Alpha from optical thickness
    // 1 - exp(-density * thickness)
    return 1.0 - exp(-density * thickness);
}

// Usage for volumetric effect
let density = sampleDensity(uv);
let thickness = sampleThickness(uv);
let opticalDepth = density * thickness;

// Get base color from behind
let background = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

// Apply absorption
let absorption = vec3<f32>(0.5, 0.8, 1.0); // Blue-tinted medium
let transmitted = physicalTransmittance(background, opticalDepth, absorption);

// Calculate alpha
let alpha = volumetricAlpha(density, thickness);

// Final color
let finalColor = mix(background, transmitted, alpha);
textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
```

**Visual Effect:** Realistic light absorption through colored volumes like fog, smoke, or stained glass.

---

### Mode 5: Effect Intensity Alpha
**Use for:** Distortion shaders, displacement effects

**Concept:** Alpha based on how much distortion/effect is applied

```wgsl
// Implementation
fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32
) -> f32 {
    // Calculate displacement magnitude
    let displacement = length(displacedUV - originalUV);
    
    // More displacement = more opaque
    let displacementAlpha = smoothstep(0.0, 0.1, displacement);
    
    // Edge fade (effect fades at screen edges)
    let edgeDist = min(
        min(originalUV.x, 1.0 - originalUV.x),
        min(originalUV.y, 1.0 - originalUV.y)
    );
    let edgeFade = smoothstep(0.0, 0.05, edgeDist);
    
    // Combine
    let alpha = baseAlpha * displacementAlpha * edgeFade;
    
    return max(alpha, 0.1); // Minimum visibility
}

// Usage in distortion shader
let displacedUV = uv + calculateDisplacement(uv);
let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
let alpha = effectIntensityAlpha(uv, displacedUV, 0.8);

textureStore(writeTexture, coord, vec4<f32>(color, alpha));
```

---

### Mode 6: Selective Alpha (Luminance Key)
**Use for:** Screen blend modes, glow effects, light leaks

**Concept:** Dark pixels become transparent (like screen blend in Photoshop)

```wgsl
// Implementation
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    
    // Key out dark pixels
    let alpha = smoothstep(threshold - softness, threshold + softness, luma);
    
    return alpha;
}

// Usage for glow effect
let glowColor = calculateGlow(uv);
let alpha = luminanceKeyAlpha(glowColor, 0.1, 0.05);

textureStore(writeTexture, coord, vec4<f32>(glowColor, alpha));
```

**Visual Effect:** Effect only appears where there's brightness - perfect for glows, light leaks, lens flares.

---

## Target Shaders for Advanced Alpha

### Distortion Category (Apply Effect Intensity Alpha)
- [ ] tensor-flow-sculpting
- [ ] hyperbolic-dreamweaver
- [ ] julia-warp
- [ ] parallax-shift
- [ ] liquid-warp
- [ ] vortex-distortion
- [ ] bubble-lens
- [ ] slinky-distort

### Volumetric/Atmospheric (Apply Physical Transmittance)
- [ ] volumetric-cloud-nebula
- [ ] aurora-rift
- [ ] aurora-rift-2
- [ ] fog/atmospheric shaders

### Feedback/Temporal (Apply Accumulative Alpha)
- [ ] temporal-echo
- [ ] infinite-fractal-feedback
- [ ] reaction-diffusion
- [ ] lenia
- [ ] video-echo-chamber

### Edge-Detection/Outline (Apply Edge-Preserve Alpha)
- [ ] neon-edge-diffusion
- [ ] neon-edge-reveal
- [ ] edge-glow-mouse
- [ ] neon-edges
- [ ] sketch-reveal

### Glow/Light Effects (Apply Luminance Key Alpha)
- [ ] anamorphic-flare
- [ ] lens-flare-brush
- [ ] neon-pulse
- [ ] divine-light
- [ ] light-leaks

### Complex Multi-Effect (Apply Depth-Layered Alpha)
- [ ] chromatographic-separation
- [ ] kimi_liquid_glass
- [ ] gen-xeno-botanical-synth-flora
- [ ] crystal-refraction
- [ ] holographic-* shaders

---

## Implementation Template

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {SHADER_NAME} - Advanced Alpha
//  Alpha Mode: {MODE_NAME}
//  Features: advanced-alpha, depth-aware, {other features}
// ═══════════════════════════════════════════════════════════════════

// ... standard header ...

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(
    color: vec3<f32>,
    uv: vec2<f32>,
    params: vec4<f32>
) -> f32 {
    // params.x: intensity
    // params.y: threshold
    // params.z: depth weight
    // params.w: effect-specific
    
    // Implementation based on selected mode
    // ...
    
    return alpha;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let pixelSize = 1.0 / res;
    
    // ... effect calculation ...
    let processedColor = processEffect(uv);
    
    // Advanced alpha calculation
    let alpha = calculateAdvancedAlpha(processedColor, uv, u.zoom_params);
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Store with calculated alpha
    textureStore(writeTexture, gid.xy, vec4<f32>(processedColor, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

---

## Parameter Mapping

All advanced alpha shaders should use:

| Param | Usage | Range |
|-------|-------|-------|
| x | Effect intensity | 0.0-1.0 |
| y | Alpha threshold | 0.0-1.0 |
| z | Depth influence | 0.0-1.0 |
| w | Mode-specific | 0.0-1.0 |

---

## Deliverables

1. **50 upgraded shader files** with advanced alpha modes
2. **Alpha mode documentation** with visual examples
3. **Parameter tuning guide** for each mode

---

## Success Criteria

- All 50 shaders have sophisticated alpha handling
- Visual quality improved with depth/layering
- No hardcoded alpha = 1.0 (except where appropriate)
- All modes documented with usage examples
- Parameters allow tuning of alpha behavior
