# Fireworks & Pyrotechnics — Contributor Kit

> **Audience:** Human contributors and AI agents adding fireworks / pyrotechnic shaders to Pixelocity.  
> **Required preamble:** Read [`agents/WGSL_BUILTINS_GENERATIVE.md`](./WGSL_BUILTINS_GENERATIVE.md) first — especially §0 (canonical header), §3 (textures in compute), and §11 (anti-patterns).  
> **Parent epic:** GitHub [#897](https://github.com/ford442/image_video_effects/issues/897) (series) · [#898](https://github.com/ford442/image_video_effects/issues/898) (variants).

---

## 1. Add-Shader Checklist

| # | Action | Command / path |
|---|--------|----------------|
| 1 | **Pick a category** | **Generative** (procedural night sky) → `shader_definitions/generative/` · **Image effect** (photo/video reactive) → `shader_definitions/image/` |
| 2 | **Create WGSL** | `public/shaders/<id>.wgsl` (e.g. `gen-fireworks-willow-cascade.wgsl`) |
| 3 | **Paste canonical header** | See §2 below — copy verbatim from `WGSL_BUILTINS_GENERATIVE.md` §0 |
| 4 | **Implement `@compute` main** | `@workgroup_size(16, 16, 1)`, bounds guard, `textureStore` to `writeTexture` |
| 5 | **Create JSON definition** | `shader_definitions/<category>/<id>.json` — same base name as WGSL |
| 6 | **Fill four slider slots** | Generative: `updatedParams` with `index` 0–3 · Image: `params` array (4 entries) |
| 7 | **Run generator** | `node scripts/generate_shader_lists.js` |
| 8 | **Validate** | See §8 |
| 9 | **Smoke-test in UI** | `BROWSER=none npm start` → search shader name, tweak sliders, click/hold mouse, play audio |
| 10 | **Commit** | WGSL + JSON + regenerated `public/shader-lists/*.json` |

**Common failures**

| Symptom | Fix |
|---------|-----|
| Shader missing from UI | JSON `id` must match filename stem; generator skipped file → check console |
| `missing @compute entry point` | Use `@compute`, not `@fragment` |
| Naga: `textureSample` invalid | Use `textureSampleLevel(..., 0.0)` in compute |
| Black canvas | No `textureStore(writeTexture, ...)` or alpha always 0 |
| Sliders do nothing | Read all four `u.zoom_params` components in shader code |

---

## 2. Canonical 13-Binding Contract

**Copy this verbatim.** Do not reorder bindings, rename resources, or embed textures inside `Uniforms`.

```wgsl
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution (w, h)
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse (pixel coords), .w = mouse_down (>0.5)
  zoom_params: vec4<f32>,  // .xyzw = UI sliders p1–p4 (always 0–1 from engine)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = time_created, .w = strength
};
```

### Binding cheat-sheet

| Binding | Name | Role in fireworks shaders |
|---------|------|---------------------------|
| 1 | `readTexture` | Source image / video frame (`textureSampleLevel`) |
| 4 | `readDepthTexture` | Depth map — foreground launches higher/faster |
| 9 | `dataTextureC` | **Read** previous-frame glow/trails (`textureLoad`) |
| 7–8 | `dataTextureA/B` | **Write** accumulation / feedback state |
| 2 | `writeTexture` | Final colour + semantic alpha |
| 6 | `writeDepthTexture` | Depth output (often `0.0` for pure pyro) |
| 12 | `plasmaBuffer` | Bass / mids / treble audio |

> **There is no `public/shaders/util/helpers.wgsl`.** WGSL has no `import` in this pipeline. Inline helpers (`hash1`, `softGlow`, `acesToneMap`, etc.) from existing fireworks shaders or `WGSL_BUILTINS_GENERATIVE.md`.

---

## 3. JSON Definition Templates

### Generative fireworks (`shader_definitions/generative/`)

Folder name = category. Use `updatedParams` with explicit `index` 0–3. Sliders are **normalized 0–1**; map to physical ranges inside WGSL with `mix()`.

```json
{
  "name": "Willow Cascade",
  "category": "generative",
  "tags": ["fireworks", "willow", "trails", "generative", "audio-reactive"],
  "description": "Long drooping golden-silver willow trails with wind drift and heavy temporal feedback.",
  "workgroup_size": [16, 16, 1],
  "updatedParams": [
    { "index": 0, "name": "Trail Length", "default": 0.72, "min": 0, "max": 1, "step": 0.01 },
    { "index": 1, "name": "Droop",        "default": 0.65, "min": 0, "max": 1, "step": 0.01 },
    { "index": 2, "name": "Wind",         "default": 0.35, "min": 0, "max": 1, "step": 0.01 },
    { "index": 3, "name": "Color Warmth", "default": 0.55, "min": 0, "max": 1, "step": 0.01 }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "updated": true,
  "id": "gen-fireworks-willow-cascade",
  "url": "shaders/gen-fireworks-willow-cascade.wgsl",
  "features": []
}
```

### Image-reactive fireworks (`shader_definitions/image/`)

Same WGSL contract; JSON uses `params` (with optional `id` per param). Still maps to `u.zoom_params.xyzw` in shader code.

```json
{
  "id": "fireworks-edge-ignite",
  "name": "Fireworks Edge Ignite",
  "url": "shaders/fireworks-edge-ignite.wgsl",
  "description": "Image contours and edges become ignition lines for pyrotechnic shells.",
  "tags": ["fireworks", "edge", "image-reactive", "audio-reactive"],
  "features": ["audio-reactive", "temporal", "semantic-alpha", "depth-aware"],
  "params": [
    { "id": "edge",  "name": "Edge Sensitivity", "default": 0.55, "min": 0, "max": 1, "step": 0.01 },
    { "id": "power", "name": "Launch Power",     "default": 0.65, "min": 0, "max": 1, "step": 0.01 },
    { "id": "trail", "name": "Trail Glow",       "default": 0.5,  "min": 0, "max": 1, "step": 0.01 },
    { "id": "boost", "name": "Color Boost",      "default": 0.6,  "min": 0, "max": 1, "step": 0.01 }
  ]
}
```

---

## 4. Starter Shader Skeleton

Minimal generative fireworks shell — compiles once you add the header from §2 above the `const PI` line.

```wgsl
// gen-fireworks-starter.wgsl — replace effect body, keep contract + stores

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv - c);
  return (exp(-d * d / (r * r * 0.5)) + 0.3 * exp(-d / (r * 3.0))) * i;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res   = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv   = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;

  let p1 = u.zoom_params.x;  // e.g. shell scale
  let p2 = u.zoom_params.y;  // e.g. ring count
  let p3 = u.zoom_params.z;  // e.g. hue / wind
  let p4 = u.zoom_params.w;  // e.g. trail persistence

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  // --- Example: pulsing burst at centre ---
  let radius = mix(0.06, 0.14, 0.5 + 0.5 * sin(time * 2.0)) * (0.7 + bass * 0.5 + p1);
  let glow   = softGlow(uv, vec2<f32>(0.0), radius, 1.0 + mids);
  var col    = vec3<f32>(1.0, 0.85, 0.4) * glow;

  // Temporal trails (long-exposure feel)
  let decay = mix(0.88, 0.97, p4);
  col = mix(prev * decay, col, 0.25 + treble * 0.1);

  col = acesToneMap(col * 1.05);
  let alpha = clamp(length(col) * 1.1 + 0.12, 0.15, 0.96);

  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(dataTextureB, pixel, vec4<f32>(col * 0.6 + prev * 0.35, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
```

**Reference implementations** (copy patterns, not paste whole files):

| Shader | Path | Learn |
|--------|------|-------|
| Willow trails | `public/shaders/gen-fireworks-willow-cascade.wgsl` | Gravity droop, wind, temporal persistence |
| Chrysanthemum rings | `public/shaders/gen-fireworks-chrysanthemum.wgsl` | Concentric ring layers, core flash |
| Multi-stage palm | `public/shaders/gen-fireworks-crackle-palm.wgsl` | Timed secondary bursts |
| Image colour lift | `public/shaders/gen-image-pyro.wgsl` | Sample `readTexture` for spark hues |
| Pixel detonation | `public/shaders/gen-image-pixel-detonation.wgsl` | Bright pixels + edges ignite |
| Edge contours | `public/shaders/fireworks-edge-ignite.wgsl` | Image-effect category |

---

## 5. Four UI Sliders — Fireworks Mapping Guide

Sliders arrive as `u.zoom_params` in **0–1**. Always `mix(min, max, slider)` inside the shader.

| Slot | Fireworks role | Example WGSL |
|------|----------------|--------------|
| **x** | Scale / intensity / shell power | `let power = mix(0.35, 1.8, u.zoom_params.x);` |
| **y** | Complexity (rings, strands, ignition) | `let rings = i32(mix(1.0, 5.0, u.zoom_params.y));` |
| **z** | Spatial / colour (wind, hue, edge sens.) | `let wind = mix(-0.12, 0.35, u.zoom_params.z);` |
| **w** | Temporal (trail decay, lifetime, warmth) | `let decay = mix(0.88, 0.97, u.zoom_params.w);` |

**Rules**

- Read **all four** slots somewhere meaningful (UI feels broken otherwise).
- Prefer smooth `mix` / `smoothstep` — avoid hard jumps when sliders move.
- Name sliders in JSON for the effect (e.g. "Droop" not "Param 2").

---

## 6. Audio & Mouse Cheat-Sheet

```wgsl
let time  = u.config.x;
let res   = vec2<f32>(u.config.zw);

// Audio — smoothed by engine; typical range ~0–2
let bass   = plasmaBuffer[0].x;  // big shells, burst radius, droop
let mids   = plasmaBuffer[0].y;  // secondary rings, launch rate
let treble = plasmaBuffer[0].z;  // crackle, micro-sparks, silver dust

// Mouse — pixel coordinates, not normalized 0–1
let mouse     = vec2<f32>(u.zoom_config.yz);
let mouseDown = u.zoom_config.w;   // > 0.5 while left button held
let mouseUV   = (mouse - res * 0.5) / min(res.x, res.y);  // aspect-correct

// Ripples (optional) — up to 50 click ripples
// u.ripples[i].xy = position, .z = birth time, .w = strength
```

**Typical fireworks patterns**

| Pattern | Code idea |
|---------|-----------|
| Bass → bigger bursts | `let energy = shellPow * (0.6 + bass * 0.7);` |
| Treble → crackle layer | `let n = i32(8.0 + treble * 20.0);` extra micro-sparks |
| Mouse shell | `if (mouseDown > 0.5) { ... softGlow(uv, mouseUV, ...) }` |
| Depth-aware launch | `let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;` |

---

## 7. Variant Roadmap (split work here)

| Variant | Status | ID / path | Notes |
|---------|--------|-----------|-------|
| Fireworks Nocturne | ✅ shipped | `gen-fireworks-nocturne` | Classic multi-mortar night display |
| Image Pyro | ✅ shipped | `gen-image-pyro` | Photo colours drive sparks |
| Willow Cascade | ✅ shipped | `gen-fireworks-willow-cascade` | Long drooping trails |
| Chrysanthemum / Peony | ✅ shipped | `gen-fireworks-chrysanthemum` | Dense ring shells |
| Pixel Detonation | ✅ shipped | `gen-image-pixel-detonation` | Bright pixels + edges |
| Crackle Palm | ✅ shipped | `gen-fireworks-crackle-palm` | Multi-stage palm fronds |
| Ring Shell | ✅ shipped | `gen-fireworks-ring-shell` | Halo / donut bursts |
| Crossette | ✅ shipped | `gen-fireworks-crossette` | Four-arm split |
| Kamuro Gold | ✅ shipped | `gen-fireworks-kamuro-gold` | Slow gold glitter rain |
| Roman Candle | ✅ shipped | `gen-fireworks-roman-candle` | Vertical star barrage |
| Edge Ignite (image) | ✅ shipped | `fireworks-edge-ignite` | Contour launches |
| Portrait Burst (image) | ✅ shipped | `fireworks-portrait-burst` | Bright-region cores |
| Patriotic July 4 (image) | ✅ shipped | `fireworks-patriotic-july4` | R/W/B palette |
| Depth Parade (image) | ✅ shipped | `fireworks-depth-parade` | Layered depth launches |
| **Depth-aware 3D burst** | 🔲 open | — | Parallax from `readDepthTexture`; speed ∝ depth |
| **Bioluminescent / ferrofluid pyro** | 🔲 open | — | Neon HSV palette pulsing with bass |
| **Quantum teleport sparks** | 🔲 open | — | Symmetric partner jumps every ~0.12 s |
| **Multi-barrage sync** | 🔲 open | — | Shells timed to beat grid (bass zero-cross) |
| **Smoke / afterglow-only pass** | 🔲 open | — | Heavy `dataTextureC` persistence, faint shells |

Pick a 🔲 row, announce it on #898, and use a fresh `gen-fireworks-*` or `fireworks-*` id.

---

## 8. Validation Commands

```bash
# Register shader in manifests (required after every new JSON)
node scripts/generate_shader_lists.js

# Structural checks (compute entry, workgroup size, textureStore)
python3 scripts/test_workgroup_gate.py

# Naga WGSL compile check (requires naga-cli — see scripts/NAGA_README.md)
node scripts/validate-naga.js

# Unit tests (renderer / manifest plumbing)
npx react-scripts test --watchAll=false --ci

# Dev server (BROWSER=none avoids headless VM browser launch)
BROWSER=none npm start
```

**Not available in this repo:** `npm run wgsl-validate`, `npm run render -- --shader …` (use naga + dev server instead).

**Cloud VM note:** No GPU in CI/Cloud — canvas may be black; trust naga + unit tests + manual test on a GPU machine.

---

## 9. PR Checklist

- [ ] Canonical 13-binding header unchanged
- [ ] `@compute @workgroup_size(16, 16, 1)` + bounds guard
- [ ] `textureStore(writeTexture, …)` every frame
- [ ] Four sliders read and documented in JSON
- [ ] Audio (`plasmaBuffer`) and mouse (`zoom_config`) used
- [ ] `acesToneMap` on final colour
- [ ] Semantic alpha on `writeTexture` (not hardcoded `1.0` unless intentional)
- [ ] Generator run; `public/shader-lists/<category>.json` updated
- [ ] Naga clean for your new file
- [ ] Screenshot or short clip in PR description

---

*Happy hacking — may your shells compile on the first try.* 🎆