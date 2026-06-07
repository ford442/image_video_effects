# Agent 2C: Distance-Field Sculptor
## Task Specification - Phase C, Agent 2

**Role:** Distance-Field / Wavefront Specialist
**Priority:** HIGH (adds a primitive the library currently lacks)
**Target:** Create 3 new mouse-responsive compute shaders built on distance fields
**Estimated Duration:** 5-6 days

---

## Mission

Introduce **true distance-field computation** to the shader library. The existing Voronoi shaders brute-force every seed (O(N) per pixel); the SDF shaders use hand-coded analytic primitives. Phase C brings the **Jump-Flood Algorithm** (sub-O(N), works with hundreds of seeds), a **fast-sweeping Eikonal solver** for wavefront propagation, and an **interactive SDF constructive-solid-geometry sculptor** with soft-shadow raymarching. All three are driven by the mouse and produce geometric beauty: crystalline tessellations, glowing light fronts, and sculpted 3D masses.

---

## Shader Concepts

### 1. `jfa-aurora-voronoi` (log₂(N) passes: initialize + jump-flood cascade + shade)

**Concept:** Each mouse click drops a colored seed into the scene. The Jump-Flood Algorithm propagates the nearest-seed information across the whole canvas in log₂(resolution) passes (1024 → 10 passes). Shaded with iridescent, aurora-like color-by-distance-gradient.

**Complexity:** High
**Primary Techniques:**
- **Jump-Flood Algorithm** (Rong & Tan 2006): at pass k, each pixel asks the 9 pixels at offset `2^(log2N - k - 1)` which seed is nearest.
- **Gradient-from-distance** for edge glow.
- Seeds live in `extraBuffer` as `(x, y, hue, active)` quads.

**RGBA32FLOAT packing (JFA seed):**
```
dataTextureA.r = nearest seed x  (pixel coords)
dataTextureA.g = nearest seed y
dataTextureA.b = squared distance to that seed
dataTextureA.a = seed ID (cast from u32 at init)
```

**Binding usage:**
- `readTexture` (1): background image (mixed into cells)
- `writeTexture` (2): shaded aurora output
- `dataTextureA` (7): JFA state (ping)
- `dataTextureB` (8): JFA state (pong) — alternate passes swap which is read vs. written
- `extraBuffer` (10): `array<vec4<f32>>` of up to 64 seeds, written by CPU from mouse clicks

```wgsl
// Pass "init": seed pixels from the latest 64 ripple clicks
let id = global_id.x + global_id.y * u32(u.config.z);
var out = vec4<f32>(-1.0, -1.0, 1e20, -1.0);
for (var i = 0u; i < 64u; i++) {
    let seed = u.ripples[i];
    if (seed.z <= 0.0) { continue; }
    let sp = seed.xy * u.config.zw;
    let d2 = dot(sp - vec2<f32>(global_id.xy), sp - vec2<f32>(global_id.xy));
    if (d2 < 1.0) { out = vec4<f32>(sp, 0.0, f32(i)); }
}
textureStore(dataTextureA, vec2<i32>(global_id.xy), out);
```

```wgsl
// Pass "jfa_step_k": each pixel checks offsets ±step, samples 9 neighbors
let step = 1 << (passes_remaining - 1u);
var best = textureLoad(dataTextureA, vec2<i32>(global_id.xy), 0);
for (var dy = -1; dy <= 1; dy++) {
  for (var dx = -1; dx <= 1; dx++) {
    let sp_pix = vec2<i32>(global_id.xy) + vec2<i32>(dx, dy) * i32(step);
    let cand = textureLoad(dataTextureA, sp_pix, 0);
    if (cand.a < 0.0) { continue; }
    let d2 = dot(cand.xy - vec2<f32>(global_id.xy), cand.xy - vec2<f32>(global_id.xy));
    if (d2 < best.z) { best = vec4<f32>(cand.xy, d2, cand.a); }
  }
}
textureStore(dataTextureB, vec2<i32>(global_id.xy), best);
```

```wgsl
// Shade pass: color by distance gradient → aurora shimmer
let me    = textureLoad(dataTextureA, pix, 0);
let dx    = textureLoad(dataTextureA, pix + vec2<i32>(1,0), 0).z
          - textureLoad(dataTextureA, pix - vec2<i32>(1,0), 0).z;
let dy    = textureLoad(dataTextureA, pix + vec2<i32>(0,1), 0).z
          - textureLoad(dataTextureA, pix - vec2<i32>(0,1), 0).z;
let grad  = normalize(vec2<f32>(dx, dy) + 1e-5);
let dist  = sqrt(me.z);
let hue   = u.ripples[i32(me.a)].w + 0.2 * sin(dist * u.zoom_params.x);
let edge  = smoothstep(u.zoom_params.y, 0.0, fract(dist * u.zoom_params.z));
let rgb   = hsv_to_rgb(vec3<f32>(hue, 0.8, 1.0)) * (0.6 + 0.4 * grad.x)
          + vec3<f32>(edge * u.zoom_params.w);
```

