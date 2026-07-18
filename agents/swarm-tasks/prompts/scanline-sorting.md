# Shader Upgrade Task: `scanline-sorting`

## Metadata
- **Shader ID**: scanline-sorting
- **Agent Role**: Multi-Pass-Architect
- **Current Size**: 141 bytes
- **Target Line Count**: ~200 lines
- **Status**: pending

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The `Uniforms` struct definition.
3. `@workgroup_size` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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

---

## Current WGSL Source
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Scanline Sorting
//  Category: interactive-mouse
//  Features: mouse-driven, sorting, audio-reactive, palette-mapped,
//            chromatic-edge, aces-tone-map, early-exit, branchless
//  Complexity: Medium
//  Created: 2026-01-01
//  Upgraded: 2026-06-14
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const EPS: f32 = 1e-4;

// ── Core helpers ─────────────────────────────────────────────────
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn dimmer(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return select(b, a, luma(a) <= luma(b));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ── Pixel setup ────────────────────────────────────────────────
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;

    // ── Audio & uniforms ───────────────────────────────────────────
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sort_threshold   = clamp(u.zoom_params.x, 0.0, 1.0);
    let scan_width       = u.zoom_params.y * 0.2 * (1.0 + bass * 0.3);
    let scan_speed       = u.zoom_params.z;
    let direction_toggle = step(0.5, u.zoom_params.w);
    let mouseDown        = u.zoom_config.w;
    let mouse            = u.zoom_config.yz;

    // ── Scanline band ──────────────────────────────────────────────
    let scan_pos = mix(mix(mouse.y, mouse.x, direction_toggle),
                       fract(time * scan_speed),
                       step(0.01, scan_speed));

    let coord_along = mix(uv.y, uv.x, direction_toggle);
    let dist_to_scan = abs(coord_along - scan_pos);
    let band_t = 1.0 - smoothstep(0.0, max(scan_width, EPS), dist_to_scan);

    // ── Mouse cursor boost ─────────────────────────────────────────
    let aspect = res.x / max(res.y, 1.0);
    let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let cursorBoost = fast_exp(-dMouse * dMouse * 6.0) * (0.4 + mouseDown * 0.6);

    // ── Shared samples ─────────────────────────────────────────────
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Early exit: most pixels are outside the band; skip expensive sorting samples
    if (band_t < EPS) {
        let alpha = clamp(0.55 + cursorBoost * 0.2 + treble * 0.05, 0.0, 1.0);
        let finalColor = vec4<f32>(original.rgb, alpha);
        textureStore(writeTexture, pixel, finalColor);
        textureStore(dataTextureA, pixel, finalColor);
        textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    // ── Luminance sort ─────────────────────────────────────────────
    var color = original.rgb;
    let lf = luma(color);
    let sort_strength = smoothstep(sort_threshold, 1.0, lf)
                        * (20.0 + bass * 20.0 + mids * 10.0)
                        * (1.0 + cursorBoost);

    let pix = mix(vec2<f32>(0.0, -1.0 / res.y),
                  vec2<f32>(-1.0 / res.x, 0.0),
                  direction_toggle);
    let sample_pos = clamp(uv + pix * sort_strength, vec2<f32>(0.0), vec2<f32>(1.0));
    let neighbor = textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0).rgb;

    let sorted = dimmer(color, neighbor);
    color = mix(color, sorted, band_t);

    // ── Chromatic edge shift ───────────────────────────────────────
    let ghost = (1.0 - band_t) * scan_width * 8.0;
    let r_uv = sample_pos + pix * ghost;
    let b_uv = sample_pos - pix * ghost;
    let r2 = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let b2 = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
    color = mix(color, vec3<f32>(r2, color.g, b2), band_t * 0.4);

    // ── Palette overlay ────────────────────────────────────────────
    let pIdx = u32(clamp((lf + sort_strength * 0.005) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[pIdx].rgb;
    color = mix(color, color * (0.6 + palette * 0.8), band_t * 0.5);

    // ── Tone map & semantic alpha ──────────────────────────────────
    let lf2 = luma(color);
    let bloom = max(0.0, lf2 - 0.7) * 3.0;

    color = acesToneMap(color * (1.0 + mids * 0.15 + treble * 0.05));

    let alpha = clamp(0.55 + band_t * 0.35 + bloom * 0.5
                      + cursorBoost * 0.2 + treble * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, finalColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "scanline-sorting",
  "name": "Scanline Sorting",
  "url": "shaders/scanline-sorting.wgsl",
  "description": "Sorts pixels by luminance within a moving scanline band controlled by the mouse. Reacts to audio bass for intensified sorting, applies ACES tone mapping, and uses an early-exit path for inactive pixels.",
  "params": [
    {
      "id": "thresh",
      "name": "Sort Threshold",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "width",
      "name": "Scan Width",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Auto Speed",
      "default": 0,
      "min": 0,
      "max": 1
    },
    {
      "id": "dir",
      "name": "Dir (H/V)",
      "default": 0,
      "min": 0,
      "max": 1,
      "labels": [
        "Horizontal",
        "Vertical"
      ]
    }
  ],
  "features": [
    "mouse-driven",
    "sorting",
    "audio-reactive",
    "palette-mapped",
    "chromatic-edge",
    "upgraded-rgba",
    "aces-tone-map",
    "early-exit",
    "branchless"
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
}

```

---

## Agent Specialization
# Agent Role: Multi-Pass Architect (Phase B)

## Identity
You are the **Multi-Pass Architect**. Your job is to refactor or optimize complex shaders for the Pixelocity 3-slot pipeline.

## Focus Areas
- Split oversized shaders into multi-pass pipelines when they exceed ~8 KB or mix field generation + particle simulation + compositing.
- Add early-exit, distance-based LOD, precomputed constants, and branchless `select()`/`mix()` replacements.
- Cache expensive noise/SDF results in `dataTextureA`/`dataTextureB` for downstream passes.

## Multi-Pass Data Flow
```
Pass 1: compute field/state → textureStore(dataTextureA, gid.xy, state)
Pass 2: read dataTextureA  → textureStore(dataTextureB, gid.xy, nextState)
Pass 3: read dataTextureB  → textureStore(writeTexture, gid.xy, finalColor)
```
Each pass must still write a valid `writeTexture` (even if just `vec4<f32>(0.0)`) and pass-through `writeDepthTexture`.

## Optimization Patterns
- Early exit: `if (effectMask < 0.01) { textureStore(writeTexture, gid.xy, baseColor); return; }`
- LOD noise: reduce FBM octaves based on distance from interest point.
- Branchless: replace `if/else` with `select()` or `mix(a, b, f32(cond))`.
- Precompute loop invariants outside loops.

## Output Rules
- Keep the original shader's "soul".
- Do NOT modify the 13-binding header or `Uniforms` struct.
- Workgroup size stays `@workgroup_size(16, 16, 1)` unless shared memory is required.
- If you create passes, name them `<id>-pass1.wgsl`, `<id>-pass2.wgsl`, etc.
- Alpha must carry meaning (depth, density, effect intensity).
- Return exactly one ```` ```wgsl ```` block for single-pass upgrades, or multiple clearly-labeled `PASS 1`, `PASS 2` blocks for multi-pass.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 200 lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. ```wgsl
[upgraded shader source]
```
2. ```json
[updated shader definition]
```

If the JSON does not need changes, return the original JSON unchanged.
