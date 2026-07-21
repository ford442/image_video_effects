# Swarm Brief: data-slicer-interactive

**Role:** Algorithmist
**Name:** Data Slicer
**Category:** interactive-mouse
**Description:** Glitchy horizontal slicing with FBM-warped torn edges, click-triggered slice bursts from ripple history, bass-modulated slice count, and semantic alpha at slice boundaries.
**Current lines:** 189
**Target lines:** 239–279 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on the math and procedural structure of the effect:
- fbm-driven slice offset jitter, branchless: perturb each slice's displacement with smooth fbm noise using select/mix, no divergent branches.
- Audio band mapping: bass (plasmaBuffer[0].x) drives slice density, mids (plasmaBuffer[0].y) drive slice displacement magnitude.
- Mouse-down spawns a slice shockwave ripple using the u.ripples array: an expanding ring that locally amplifies slice offsets as it travels.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w, replacing the 4 most important hardcoded constants. Add them to the JSON updatedParams with index 0-3, sensible name/default/min/max/step.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional — only declare it if the shader already uses it.

## JSON Parameters / Controls

```json
{
  "id": "data-slicer-interactive",
  "name": "Data Slicer",
  "url": "shaders/data-slicer-interactive.wgsl",
  "description": "Glitchy horizontal slicing with FBM-warped torn edges, click-triggered slice bursts from ripple history, bass-modulated slice count, and semantic alpha at slice boundaries.",
  "params": [
    {
      "id": "slice_count",
      "name": "Slice Count",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "slice_width",
      "name": "Slice Width",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "fbm_warp",
      "name": "FBM Warp",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "color_shift",
      "name": "Color Shift",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "glitch",
    "audio-reactive",
    "temporal",
    "upgraded-rgba"
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "audio-reactive",
    "glitch",
    "feedback",
    "temporal",
    "fbm",
    "slice"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Slice Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Displacement",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Jitter Amount",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Shockwave Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Data Slicer Interactive — Phase B Multi-Pass-Architect Upgrade
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-feedback,
//            depth-aware, chromatic-aberration, aces-tone-map,
//            lod-noise, early-exit, branchless-ripple, field-cache
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const EPS: f32 = 1e-4;

// ── Core math ────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbmLod(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Entry ────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let audio = plasmaBuffer[0];
    let bassRaw = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Bass envelope readback with smooth attack/release
    let prevBass = prev.a;
    let attackK = select(0.15, 0.8, bassRaw > prevBass);
    let bass = mix(prevBass, bassRaw, attackK);

    // Parameters
    let sliceCountBase = mix(4.0, 32.0, u.zoom_params.x);
    let sliceCount = sliceCountBase * (1.0 + bass * 0.5);
    let sliceWidth = mix(0.005, 0.08, u.zoom_params.y);
    let fbmWarpAmt = u.zoom_params.z * 0.06;
    let colorShift = u.zoom_params.w * 0.1;

    // Gravity well
    let dMouse = uv01 - mouse;
    let distMouse = length(dMouse);
    let gravity = 1.0 - smoothstep(0.0, 0.35, distMouse);

    // Slice construction
    let sliceIndex = floor(uv01.y * sliceCount);
    let invSliceCount = 1.0 / max(sliceCount, EPS);
    let sliceY = sliceIndex * invSliceCount;
    let nextSliceY = (sliceIndex + 1.0) * invSliceCount;

    // LOD: fewer noise octaves far from the mouse interest point
    let lodOct = select(2, 4, distMouse < 0.4);

    // FBM-warped slice edges
    let edgeNoise = fbmLod(vec2<f32>(uv01.x * 8.0, sliceY * 4.0 + time * 0.3), lodOct);
    let warpedSliceWidth = sliceWidth + edgeNoise * fbmWarpAmt;
    let distToSlice = min(abs(uv01.y - sliceY), abs(uv01.y - nextSliceY));
    let strength = 1.0 - smoothstep(0.0, max(warpedSliceWidth, EPS), distToSlice);

    // Early exit: no slice or gravity influence — passthrough with valid state
    if (strength < 0.005 && gravity < 0.01) {
        let base = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
        let alpha = clamp(luma(base) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);
        textureStore(writeTexture, pixel, vec4<f32>(base, alpha));
        textureStore(dataTextureA, pixel, vec4<f32>(base, bass));
        textureStore(dataTextureB, pixel, vec4<f32>(0.0, 0.0, 0.0, bass));
        textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    // Click-triggered slice bursts (branchless accumulation)
    var burst = 0.0;
    let rippleCount = u32(u.config.y);
    let invAgeMax = 1.0 / 1.2;
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rDist = length(uv01 - rp.xy);
        let rAge = time - rp.z;
        let rBand = abs(rDist - rAge * 0.5);
        let rippleActive = f32(rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
        let decay = clamp(1.0 - rAge * invAgeMax, 0.0, 1.0);
        burst += rippleActive * decay * 0.15 * sin(rDist * 50.0 - rAge * 20.0);
    }

    // Quantized jitter modulated by mids
    let quant = mix(20.0, 70.0, mids);
    let quantY = floor(uv01.y * quant) / quant;
    let n = valueNoise(vec2<f32>(quantY * 10.0, time * 3.0 * (1.0 + treble)));

    var offset = (n - 0.5) * 0.3 * strength + burst * strength;
    var split = colorShift * strength * (1.0 + bass * 2.0);
    let alphaMod = 1.0 - strength * 0.35;

    // Gravity deformation + depth parallax
    offset += gravity * 0.02 * sin(uv01.x * 20.0 + time);
    split *= 1.0 + depth * 0.5;

    // Radial chromatic aberration
    let center = vec2<f32>(0.5);
    let delta = uv01 - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let caStr = (0.003 * (1.0 + bass) + depth * 0.001) * strength;

    let rUv = clamp(uv01 + vec2<f32>(offset + split, 0.0) + dir * caStr, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUv = clamp(uv01 + vec2<f32>(offset - split, 0.0) - dir * caStr * 0.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv01 + vec2<f32>(offset, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;

    // Temporal feedback trails
    let feedbackUV = clamp(uv01 + vec2<f32>(offset * 0.3, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let prevCol = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0);
    let fbAmt = 0.12 * strength + mouseDown * 0.25;
    var color = vec3<f32>(r, g, b);
    color = mix(color, prevCol.rgb, fbAmt);

    // Treble sparkle + depth boost + tone map
    color += vec3<f32>(treble * strength * 0.25, treble * strength * 0.15, treble * strength * 0.1);
    color = mix(color, color * 1.3, depth * strength * 0.5);
    color = acesToneMap(color * (0.9 + mids * 0.2));

    // Semantic alpha: interaction intensity
    let alpha = clamp(luma(color) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3) * alphaMod;

    // Write outputs: trail cache in A, field cache in B, depth pass-through
    let trail = mix(prevCol.rgb * 0.92, color, 0.15 + bass * 0.15);
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, bass));
    textureStore(dataTextureB, pixel, vec4<f32>(strength, offset, split, bass));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