**Visual:** Every click blooms into a cell of glowing color; cell boundaries light up as iridescent edges. Moving the mouse through existing cells warps distance-field contours, producing the shimmering of the aurora borealis.

**Params:**
- x: Contour frequency (how many iso-bands per cell)
- y: Edge sharpness
- z: Contour spacing (pixels per band)
- w: Edge glow strength

**RGB-from-RGBA strategy:** Input image alpha masks where seeds are allowed — alpha<0.1 rejects seed placement so transparent regions become "void" between cells. Output RGB only (alpha set to 1.0).

---

### 2. `sdf-field-sculptor` (3-pass: splat, raymarch, composite)

**Concept:** The mouse is a 3D sculptor that adds/subtracts soft-min SDF primitives onto a persistent scalar field. Pass 2 raymarches the field with soft shadows and ambient occlusion. Wipe the image away and sculpt pure marble-like forms; or leave the image underneath and etch glowing sigils on top.

**Complexity:** High
**Primary Techniques:**
- Persistent scalar SDF in `writeDepthTexture` (`r32float`)
- Soft-min CSG union: `smin(a, b, k) = -log(exp(-k·a) + exp(-k·b)) / k`
- Analytic gradient via 4-tap finite differences
- Ambient occlusion via short-ray integration

**RGBA32FLOAT packing (SDF + gradient):**
```
dataTextureA.r = sdf value (persistent)
dataTextureA.g = ∂sdf/∂x
dataTextureA.b = ∂sdf/∂y
dataTextureA.a = material ID (cycles with u.config.y click count)
```

**Binding usage:**
- `readTexture` (1): backdrop image
- `writeTexture` (2): final composite
- `writeDepthTexture` (6): raw SDF (can also be read via depth sampler)
- `dataTextureA` (7): SDF + gradient + material
- `dataTextureB` (8): lighting accumulator (HDR)

```wgsl
// Pass 1: splat mouse primitive into SDF with smooth-min union
let mouse = u.zoom_config.yz * u.config.zw;
let r     = u.zoom_params.x * 120.0;
let d_new = length(vec2<f32>(global_id.xy) - mouse) - r;

let prev  = textureLoad(dataTextureA, vec2<i32>(global_id.xy), 0);
let k     = 16.0;

// Smooth union if left-press, smooth subtraction if long-held (click count odd)
var d_combined: f32;
if ((u32(u.config.y) & 1u) == 0u) {
    d_combined = -log(exp(-k*prev.r) + exp(-k*d_new)) / k;          // union
} else {
    d_combined =  log(exp( k*prev.r) + exp(-k*d_new)) / k;          // subtraction
}

// Finite-difference gradient (sampled across a 3x3 neighborhood)
let dx = textureLoad(dataTextureA, pix + vec2<i32>(1,0), 0).r - prev.r;
let dy = textureLoad(dataTextureA, pix + vec2<i32>(0,1), 0).r - prev.r;
textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(d_combined, dx, dy, prev.a + step(d_new, 0.0)));
textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d_combined, 0, 0, 0));
```

```wgsl
// Pass 2: raymarch lighting — traverse the 2D SDF as if it were a 3D heightfield
var p  = uv_to_world(uv);
var t  = 0.0; var glow = 0.0;
for (var i = 0; i < 32; i++) {
    let d = textureLoad(dataTextureA, pix_at(p), 0).r;
    if (d < 0.5) { break; }
    t    += max(d * 0.6, 1.0);
    glow += exp(-d * u.zoom_params.y) / f32(i + 1);    // halo glow
    p    += light_dir * max(d, 1.0);
}
// Ambient occlusion: count nearby occupied pixels
var ao = 0.0;
for (var j = 0; j < 5; j++) {
    let dd = textureLoad(dataTextureA, pix + ao_offsets[j], 0).r;
    ao += clamp(dd / ao_radii[j], 0.0, 1.0);
}
textureStore(dataTextureB, pix, vec4<f32>(glow * ao, 0, 0, 0));
```

**Visual:** A blank canvas becomes a sculptor's space — drag to draw smooth organic blobs, click-repeatedly to subtract. Lit with a soft directional light, the form casts blurry shadows, picks up occlusion darkening in crevices, and glows at edges.

**Params:**
- x: Brush radius
- y: Glow falloff
- z: Light angle (0-1 → 0-2π)
- w: Backdrop blend (0 = pure marble, 1 = image only shown inside form)

**RGB-from-RGBA strategy:** Output alpha fixed at 1. Input RGBA is sampled only when the SDF value is negative (inside form), and alpha multiplies the backdrop blend.

---

### 3. `eikonal-lantern` (iterative fast-sweeping: 4 passes per frame)

