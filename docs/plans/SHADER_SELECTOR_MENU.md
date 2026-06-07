# Shader-Based Selector Menu — Design Plan

> **Goal**: Replace the text-list shader selector with an immersive visual browser where the selector UI itself is rendered by generative shaders — each category shown as a live animated tile.  
> **Constraint**: No changes to `Renderer.ts`, `types.ts`, or BindGroups.

---

## 1. Vision

The current selectors (`ShaderMegaMenu`, `ShaderCoordinateMenu`) are standard HTML/CSS dropdowns. The new menu:

- Renders a **grid of live shader tiles** — each cell runs a lightweight shader in a small `<canvas>` using the existing WebGPU renderer
- The **background of the menu itself** is a generative shader (category-specific atmosphere)
- Selecting a category causes the background shader to **transition** to that category's ambient visual
- Hovering a shader tile briefly previews it **full-screen** with an alpha overlay

---

## 2. Two Implementation Scopes

### Scope A — Thumbnail Grid (achievable today, ~1–2 days)

Add a `ShaderThumbnailGrid` component that:

1. Creates one small (128×128) `<canvas>` per visible shader using the existing `Renderer` class
2. Dispatches a single frame of the shader into it (no continuous animation — just the first frame at `time=0`)
3. Displays results as a CSS grid with label overlay
4. Clicking navigates to the shader

**Why static first frame?** Running 20+ live WebGPU instances simultaneously is not safe on all hardware. A single-frame screenshot per visible shader is GPU-friendly.

**Implementation sketch**:
```typescript
// src/components/ShaderThumbnailGrid.tsx
async function renderThumbnail(shaderId: string): Promise<ImageBitmap> {
  const offscreenCanvas = new OffscreenCanvas(128, 128);
  const renderer = new Renderer(offscreenCanvas);
  await renderer.loadShader(shaderId);
  renderer.render({ time: 0, ...defaultUniforms });
  return offscreenCanvas.transferToImageBitmap();
}
```

**State managed**: thumbnail cache in `Map<shaderId, ImageBitmap>`, built lazily as the user scrolls.

---

### Scope B — Full Generative Selector (2–3 days)

A dedicated `ShaderGalaxy` component — a fullscreen WebGPU canvas running a custom `gen-selector-galaxy.wgsl` that:

- Renders **floating label nodes** via signed-distance text (or HTML overlay positioned by GPU-computed coords)
- Each node pulses with the audio spectrum — bass drives node size, treble drives sparkle
- **Category zones** are Voronoi regions colored by category palette
- Clicking a node triggers a **warp transition** (zoom-in effect) before switching shaders

The generative selector is itself a shader in the `public/shaders/` library — it just happens to be the UI.

---

## 3. New Shader: `gen-selector-galaxy.wgsl`

A purpose-built generative shader for use as the selector background. Key visual elements:

### 3.1 Category Palette Map

| Category | Hue | Accent |
|----------|-----|--------|
| `generative` | 260° (violet) | Electric blue |
| `interactive-mouse` | 190° (cyan) | Teal |
| `artistic` | 30° (amber) | Gold |
| `simulation` | 160° (green) | Lime |
| `advanced-hybrid` | 300° (magenta) | Pink |
| `visual-effects` | 10° (red-orange) | Coral |
| `distortion` | 210° (blue) | Indigo |
| `retro-glitch` | 100° (yellow-green) | Neon |
| `liquid-effects` | 200° (sky blue) | Aqua |
| `lighting-effects` | 45° (yellow) | Warm white |
| `geometric` | 240° (blue-violet) | Silver |
| `post-processing` | 0° (neutral) | White |

### 3.2 Shader Structure

```wgsl
// gen-selector-galaxy.wgsl
//
// Renders a voronoi-partitioned starfield where each region represents
// a shader category. Node positions encoded in extraBuffer as:
//   extraBuffer[i*4 + 0] = x (0-1)
//   extraBuffer[i*4 + 1] = y (0-1)
//   extraBuffer[i*4 + 2] = category_hue
//   extraBuffer[i*4 + 3] = selection_state (0=default, 1=hover, 2=active)

fn voronoiCell(uv: vec2<f32>, numNodes: i32) -> vec3<f32> {
    // Returns: .xy = nearest node coords, .z = distance
    var minDist = 99.0;
    var nearest = vec2<f32>(0.0);
    for (var i = 0; i < numNodes; i++) {
        let nx = extraBuffer[i * 4 + 0];
        let ny = extraBuffer[i * 4 + 1];
        let nodePos = vec2<f32>(nx, ny);
        let d = distance(uv, nodePos);
        if d < minDist { minDist = d; nearest = nodePos; }
    }
    return vec3<f32>(nearest, minDist);
}
```

### 3.3 Visual Layers (bottom to top)

