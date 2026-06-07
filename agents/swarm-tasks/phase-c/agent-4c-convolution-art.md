# Agent 4C: Convolution-Art Alchemist
## Task Specification - Phase C, Agent 4

**Role:** Advanced Image-Convolution Specialist
**Priority:** MEDIUM-HIGH (library currently has almost no real convolutions)
**Target:** Create 3 mouse-responsive compute shaders built on advanced multi-pass convolutions
**Estimated Duration:** 4-5 days

---

## Mission

The library's convolution coverage is embarrassingly thin: one 3×3 Gaussian, one Sobel edge detector, and an implicit Laplacian inside the reaction-diffusion shaders. Phase C introduces the **separable cross-bilateral filter**, **Perona-Malik anisotropic diffusion**, and a **workgroup-shared mean-shift painter**. All three are mouse-localized (the effect only applies inside a soft cursor kernel) and turn real images into living painterly works.

These shaders also demonstrate three patterns otherwise absent from the codebase: **separable multi-pass convolution**, **edge-stopping diffusion**, and **workgroup shared-memory histograms with atomic updates**.

---

## Shader Concepts

### 1. `bilateral-glow-forest` (3-pass: horizontal, vertical, composite)

**Concept:** A separable **cross-bilateral filter** localized to the mouse cursor. The mouse paints a soft disk; inside it, each pixel is replaced with a distance-weighted *and* color-weighted average of its neighbors, producing an edge-preserving smoothing that glows. Dragging becomes "brushing the noise out of a photograph into a luminous forest floor".

**Complexity:** Medium-High
**Primary Techniques:**
- **Separable bilateral** in two 1D passes (converted from a full 2D kernel for ~10× speedup)
- Per-pixel σ_space and σ_range read from `u.zoom_params`
- Cursor kernel mask so the rest of the image remains unchanged

**RGBA32FLOAT packing:**
```
dataTextureA.rgb = horizontally-blurred pixel (intermediate)
dataTextureA.a   = per-pixel mask (0 outside brush, 1 at center)
```

**Binding usage:**
- `readTexture` (1): source image
- `writeTexture` (2): final composite
- `dataTextureA` (7): horizontal-pass result + brush mask
- `dataTextureC` (9): previous frame's output — allows dragging to **accumulate** glow across frames

```wgsl
// Pass 1: horizontal bilateral
const K: i32 = 13;  // kernel radius
let center = textureLoad(readTexture, pix, 0).rgb;
let sigma_space = u.zoom_params.x * 12.0 + 1.0;
let sigma_range = u.zoom_params.y * 0.3  + 0.01;
var num = vec3<f32>(0.0);
var den = 0.0;
for (var dx = -K; dx <= K; dx++) {
    let s = textureLoad(readTexture, pix + vec2<i32>(dx, 0), 0).rgb;
    let w_s = exp(-f32(dx*dx) / (2.0 * sigma_space * sigma_space));
    let dc  = s - center;
    let w_r = exp(-dot(dc, dc) / (2.0 * sigma_range * sigma_range));
    let w   = w_s * w_r;
    num += s * w;
    den += w;
}
let mx = distance(vec2<f32>(pix), u.zoom_config.yz * u.config.zw);
let mask = smoothstep(u.zoom_params.z * 400.0, 0.0, mx) * u.zoom_config.w;
textureStore(dataTextureA, pix, vec4<f32>(num / den, mask));
```

```wgsl
// Pass 3: composite with a luminous boost
let smoothed = textureLoad(dataTextureA, pix, 0);
let src = textureLoad(readTexture, pix, 0).rgb;
// Glow = residual high-frequency energy added back as HDR
let residual = abs(src - smoothed.rgb);
let glow = pow(1.0 - residual, vec3<f32>(3.0)) * u.zoom_params.w * 2.5;
let out = mix(src, smoothed.rgb + glow, smoothed.a);
textureStore(writeTexture, pix, vec4<f32>(out, 1.0));
```

**Visual:** Like rubbing a photograph with a soft cloth — grain and noise vanish where the mouse passes, leaving only the large tonal masses glowing softly. Edges remain crisp thanks to the range filter; the result looks like "hand-tinted film".

**Params:**
- x: σ_space (spatial blur radius)
- y: σ_range (how sensitive to edges; smaller = more edge-preserving)
- z: Brush radius
- w: Glow intensity (HDR)

**RGB-from-RGBA strategy:** Source alpha directly multiplies the glow amount — transparent regions get no glow. Output RGB only.

---

