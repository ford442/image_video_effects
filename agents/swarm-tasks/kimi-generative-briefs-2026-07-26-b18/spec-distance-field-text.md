# Swarm Brief: spec-distance-field-text

**Role:** Algorithmist
**Name:** Distance Field Text
**Category:** generative
**Description:** SDF-based procedural glyph overlay with audio-reactive domain warp, depth-aware shadows, temporal feedback trails, ACES tone mapping, and chromatic aberration. Generates abstract runes and symbols as signed distance fields with smooth scaling, glowing edges, and chromatic cycling.
**Current lines:** 220
**Target lines:** 270–310 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This glyph shader samples depth with the wrong UV space and advertises feedback trails that do not exist - fix both honestly:
- FIX THE DEPTH UV (priority 1): the depth passthrough samples readDepthTexture with `uv` (the -1..1 remapped coord) instead of `uv01` - out-of-range samples clamp to edge texels and poison the downstream depth chain. Fix both sample sites to `uv01`.
- MAKE THE TRAILS REAL: JSON/tags claim temporal feedback but dataTextureC is never read. Implement it: store (glyphColor, d) to dataTextureA as now, read back via dataTextureC with decay ~0.92 mixed at <= 0.3 (clamp accumulated pre-tint ~1.2) so glyphs leave phosphor trails. Keep it stable.
- Spectral glyphs: select the active glyph index from per-bin FFT energy (`plasmaBuffer[1..4]`, one bin per glyph) so the dominant band picks the symbol; click ripples (guard `min(u32(u.config.y), 50u)`) as expanding SDF displacement rings.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve `sdGlyph0..3` and the branchless `sdGlyph` index-weight selection VERBATIM - glyph shapes are hand-tuned segment sets. Keep the `overlayMix < 0.001` early-exit passthrough intact.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "spec-distance-field-text",
  "name": "Distance Field Text",
  "url": "shaders/spec-distance-field-text.wgsl",
  "description": "SDF-based procedural glyph overlay with audio-reactive domain warp, depth-aware shadows, temporal feedback trails, ACES tone mapping, and chromatic aberration. Generates abstract runes and symbols as signed distance fields with smooth scaling, glowing edges, and chromatic cycling.",
  "tags": [
    "SDF",
    "distance-field",
    "procedural-text",
    "glyph",
    "overlay",
    "runes",
    "audio-reactive",
    "depth-aware",
    "temporal-feedback",
    "ACES",
    "chromatic-aberration",
    "HDR"
  ],
  "features": [
    "SDF",
    "procedural-text",
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "temporal-feedback",
    "ACES-tone-map",
    "chromatic-aberration"
  ],
  "params": [
    {
      "id": "glyph_scale",
      "name": "Glyph Scale",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "glyph_width",
      "name": "Glyph Width",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "glow",
      "name": "Glow Radius",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "overlay",
      "name": "Overlay Mix",
      "default": 0.7,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.5,
  "updatedParams": [
    {
      "index": 0,
      "name": "Glyph Scale",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Glyph Width",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Glow Radius",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Overlay Mix",
      "default": 0.7,
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
// ═══ spec-distance-field-text ═══════════════════════════════════════════
//  Category: generative
//  Phase: B
//  Features: SDF, procedural-text, glyph, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, chromatic-aberration,
//            signed-distance-field, slot-chain, LOD
//  Complexity: Medium

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
const HASH_K: f32 = 43758.5453123;

// ── Core math ─────────────────────────────────────────────────────────
fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * HASH_K);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}

// LOD-aware domain warp: fewer octaves far from the interest point.
fn domainWarpLOD(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}

// ── SDF primitives ────────────────────────────────────────────────────
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdGlyph0(p: vec2<f32>) -> f32 {
    let s1 = sdSegment(p, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, -0.3));
    let s2 = sdSegment(p, vec2<f32>(0.3, -0.3), vec2<f32>(0.0, 0.4));
    let s3 = sdSegment(p, vec2<f32>(0.0, 0.4), vec2<f32>(-0.3, -0.3));
    let s4 = sdSegment(p, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.15));
    return min(min(s1, s2), min(s3, s4));
}

fn sdGlyph1(p: vec2<f32>) -> f32 {
    let c = abs(length(p) - 0.3);
    let h = sdSegment(p, vec2<f32>(-0.3, 0.0), vec2<f32>(0.3, 0.0));
    let v = sdSegment(p, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.3));
    return min(min(c, h), v);
}

fn sdGlyph2(p: vec2<f32>) -> f32 {
    let db = abs(p) - vec2<f32>(0.3);
    let box = min(max(db.x, db.y), 0.0) + length(max(db, vec2<f32>(0.0)));
    let diag = sdSegment(p, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, 0.3));
    return min(box, diag);
}

