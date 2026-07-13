# Fireworks & Pyrotechnics Library Guide

> Family conventions for generative fireworks/pyro shaders in Pixelocity.  
> Read this before adding a new variant.

## Current family roster

> See also `agents/FIREWORKS_CONTRIBUTOR_KIT.md` for the full list including image-effect variants.

### Core generative fireworks

| ID | What it covers |
|---|---|
| `gen-fireworks-nocturne` | Classic multi-shell night display, gravity bursts, embers, trails, mouse command shells. |
| `gen-fireworks-willow-cascade` | Long hanging golden/silver willow trails with wind drift. |
| `gen-fireworks-chrysanthemum` | Dense spherical shells with concentric ring layers. |
| `gen-fireworks-crackle-palm` | Multi-stage shells: primary burst → delayed crackle → palm fronds. |
| `gen-fireworks-ring-shell` | Halo / donut ring bursts. |
| `gen-fireworks-crossette` | Four-arm split crossette shells. |
| `gen-fireworks-kamuro-gold` | Slow gold/silver glitter rain. |
| `gen-fireworks-roman-candle` | Vertical star barrage from tubes. |
| `gen-fireworks-horse-tail` | Brocade / horse-tail long golden streamers. |
| `gen-fireworks-comet-trail` | Blazing comet head + luminous trail. |
| `gen-fireworks-fan-shell` | Wide hemisphere fan spread. |
| `gen-fireworks-strobe-shell` | Rhythmic multi-flash strobe bursts. |
| `gen-fireworks-wind-ripple` | Shells drift with wind; ripple events trigger directed barrages. |
| `gen-fireworks-smoke-bloom` | Volumetric smoke layers and enhanced light bloom. |
| `gen-fireworks-audio-symphony` | Rhythm-driven display: bass launches, mids secondary bursts, treble micro-sparks. |

### Image / video-reactive pyrotechnics

| ID | What it covers |
|---|---|
| `gen-image-pyro` | Photo biases launches and spark colors. |
| `gen-image-pixel-detonation` | Pixel-to-spark lift with edge-ignited launches and depth-aware bursts. |
| `fireworks-edge-ignite` | Contours / edges become ignition lines. |
| `fireworks-portrait-burst` | Bright regions detonate as burst cores. |
| `fireworks-patriotic-july4` | Red/white/blue July 4th palette. |
| `fireworks-depth-parade` | Depth-layered sequential launches. |

## Non-negotiable contract

Copy the header **verbatim** from `public/shaders/_template_canonical_compute.wgsl` or from any existing fireworks shader. Do not invent, rename, or reorder bindings.

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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = p1…p4 sliders
  ripples: array<vec4<f32>, 50>,
};
```

- Entry point: `@compute @workgroup_size(16, 16, 1) fn main(@builtin(global_invocation_id) global_id: vec3<u32>)`
- Bounds guard is mandatory.
- Write `writeTexture`, `writeDepthTexture`, and at least one of `dataTextureA`/`dataTextureB` every frame.
- Use `dataTextureC` for temporal persistence (trails/afterglow/smoke).

## Audio mapping convention

Always read the same three channels:

```wgsl
let bass   = plasmaBuffer[0].x;  // 20–200 Hz, ~0–2
let mids   = plasmaBuffer[0].y;  // 200–2000 Hz, ~0–2
let treble = plasmaBuffer[0].z;  // 2k–20k Hz, ~0–2
```

Recommended mapping:
- **Bass** → shell launch intensity, primary detonation size, launch frequency.
- **Mids** → secondary bursts, ring layers, shell count.
- **Treble** → micro-crackle, sparkle dust, high-frequency pops.

## Parameter convention

Map `u.zoom_params.x/y/z/w` to four sliders with these semantic defaults:

| Slider | Common semantic | Range |
|---|---|---|
| p1 (`zoom_params.x`) | Energy / Size / Power | 0–1 |
| p2 (`zoom_params.y`) | Timing / Density / Layers / Sensitivity | 0–1 |
| p3 (`zoom_params.z`) | Trail length / Spark count / Bloom strength | 0–1 |
| p4 (`zoom_params.w`) | Color drift / Hue shift / Warmth | 0–1 (or -1–1 for hue twist) |

Use `mix(min, max, param)` to derive shader units.

## Mouse convention

```wgsl
let mouse    = vec2<f32>(u.zoom_config.yz);
let mouseUV  = (mouse - res * 0.5) / min(res.x, res.y);
let mouseDown = u.zoom_config.w;

if (mouseDown > 0.5) {
  // launch command shell at mouseUV
}
```

## Depth convention

```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / res, 0.0).r;
let depthBoost = 0.7 + depth * 0.6;
```

Use it as a compositing boost or to make foreground bursts pop. Fireworks shaders usually write `0.0` to depth.

## Canonical helper recipes

Reuse these exact forms for visual consistency:

```wgsl
const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453123); }

fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var v = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { v += a * vnoise(p * f); f *= 2.02; a *= 0.5; }
  return v;
}

fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv - c);
  return (exp(-d * d / (r * r * 0.5)) + 0.3 * exp(-d / (r * 3.0))) * i;
}

fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32, drag: f32) -> vec2<f32> {
  let t = age;
  let df = exp(-drag * t);
  return o + vec2<f32>(v.x * df, v.y * df - g * t * t * 0.5);
}
```

## Temporal feedback

```wgsl
let prev = textureLoad(dataTextureC, pixel, 0).rgb;
let decay = mix(0.92, 0.98, trailParam);
col = mix(prev * decay + smoke, col, 0.25);
textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
textureStore(dataTextureB, pixel, vec4<f32>(col * 0.55 + prev * 0.38, 1.0));
```

## Semantic alpha

```wgsl
let alpha = clamp(length(col) * 1.1 + 0.15, 0.12, 0.97);
```

Never hardcode `alpha = 1.0` unless the shader is intentionally opaque.

## Adding a new shader

1. Pick a clear gap from the roster above; avoid duplicating an existing archetype.
2. Scaffold: `python3 scripts/new_shader.py my-firework-name --category generative`.
3. Replace the stub with effect code, keeping the contract intact.
4. Create `shader_definitions/generative/<id>.json` with 4 `updatedParams`.
5. Run:
   - `node scripts/generate_shader_lists.js`
   - `npm run build:manifest`
   - `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`
   - `node scripts/validate-naga.js public/shaders` (if naga installed)
   - `npm test -- --watchAll=false --ci`
6. Update this guide’s roster and `memory/YYYY-MM-DD.md`.

## Anti-patterns

- `textureSample(...)` in compute → use `textureSampleLevel(..., 0.0)`.
- `tan(x)` → use `sin(x) / cos(x)`.
- Two-arg `@workgroup_size(16, 16)` → use three explicit dimensions.
- Writing same pixel from multiple threads → each thread writes once.
- Binding names/numbers that drift from the canonical header.