**Concept:** The mouse is a lantern source. An Eikonal equation `|∇T| = 1/speed(x,y)` is solved to compute travel-time from the source to every pixel; speed is modulated by the image's luminance so bright regions propagate fast and dark regions slow down. Render shows a glowing wavefront crawling across the scene and being refracted by the underlying image.

**Complexity:** High
**Primary Techniques:**
- **Fast-sweeping method**: four diagonal sweeps (↘, ↙, ↗, ↖) converge the solution in ~4-8 full sweeps.
- Speed map derived from image gradient magnitude.
- Isochrone rendering: `color = palette(fract(T * frequency))`.

**RGBA32FLOAT packing:**
```
dataTextureA.r = travel-time T
dataTextureA.g = speed(x,y)
dataTextureA.b = source-direction gradient (∂T/∂x)
dataTextureA.a = isochrone index (T * freq mod 1)
```

**Binding usage:**
- `readTexture` (1): source image that modulates speed
- `writeTexture` (2): isochrone render
- `dataTextureA` (7): travel-time + gradient
- `dataTextureB` (8): sweep pong buffer (needed because sweep direction depends on pass)

```wgsl
// Speed map: dark = slow, bright = fast, edges = barriers
let luma = dot(textureLoad(readTexture, pix, 0).rgb, vec3<f32>(0.299, 0.587, 0.114));
let dx = luma_at(pix + vec2<i32>(1,0)) - luma_at(pix - vec2<i32>(1,0));
let dy = luma_at(pix + vec2<i32>(0,1)) - luma_at(pix - vec2<i32>(0,1));
let edge = length(vec2<f32>(dx, dy));
let speed = mix(0.1, 2.0, luma) * exp(-edge * u.zoom_params.x * 10.0);
```

```wgsl
// Sweep kernel (one of four directions, selected by pass index)
// For sweep ↘: read T(i-1, j) and T(i, j-1), update T(i,j)
let Tx = textureLoad(dataTextureA, pix + vec2<i32>(-1, 0), 0).r;
let Ty = textureLoad(dataTextureA, pix + vec2<i32>( 0,-1), 0).r;
let h  = 1.0 / speed;
// Upwind finite-difference update
let a = min(Tx, Ty);
let b = max(Tx, Ty);
var Tn: f32;
if (b - a >= h) { Tn = a + h; }
else { Tn = 0.5 * (a + b + sqrt(2.0 * h*h - (b-a)*(b-a))); }
let T_cur = textureLoad(dataTextureA, pix, 0).r;
textureStore(dataTextureA, pix, vec4<f32>(min(T_cur, Tn), speed, dx, fract(Tn * u.zoom_params.z)));
```

**Visual:** A glowing front emanates from the cursor like a sonar ping, slows down as it enters dark regions of the image (like light entering glass) and speeds through bright regions. Isochrone rings paint the scene in concentric contours that warp to match image structure — an optical map of "time to reach each point".

**Params:**
- x: Edge-as-barrier strength (0 = image has no effect, 1 = edges stop wave)
- y: Palette frequency along isochrones
- z: Isochrone count per unit time
- w: Source strength (bumps speed at mouse to force a fresh ping)

**RGB-from-RGBA strategy:** Input alpha sets the speed floor — transparent pixels become `speed=0.01` barriers (light can't propagate through). Output RGB encodes the wavefront.

---

## Deliverables

| File | Lines | Notes |
|------|-------|-------|
| `public/shaders/jfa-aurora-voronoi-init.wgsl` | ~40 | Seeds from ripples |
| `public/shaders/jfa-aurora-voronoi-step.wgsl` | ~50 | Single JFA step (parameterized step size) |
| `public/shaders/jfa-aurora-voronoi-shade.wgsl` | ~60 | Gradient + aurora shading |
| `shader_definitions/interactive-mouse/jfa-aurora-voronoi.json` | ~100 | log2(N) pass chain |
| `public/shaders/sdf-field-sculptor-splat.wgsl` | ~70 | CSG union/subtract |
| `public/shaders/sdf-field-sculptor-light.wgsl` | ~80 | Raymarch + AO |
| `public/shaders/sdf-field-sculptor-composite.wgsl` | ~40 | Image blend |
| `shader_definitions/interactive-mouse/sdf-field-sculptor.json` | ~80 | |
| `public/shaders/eikonal-lantern-sweep.wgsl` | ~60 | Single directional sweep |
| `public/shaders/eikonal-lantern-render.wgsl` | ~50 | Isochrone palette render |
| `shader_definitions/interactive-mouse/eikonal-lantern.json` | ~80 | |

---

## Validation Checklist

- [ ] JFA converges to correct nearest-seed for test seed set (validated against brute-force O(N) reference).
- [ ] SDF sculpt persists across frames (uses `dataTextureC` to feed previous state into `dataTextureA`).
- [ ] Eikonal solver converges in ≤8 full sweeps (4 directions × 2 rounds).
- [ ] All three shaders use the 13-binding contract unmodified.
- [ ] Each shader's header comment documents its RGBA32FLOAT packing scheme.