fn sdGlyph3(p: vec2<f32>) -> f32 {
    let d1 = sdSegment(p, vec2<f32>(0.0, 0.35), vec2<f32>(0.25, 0.0));
    let d2 = sdSegment(p, vec2<f32>(0.25, 0.0), vec2<f32>(0.0, -0.35));
    let d3 = sdSegment(p, vec2<f32>(0.0, -0.35), vec2<f32>(-0.25, 0.0));
    let d4 = sdSegment(p, vec2<f32>(-0.25, 0.0), vec2<f32>(0.0, 0.35));
    return min(min(min(d1, d2), min(d3, d4)), length(p) - 0.06);
}

// Branchless glyph selection via index weights.
fn sdGlyph(p: vec2<f32>, idx: i32, scale: f32) -> f32 {
    let sp = p / scale;
    let d0 = sdGlyph0(sp); let d1 = sdGlyph1(sp);
    let d2 = sdGlyph2(sp); let d3 = sdGlyph3(sp);
    let w0 = f32(idx == 0); let w1 = f32(idx == 1);
    let w2 = f32(idx == 2); let w3 = f32(idx == 3);
    return (d0 * w0 + d1 * w1 + d2 * w2 + d3 * w3) * scale;
}

fn sdGlyphGrid(p: vec2<f32>, gridScale: f32, time: f32) -> f32 {
    let cell = floor(p * gridScale);
    let local = fract(p * gridScale) - 0.5;
    let h = hash21(cell);
    let glyphIdx = i32(h * 4.0);
    let pulse = 1.0 + sin(time * 2.0 + cell.x * 3.0 + cell.y * 2.0) * 0.1;
    return sdGlyph(local, glyphIdx, pulse / gridScale);
}

// ── Color utilities ───────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Entry point ───────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (uv01 - 0.5) * 2.0;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let overlayMix = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    // Parameter mapping
    let glyphScale = mix(2.0, 12.0, p1);
    let glyphWidth = mix(0.003, 0.02, p2);
    let glowRadius = mix(0.0, 0.05, p3);

    // Base image from slot chain
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;

    // Early exit when the overlay is disabled — keeps base image intact.
    if (overlayMix < 0.001) {
        let alpha = clamp(luma(baseColor) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);
        let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeTexture, pixel, vec4<f32>(baseColor, alpha));
        textureStore(dataTextureA, pixel, vec4<f32>(0.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
        return;
    }

    // LOD: fewer FBM octaves far from the mouse (or screen center when idle).
    let interestDist = length(uv01 - mix(vec2<f32>(0.5), mouse, step(0.5, u.zoom_config.w)));
    let lodOct = i32(clamp(3.0 - interestDist * 4.0, 1.0, 3.0));

    // Domain-warp the glyph coordinate for organic audio-reactive motion
    let warpStr = 0.02 + bass * 0.03;
    let warpedUV = domainWarpLOD(uv, warpStr, lodOct);

    // Glyph SDF
    var d = sdGlyphGrid(warpedUV, glyphScale, time);

    // Branchless mouse reveal
    let mouseDist = length(uv01 - mouse);
    let reveal = fast_exp(-mouseDist * mouseDist * 800.0) * step(0.5, u.zoom_config.w);
    d -= reveal * 0.02;

    // SDF masks
    let glyphMask = 1.0 - smoothstep(-glyphWidth, glyphWidth, d);
    let glowMask = fast_exp(-d * d / (glowRadius * glowRadius + 1e-4)) * (1.0 - glyphMask);
    let shadowMask = 1.0 - smoothstep(-glyphWidth * 2.0, glyphWidth * 2.0, d + 0.025);

    // Glyph color cycling with audio-driven hue shift
    let hue = time * 0.1 + uv.x * 0.2 + uv.y * 0.15 + mids * 0.3 + treble * 0.1;
    let glyphColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * (hue + 0.0)),
        0.5 + 0.5 * cos(TAU * (hue + 0.3333)),
        0.5 + 0.5 * cos(TAU * (hue + 0.6667))
    );
    let glowColor = glyphColor * (1.5 + bass);

    // Composite with depth-aware shadow
    let depthMod = 0.5 + depth * 0.5;
    var outColor = baseColor;
    outColor = mix(outColor, outColor * 0.7 + vec3<f32>(0.0, 0.0, 0.1) * 0.3,
                   shadowMask * 0.4 * overlayMix * depthMod);
    outColor = mix(outColor, outColor + glowColor * glowMask, glowMask * overlayMix);
    outColor = mix(outColor, glyphColor, glyphMask * overlayMix);

    // Generative chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    let dir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    outColor = vec3<f32>(
        outColor.r + dir.x * caStr,
        outColor.g,
        outColor.b - dir.y * caStr * 0.5
    );

    // ACES tone map and semantic alpha
    outColor = acesToneMap(outColor * (0.9 + mids * 0.2));
    let alpha = clamp(luma(outColor) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);

    textureStore(writeTexture, pixel, vec4<f32>(outColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(glyphColor, d));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
```