### 2. `anisotropic-perona-malik` (iterative: 5 diffusion steps per frame)

**Concept:** Perona-Malik anisotropic diffusion. The image "flows" like heat, but the conductance is suppressed across edges, so heat (color energy) pools within regions and never crosses boundaries. The mouse locally increases diffusion time → passes turn photographs into oil-paintings with crisp borders. Different from existing `anisotropic-kuwahara` (which uses oriented rectangles); this is the **continuous PDE** approach.

**Complexity:** Medium
**Primary Techniques:**
- **Perona-Malik conductance**: `g(|∇I|) = exp(-(|∇I|/K)²)`
- Explicit Euler integration over multiple iterations
- Structure tensor (optional upgrade) for directional conductance

**RGBA32FLOAT packing:**
```
dataTextureA.rgb = current diffused image (HDR, can grow >1 in bright areas)
dataTextureA.a   = accumulated diffusion time at this pixel
```

**Binding usage:**
- `readTexture` (1): source image (first-frame seed)
- `writeTexture` (2): final render (with mouse-controlled mix to original)
- `dataTextureA` (7): persistent diffused state (read)
- `dataTextureB` (8): persistent diffused state (write — ping-pong)
- `dataTextureC` (9): previous-frame state for temporal cohesion

```wgsl
// Per-iteration diffusion step
fn conductance(grad2: f32, K: f32) -> f32 {
    return exp(-grad2 / (K * K));
}

let c    = textureLoad(dataTextureA, pix, 0).rgb;
let cN   = textureLoad(dataTextureA, pix + vec2<i32>(0,-1), 0).rgb;
let cS   = textureLoad(dataTextureA, pix + vec2<i32>(0, 1), 0).rgb;
let cE   = textureLoad(dataTextureA, pix + vec2<i32>( 1,0), 0).rgb;
let cW   = textureLoad(dataTextureA, pix + vec2<i32>(-1,0), 0).rgb;

let gN = cN - c; let gS = cS - c; let gE = cE - c; let gW = cW - c;
let K  = u.zoom_params.y * 0.5 + 0.01;
let cN_g = conductance(dot(gN,gN), K);
let cS_g = conductance(dot(gS,gS), K);
let cE_g = conductance(dot(gE,gE), K);
let cW_g = conductance(dot(gW,gW), K);

// Local mouse boost: diffuse faster inside brush
let mx = distance(vec2<f32>(pix), u.zoom_config.yz * u.config.zw);
let boost = 1.0 + u.zoom_config.w * u.zoom_params.z * exp(-mx*mx / (u.zoom_params.x * 400.0 * u.zoom_params.x));
let dt = 0.15 * boost;

let new_c = c + dt * (cN_g*gN + cS_g*gS + cE_g*gE + cW_g*gW);

// Feedback: accumulate diffusion time for UI display
var prev = textureLoad(dataTextureA, pix, 0);
prev.a += dt;
textureStore(dataTextureB, pix, vec4<f32>(new_c, prev.a));
```

**Visual:** Photographs become impressionist canvases: sky regions smooth into tonal washes, edges of trees/people remain razor-sharp, and the mouse "erodes" detail inside its disk. Over several seconds the image becomes progressively more painterly in mouse-visited regions.

**Params:**
- x: Brush falloff σ (px)
- y: Edge-stop K (0 = strong edge preservation, 1 = flat Gaussian diffusion)
- z: Brush strength (how much local dt boost)
- w: Composite ratio against original input (0 = pure diffused, 1 = original with mask)

**RGB-from-RGBA strategy:** Source RGBA's alpha channel is fed into the diffusion as a *fifth channel* that tracks through the same PDE; the resulting blurred alpha forms a soft mask used to composite back to RGB output.

---

### 3. `mean-shift-painter` (2-pass: workgroup-histogram-build, shift)

**Concept:** Mean-shift segmentation using **workgroup shared memory** to build a local color histogram per 32×32 tile, then each pixel is "pulled" toward the densest histogram mode. Repeated application posterizes the image into painterly flat regions. The mouse selects which **color band** to collapse harder — painting a green region with the cursor collapses all greens into a single emerald flat.

**Complexity:** High
**Primary Techniques:**
- **workgroupBarrier + var<workgroup>** for shared histogram
- **atomicAdd** on 64-bin H+S histogram (packed 8 bins × 8 bins)
- Mean-shift iteration: `x_{k+1} = Σ(x · K(x-x_k)) / Σ(K(x-x_k))`

