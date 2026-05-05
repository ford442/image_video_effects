# Agent 1C: RGBA Convolution Architect
## Task Specification — Phase C, Agent 1

**Role:** Advanced Image Convolution & RGBA32FLOAT Exploitation Specialist  
**Priority:** HIGH  
**Target:** 15 novel convolution shaders that exploit rgba32float precision  
**Estimated Duration:** 5-7 days

---

## Mission

Create convolution-based image processing shaders that **do not yet exist** in the Pixelocity library. The current library has Sobel, Gaussian, Laplacian, Biharmonic, and Anisotropic Kuwahara. This agent introduces entirely new convolution families, all designed to exploit the full dynamic range of `rgba32float` (128 bits per pixel) for effects impossible in 8-bit pipelines.

**Key Principle:** Every convolution below must use the alpha channel as a meaningful data carrier — not as simple opacity, but as a **computation surface** storing intermediate values, quality metrics, or secondary fields that enhance the visual output.

---

## Convolutions NOT Yet in the Library

### Tier 1: Essential Missing Convolutions (Priority)

#### 1. `conv-bilateral-dream.wgsl` — Bilateral Filter with Psychedelic Color Preservation
**What it does:** Edge-preserving smoothing that blurs similar colors while keeping edges razor-sharp. Unlike Gaussian blur which destroys edges, bilateral filtering creates a "painterly" look.

**RGBA32FLOAT exploitation:**
- RGB channels: Accumulated weighted color (HDR, unclamped — values can exceed 1.0 during accumulation)
- Alpha channel: **Accumulated weight normalization factor** — storing the running sum of Gaussian weights allows deferred normalization, which is numerically more stable than normalizing per-sample in low-precision formats

**Algorithm:**
```wgsl
fn bilateral(uv: vec2<f32>, pixelSize: vec2<f32>, sigmaSpace: f32, sigmaColor: f32) -> vec4<f32> {
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let radius = i32(ceil(sigmaSpace * 2.0));
    
    for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            
            // Spatial Gaussian
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * sigmaSpace * sigmaSpace));
            
            // Range (color similarity) Gaussian
            let colorDist = length(neighbor.rgb - center.rgb);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * sigmaColor * sigmaColor));
            
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
        }
    }
    
    // Store raw accumulation — alpha = weight sum for deferred normalization
    return vec4<f32>(accumColor, accumWeight);
}
```

**Mouse interactivity:** `u.zoom_config.yz` controls the center of a varying-radius bilateral region. Near mouse = sharp (small sigma), far from mouse = dreamy smooth (large sigma). Ripples trigger "shockwaves" of sharpness radiating outward.

**Params:**
| Param | Name | Default | Range | Purpose |
|-------|------|---------|-------|---------|
| x | Spatial Sigma | 0.5 | 0.1-1.0 | Blur radius |
| y | Color Sigma | 0.3 | 0.05-1.0 | Edge preservation threshold |
| z | Psychedelic Hue Shift | 0.0 | 0.0-1.0 | Post-filter color rotation |
| w | Mouse Influence | 0.5 | 0.0-1.0 | Mouse distance effect |

---

#### 2. `conv-morphological-erosion-dilation.wgsl` — Morphological Operators (Erosion/Dilation/Open/Close)
**What it does:** Mathematical morphology on images — erosion shrinks bright regions, dilation expands them. Opening (erode then dilate) removes small bright features; closing (dilate then erode) fills small dark holes. Creates organic, biological-looking transformations.

**RGBA32FLOAT exploitation:**
- R channel: Erosion result (min filter)
- G channel: Dilation result (max filter)
- B channel: Morphological gradient (dilation − erosion = edge thickness)
- Alpha channel: **Top-hat transform** (original − opening = isolated bright peaks)

**Why RGBA32FLOAT matters:** Morphological gradient magnitudes can be extremely small (0.001) or large (2.0+) in HDR content. 8-bit would quantize the gradient to ~4 levels, destroying the delicate edge structure.

