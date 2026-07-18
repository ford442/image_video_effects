# KIMI SWARM TASK — CREATION — audio-reactive-prism-shatter

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
Create a new **input-driven** visual effect: `audio-reactive-prism-shatter`.

Visual concept: the source image shatters into voronoi prism shards around an epicenter (mouse position when held, else screen center). **Bass** drives the shatter: each shard displaces outward from the epicenter by `bass_env` * per-shard hash distance — hard hits fracture the image wide, silence lets it settle back. **Mids** drive the prism refraction: each shard spectrally splits the sampled image (r/g/b offset along the shard's displacement direction), split width scaling with mids, plus a thin-film iridescent tint per facet. **Treble** ignites glint edges: shard boundaries (F2-F1 voronoi edges) sparkle white-hot with treble. The image must remain fully readable at zero audio — shatter is a modulation, never a replacement. Settle motion should use `bass_env` release so shards glide home smoothly.

## DIFFERENTIATE FROM
- `crystalline-shatter`: static crystalline fracture — yours is audio-driven and image-preserving.
- `audio-reactive-rgb-dispersion`: uniform channel split — yours is per-shard directional refraction.
- `holographic-glitch`: scanline glitch — yours is geometric voronoi shards.

## OUTPUT CONTRACT
1. After closing ```: empty.
2. Use the exact 13-binding header below.
3. Include a full Standard Hybrid Header with Category `visual-effects`.
4. Use at least three tactics: voronoi F2-F1 edges, bass_env, hue_preserve_clamp + ACES + IGN dither.
5. Alpha preserves the source alpha except at shard edges where glint raises it; premultiplied write.

## IMMUTABLE 13-BINDING CONTRACT (copy EXACTLY)
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};
```

## CANONICAL MINIMAL SKELETON
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  audio-reactive-prism-shatter
//  Category: visual-effects
//  Features: audio-reactive, voronoi-shatter, prismatic-refraction, mouse-driven, thin-film
//  Complexity: Medium
//  Chunks From: voronoi, bass_env, hue_preserve_clamp, aces, ign
//  Created: 2026-07-18
//  By: Kimi Code CLI (weekly swarm)
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(pixel) / res;
    // TODO: implement prism shatter
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    textureStore(writeTexture, pixel, src);
}
```

## ROLE TOOLKIT — Algorithmist + Visualist + Interactivist
- Voronoi (3×3 neighborhood): F1 cell id (hash → shard seed), F2-F1 for edges. Scale cells with p1.
- Epicenter: `mix(vec2<f32>(0.5), u.zoom_config.yz, clamp(u.zoom_config.w + 0.3, 0.0, 1.0))` (mouse when down, biased center otherwise).
- Shard displacement: direction from epicenter to cell center, magnitude = `bass_env_val * p2 * hash01(cell_id)` — outward, per-shard variance.
- Prism refraction: sample r at `uv + disp * (1.0 + mids * p3)`, g at `uv + disp`, b at `uv + disp * (1.0 - mids * p3)` — clamp all UVs 0..1.
- Thin-film facet tint: `0.5 + 0.5 * cos(2π * (hash01(cell_id) + disp_mag * 4.0 + vec3(0.0, 0.33, 0.67)))`, mixed in at 15–25%.
- Treble glint: `edge = 1.0 - smoothstep(0.0, 0.05, F2-F1)`; add `edge * treble * p4` white sparkle, IGN-gated.
- Alpha: `mix(src.a, 1.0, edge * treble)`; premultiplied write `vec4(col * alpha, alpha)`.
- Depth: pass through readDepthTexture.
- Params: p1 = shard scale, p2 = shatter force, p3 = refraction width, p4 = glint intensity.

## 12 KIMI GRAPHICAL TACTICS
```wgsl
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i+vec2(1,0)), u.x),
               mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s=0.0; var a=0.5; var f=1.0;
    for (var i=0;i<oct;i++) { s+=a*valueNoise(p*f); f*=2.0; a*=0.5; }
    return s;
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
```

## LINE BUDGET & FINAL REMINDER
Target: 140–170 lines. One WGSL code block, nothing after the closing fence.