1. **Starfield base** — `fbm`-animated star density using `hash21`
2. **Voronoi region fill** — soft-colored by category hue, modulated by `bass`
3. **Region boundaries** — bright thin lines via `abs(voronoi_dist - edge_threshold) < 0.003`
4. **Node glows** — `exp(-d * 20.0)` radial glow around each shader node
5. **Selection ring** — animated `sin(time * 8.0)` pulsing ring on hovered node
6. **Particle trails** — temporal feedback trail from last-selected node to current

### 3.4 Transition Shader: `gen-selector-warp-transition.wgsl`

A short-lived shader (1.5s) that plays when a shader is selected:
- UV space contracts toward the selected node's screen position
- Chromatic aberration increases toward peak then snaps to the new shader
- Uses `zoom_config.yz` (mouse position = selection point) for warp center

```wgsl
// Warp UV toward selection point
let t      = u.config.x;               // 0 → 1 over 1.5s
let center = u.zoom_config.yz;
let warp   = 1.0 - smoothstep(0.0, 1.0, t) * 0.8;
let warped = mix(uv01, center, 1.0 - warp);
let col    = textureSampleLevel(readTexture, u_sampler, warped, 0.0).rgb;
// Chromatic boost mid-transition
let caStr = sin(t * PI) * 0.05;
// ...
```

---

## 4. React Component Architecture

```
ShaderSelectorMenu (new top-level)
├── ShaderGalaxyCanvas          ← runs gen-selector-galaxy.wgsl
│   └── (WebGPU canvas, fullscreen, z-index:100)
├── ShaderNodeLabels            ← HTML overlay, absolute-positioned
│   └── ShaderNodeLabel[]       ← one per shader, pos from extraBuffer
├── CategoryFilterBar           ← horizontal pill filter at top
└── ShaderDetailPanel           ← slides in on node hover (150ms)
    ├── ShaderThumbnail         ← single rendered frame
    ├── ShaderMeta              ← name, category, features list
    └── SelectButton
```

**State flow**:
```typescript
// URL param drives selection; galaxy reads from extraBuffer via JS writes
const [activeCategory, setActiveCategory] = useState<string | null>(null);
const [hoveredShader, setHoveredShader] = useState<string | null>(null);

// Write node positions to extraBuffer when category changes
useEffect(() => {
  const nodes = shaderDefs
    .filter(s => !activeCategory || s.category === activeCategory)
    .map((s, i) => layoutNode(s, i, totalCount));
  writeNodesToExtraBuffer(nodes, renderer);
}, [activeCategory]);
```

---

## 5. Audio Integration

The selector menu is audio-reactive using the existing `plasmaBuffer`:

- **bass** → node glow radius pulses on beat
- **mids** → region boundary brightness modulated at melody frequency  
- **treble** → star shimmer intensity
- When no audio source active → auto-animate with `sin(time)` fallback at `time * 0.3`

---

## 6. Implementation Priority

| Phase | Deliverable | Effort |
|-------|-------------|--------|
| **P0** | `gen-selector-galaxy.wgsl` — standalone shader, looks good in standard render | 0.5 day |
| **P1** | `ShaderThumbnailGrid` (Scope A) — static first-frame grid, replaces ShaderBrowser | 1 day |
| **P2** | `ShaderGalaxyCanvas` + node label overlay | 1 day |
| **P3** | `gen-selector-warp-transition.wgsl` + transition playback logic | 0.5 day |
| **P4** | Audio reactivity tuning + mobile fallback (CSS grid fallback if no WebGPU) | 0.5 day |

---

## 7. Mobile / Fallback Strategy

If `navigator.gpu` is unavailable or the device signals low memory:
- Render static `<img>` thumbnails from pre-generated screenshots stored on VPS
- Fall back to `ShaderMegaMenu` (current HTML selector) — no regression
- Detection: `if (!navigator.gpu) { return <ShaderMegaMenu {...props} /> }`

---

## 8. Files to Create

| File | Purpose |
|------|---------|
| `public/shaders/gen-selector-galaxy.wgsl` | Main selector background shader |
| `public/shaders/gen-selector-warp-transition.wgsl` | Selection transition shader |
| `src/components/ShaderSelectorMenu.tsx` | Top-level menu component |
| `src/components/ShaderGalaxyCanvas.tsx` | WebGPU canvas for galaxy |
| `src/components/ShaderThumbnailGrid.tsx` | Static thumbnail grid (Scope A) |
| `src/components/ShaderNodeLabel.tsx` | HTML overlay label for each node |
| `shader_definitions/generative/gen-selector-galaxy.json` | Shader def (adds it to library) |

---

## 9. Open Questions

1. **Node layout algorithm**: Force-directed layout (spring model) vs. radial category arcs vs. t-SNE from existing `shader_coordinates.json`? The coordinates file already has 2D positions — **use those directly** for P2.

2. **Label rendering**: HTML overlay (easier, handles long names) vs. in-shader SDF text (cooler, harder). Start with HTML overlay.

3. **Performance budget for thumbnails**: Can we run 20 thumbnails simultaneously? Safer to queue them 4 at a time and show a placeholder shimmer while loading.