```wgsl
fn morphological(uv: vec2<f32>, pixelSize: vec2<f32>, kernelRadius: i32) -> vec4<f32> {
    var minVal = vec3<f32>(999.0);
    var maxVal = vec3<f32>(-999.0);
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    for (var dy = -kernelRadius; dy <= kernelRadius; dy++) {
        for (var dx = -kernelRadius; dx <= kernelRadius; dx++) {
            // Use circular structuring element
            if (dx*dx + dy*dy > kernelRadius*kernelRadius) { continue; }
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let sample = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            minVal = min(minVal, sample);
            maxVal = max(maxVal, sample);
        }
    }
    
    let erosion = minVal;
    let dilation = maxVal;
    let gradient = dilation - erosion;         // Edge thickness
    let topHat = center - erosion;             // Isolated bright peaks
    
    // Pack all four into RGBA
    let luminanceGrad = dot(gradient, vec3<f32>(0.299, 0.587, 0.114));
    let luminanceTopHat = dot(topHat, vec3<f32>(0.299, 0.587, 0.114));
    
    return vec4<f32>(
        mix(erosion, dilation, u.zoom_params.x),   // Blend erosion↔dilation via param
        luminanceTopHat                              // Alpha = top-hat for stacking
    );
}
```

**Mouse interactivity:** Mouse position controls the structuring element shape — near mouse it becomes elongated (directional morphology), creating flow-like patterns. Ripples trigger momentary dilation "explosions."

---

#### 3. `conv-gabor-texture-analyzer.wgsl` — Gabor Filter Bank for Texture Segmentation
**What it does:** Gabor filters detect oriented texture patterns at specific frequencies. A bank of Gabor filters at multiple orientations creates a powerful texture analysis tool — it can segment an image by texture type and colorize each differently.

**RGBA32FLOAT exploitation:**
- R channel: Response to horizontal Gabor (0°)
- G channel: Response to diagonal Gabor (45°)  
- B channel: Response to vertical Gabor (90°)
- Alpha channel: Response to counter-diagonal Gabor (135°)

All four channels store signed floating-point filter responses — **critical** because Gabor responses are naturally bipolar (positive and negative). An 8-bit format would need bias+scale and would lose half the precision.

```wgsl
fn gabor(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
    var response = 0.0;
    let radius = i32(ceil(sigma * 3.0));
    let cosTheta = cos(theta);
    let sinTheta = sin(theta);
    
    for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
            let x = f32(dx);
            let y = f32(dy);
            let xTheta = x * cosTheta + y * sinTheta;
            let yTheta = -x * sinTheta + y * cosTheta;
            
            let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma));
            let sinusoidal = cos(2.0 * 3.14159 * freq * xTheta);
            let kernel = gaussian * sinusoidal;
            
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            response += luma * kernel;
        }
    }
    return response;
}
```

**Visual output:** The 4-channel Gabor response is mapped to a psychedelic color palette — textures glow in different colors based on their orientation. Diagonal wood grain might glow magenta while horizontal brick patterns glow cyan.

**Mouse interactivity:** Mouse angle (atan2 from center) rotates the entire Gabor bank, causing the texture color mapping to swirl and shift. Ripples inject frequency modulation bursts.

---

#### 4. `conv-non-local-means.wgsl` — Non-Local Means Denoising with Artistic Overdrive
**What it does:** Instead of averaging nearby pixels (spatial locality), NLM averages pixels with **similar patches** anywhere in a search window. This is the gold-standard denoising algorithm — but cranked up to create artistic effects.

**RGBA32FLOAT exploitation:** Alpha stores the **self-similarity map** — how many similar patches were found for each pixel. Low similarity = isolated/unique texture = high alpha (keep sharp). High similarity = repetitive texture = low alpha (blurred region). This creates a natural importance map.

**Algorithm core:**
```wgsl
fn patchDistance(uv1: vec2<f32>, uv2: vec2<f32>, patchRadius: i32, pixelSize: vec2<f32>) -> f32 {
    var dist = 0.0;
    for (var dy = -patchRadius; dy <= patchRadius; dy++) {
        for (var dx = -patchRadius; dx <= patchRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let p1 = textureSampleLevel(readTexture, u_sampler, uv1 + offset, 0.0).rgb;
            let p2 = textureSampleLevel(readTexture, u_sampler, uv2 + offset, 0.0).rgb;
            dist += dot(p1 - p2, p1 - p2);
        }
    }
    return dist;
}
```

When overdrive parameter is pushed high, NLM finds "echoes" of the same texture across the image and blends them together — creating dreamy, hallucinatory double-exposure effects where similar textures merge.

---

#### 5. `conv-guided-filter-depth.wgsl` — Guided Filter using Depth as Guide
**What it does:** The guided filter uses a "guide image" to steer filtering. Using the **depth texture** as guide creates depth-of-field blur that perfectly respects object boundaries — no edge bleeding.