**RGBA32FLOAT packing:**
```
dataTextureA.rgba = histogram slab (see below)
writeTexture.rgb  = shifted color
writeTexture.a    = locked/active mask
```

**Shared-memory layout (NEW — introduces atomics to the library):**
```wgsl
var<workgroup> hist: array<atomic<u32>, 64>;   // 8 hue bins × 8 sat bins
```

**Binding usage:**
- `readTexture` (1): source image
- `writeTexture` (2): shifted output
- `dataTextureA` (7): histogram slab (only needed if cross-workgroup means are desired)

```wgsl
@compute @workgroup_size(32, 32, 1)
fn cs_main(@builtin(global_invocation_id) gid: vec3<u32>,
           @builtin(local_invocation_index) li: u32) {

    // Phase 1: zero histogram cooperatively
    if (li < 64u) { atomicStore(&hist[li], 0u); }
    workgroupBarrier();

    // Phase 2: every thread bins its pixel
    let rgb = textureLoad(readTexture, vec2<i32>(gid.xy), 0).rgb;
    let hsv = rgb_to_hsv(rgb);
    let bin = u32(hsv.x * 8.0) * 8u + u32(hsv.y * 8.0);
    atomicAdd(&hist[bin], 1u);
    workgroupBarrier();

    // Phase 3: find argmax locally (cooperative reduction)
    // (spelled out for clarity; a real implementation uses tree reduction)
    var max_count = 0u;  var max_bin = 0u;
    if (li == 0u) {
        for (var b = 0u; b < 64u; b++) {
            let c = atomicLoad(&hist[b]);
            if (c > max_count) { max_count = c; max_bin = b; }
        }
    }
    workgroupBarrier();
    let dominant_hue = f32(max_bin / 8u) / 8.0 + 0.0625;
    let dominant_sat = f32(max_bin % 8u) / 8.0 + 0.0625;

    // Phase 4: mean-shift toward the dominant mode, scaled by mouse distance
    let mx = distance(vec2<f32>(gid.xy), u.zoom_config.yz * u.config.zw);
    let weight = u.zoom_params.x * exp(-mx*mx / (u.zoom_params.y * 800.0));
    let hue_shifted = mix(hsv.x, dominant_hue, weight);
    let sat_shifted = mix(hsv.y, dominant_sat, weight);
    let out = hsv_to_rgb(vec3<f32>(hue_shifted, sat_shifted, hsv.z));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(out, 1.0));
}
```

**Visual:** Photos resolve into flat painterly tiles of color, each tile the dominant hue of its 32-pixel neighborhood. Dragging the mouse over an area "collapses" its colors harder, producing a Rothko-like abstract. Releasing snaps detail back.

**Params:**
- x: Shift intensity (0 = no collapse, 1 = hard posterize)
- y: Brush falloff
- z: Histogram bias (push toward warm / cool colors)
- w: Output saturation multiplier (for psychedelic punch)

**RGB-from-RGBA strategy:** Input alpha controls per-pixel voting weight in the histogram — transparent pixels don't contribute to the local mode, so the collapse only samples what's "really there". Output RGB-only.

---

## Deliverables

| File | Lines | Notes |
|------|-------|-------|
| `public/shaders/bilateral-glow-forest-hbilat.wgsl` | ~80 | Horizontal bilateral |
| `public/shaders/bilateral-glow-forest-vbilat.wgsl` | ~80 | Vertical bilateral |
| `public/shaders/bilateral-glow-forest-composite.wgsl` | ~50 | HDR glow composite |
| `shader_definitions/artistic/bilateral-glow-forest.json` | ~100 | |
| `public/shaders/anisotropic-perona-malik.wgsl` | ~130 | Single-pass diffusion step (iterated per frame via the scheduler) |
| `shader_definitions/artistic/anisotropic-perona-malik.json` | ~80 | |
| `public/shaders/mean-shift-painter.wgsl` | ~140 | Workgroup histogram, FIRST production shader using atomics |
| `shader_definitions/artistic/mean-shift-painter.json` | ~80 | |

---

## Validation Checklist

- [ ] Bilateral separable output matches (within 2%) a true 2D bilateral reference for σ≤4.
- [ ] Perona-Malik stable at `dt=0.25` for K down to 0.02.
- [ ] Mean-shift workgroup histogram: atomic contention doesn't degrade FPS below 30 at 1080p.
- [ ] All three shaders honor the 13-binding contract.
- [ ] `mean-shift-painter.wgsl` is the **first production shader** using `var<workgroup>` + `atomic<u32>` — document this in SHADER_AUDIT.md.