**RGBA32FLOAT exploitation:**
- RGB: Filtered image (HDR, unclamped during accumulation)
- Alpha: **Filtering confidence** — `a` coefficient from the guided filter linear model. High |a| means strong edge guidance, low |a| means smooth region. This encodes how "reliable" the filtered result is.

```wgsl
// Guided filter: output = a * guide + b at each pixel
// a = cov(guide, input) / (var(guide) + epsilon)
// b = mean(input) - a * mean(guide)
fn guidedFilter(uv: vec2<f32>, radius: i32, epsilon: f32, pixelSize: vec2<f32>) -> vec4<f32> {
    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;
    
    for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r;
            let inputVal = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            sumGuide += guideVal;
            sumInput += inputVal;
            sumGuideInput += inputVal * guideVal;
            sumGuide2 += guideVal * guideVal;
            count += 1.0;
        }
    }
    
    let meanGuide = sumGuide / count;
    let meanInput = sumInput / count;
    let meanGI = sumGuideInput / count;
    let varGuide = sumGuide2 / count - meanGuide * meanGuide;
    
    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;
    
    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let result = a * guide + b;
    let confidence = length(a); // How much the guide influences the result
    
    return vec4<f32>(result, confidence);
}
```

---

### Tier 2: Exotic & Psychedelic Convolutions

#### 6. `conv-structure-tensor-flow.wgsl` — Structure Tensor Visualization with LIC
**What it does:** Computes the structure tensor (2×2 covariance of gradients), extracts eigenvectors, and uses Line Integral Convolution (LIC) to visualize the dominant texture flow as animated streamlines.

**RGBA32FLOAT exploitation:**
- RG: Dominant eigenvector direction (full f32 precision for smooth flow)
- B: Coherency (eigenvalue ratio — how strongly oriented the texture is)
- A: LIC texture (accumulated along the streamline)

---

#### 7. `conv-difference-of-gaussians-cascade.wgsl` — Multi-Scale DoG Cascade
**What it does:** Cascaded Difference-of-Gaussians at 8+ scales, combined with signed response storage. Creates a "neural edge" effect where edges at different scales glow in different colors.

**RGBA32FLOAT exploitation:** Each channel stores a different DoG scale response (all signed). Final compositing maps the 4-scale response vector to a color via a 4D→3D color matrix.

---

#### 8. `conv-anisotropic-diffusion.wgsl` — Perona-Malik Anisotropic Diffusion
**What it does:** Iterative smoothing that diffuses along edges but not across them. Creates an oil-painting effect that progressively simplifies the image into flat colored regions while preserving boundaries.

**RGBA32FLOAT exploitation:** Alpha stores the **diffusion coefficient** per pixel (how much smoothing was applied). This creates a "process map" useful for stacking effects — downstream shaders can read alpha to know which regions were simplified.

---

#### 9. `conv-steerable-pyramid.wgsl` — Steerable Pyramid Decomposition
**What it does:** Decomposes an image into oriented sub-bands (like a more powerful wavelet transform). Each sub-band captures edges at a specific orientation and scale.

**RGBA32FLOAT exploitation:** Store 4 oriented sub-band responses (0°, 45°, 90°, 135°) in RGBA. The full-precision f32 sub-band coefficients allow lossless reconstruction or artistic manipulation (boost specific orientations for "painterly" effects).

---

#### 10. `conv-bilateral-grid-splat.wgsl` — Bilateral Grid (Fast Approximate Bilateral)
**What it does:** Instead of the brute-force bilateral filter, constructs a 3D bilateral grid (x, y, intensity) and splatters pixels into it. Achieves the same edge-preserving smooth but at O(1) per pixel regardless of kernel size.

**RGBA32FLOAT exploitation:**
- RGB: Accumulated splatted color (can exceed 1.0 in grid cells with many contributions)
- A: Accumulated weight for normalization

**Why it matters:** The bilateral grid requires floating-point accumulation in 3D bins. With rgba32float, each bin stores exact contributions without quantization — enabling arbitrarily large kernel radii without performance penalty.

---

### Tier 3: Wild / Artistic Convolutions

#### 11. `conv-fractal-kernel.wgsl` — Fractal-Shaped Convolution Kernels
**What it does:** Instead of square or circular kernels, uses Mandelbrot/Julia set membership as the kernel shape. Pixels "inside" the fractal set are sampled, others are not. Creates alien, mathematically beautiful blur patterns.

---

#### 12. `conv-spiral-blur.wgsl` — Logarithmic Spiral Convolution
**What it does:** Samples along a logarithmic spiral centered on each pixel. Creates a rotational motion blur that follows a golden ratio spiral. Mouse position controls the spiral center and tightness.

---

#### 13. `conv-reaction-convolution.wgsl` — Gray-Scott Reaction-Diffusion as Convolution
**What it does:** Runs 1 step of reaction-diffusion per frame where the diffusion kernel shape is mouse-controllable. Not a standalone simulation — applies R-D as a **filter** on the input image, using image luminance to seed the A/B chemical concentrations.

**RGBA32FLOAT exploitation:**
- R: Chemical A concentration (needs f32 precision for stable PDE integration)
- G: Chemical B concentration
- B: Filtered image mixed with R-D pattern
- A: Reaction rate (feed/kill parameter spatially varying from mouse distance)

---

#### 14. `conv-frequency-domain-notch.wgsl` — Spatial-Domain Approximation of Frequency Notch Filter
**What it does:** Approximates removing specific spatial frequencies using a bank of tuned sinusoidal convolution kernels. Removes moiré patterns, aliasing artifacts, or creates "frequency painting" by selectively boosting/cutting frequency bands.

---

#### 15. `conv-stochastic-stipple.wgsl` — Stochastic Halftone via Weighted Voronoi Stippling Convolution
**What it does:** Uses blue-noise dithering + local averaging to create stipple/pointillist art from any image. Each "dot" represents a local neighborhood, sized by average luminance.

**RGBA32FLOAT exploitation:**
- RGB: Stipple color (sampled from local mean)
- A: **Stipple density** — continuous float representing how "full" each stipple cell is. Downstream shaders can use this to create varying dot sizes in vector-graphic style.

---

## Implementation Template

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {SHADER_NAME}
//  Category: image (or interactive-mouse if mouse-responsive)
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: {bilateral|morphological|gabor|NLM|guided|...}
//  Complexity: High
//  Created: 2026-04-XX
//  By: Agent 1C — RGBA Convolution Architect
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CONVOLUTION KERNEL ═══
// [kernel-specific functions here]

// ═══ RGBA32FLOAT DATA PACKING ═══
// RGB = [describe what RGB stores]
// Alpha = [describe what alpha stores — must be meaningful, not 1.0]

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // [Convolution computation]
    
    // Store with meaningful alpha
    textureStore(writeTexture, global_id.xy, vec4<f32>(result_rgb, result_alpha));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

---

## Performance Considerations

| Convolution | Kernel Size | Samples/pixel | Target FPS |
|-------------|-------------|---------------|------------|
| Bilateral | 7×7 | 49 | 45-60 |
| Bilateral | 11×11 | 121 | 30-45 |
| Morphological | 5×5 | ~20 (circular) | 60 |
| Gabor (4-band) | 9×9 × 4 | 324 | 30-45 |
| Non-Local Means | 7×7 patch, 21×21 search | ~200 | 20-30 |
| Guided Filter | 9×9 | 81 | 45-60 |
| Structure Tensor LIC | 3×3 + 32 LIC steps | ~40 | 45-60 |

**Optimization strategies:**
- Use `textureLoad` instead of `textureSampleLevel` for integer coordinates
- Use shared memory tiles for convolutions with radius ≤ 4
- Use separable decomposition where possible (Gaussian component of bilateral)
- Use early-exit for pixels far from mouse when mouse influence is active
- LOD: Reduce kernel size for pixels far from screen center

---

## Deliverables

1. **15 WGSL shader files** in `public/shaders/conv-*.wgsl`
2. **15 JSON definition files** in `shader_definitions/image/` or `shader_definitions/interactive-mouse/`
3. **Each shader must:**
   - Use a convolution technique NOT already in the library
   - Store meaningful data in the alpha channel
   - Respond to at least 2 of the 4 zoom_params
   - Include mouse responsiveness via zoom_config and/or ripples
   - Include header comments explaining the RGBA32FLOAT exploitation

---

## Success Criteria

- [ ] All 15 shaders compile without WGSL errors
- [ ] No duplicate convolution type with existing library
- [ ] Alpha channel stores meaningful data in all shaders (document what)
- [ ] Mouse responsiveness verified (zoom_config and/or ripples)
- [ ] Performance targets met (30+ FPS at 2048×2048)
- [ ] Visual output is psychedelic / artistically compelling
- [ ] JSON definitions include params, tags, description
