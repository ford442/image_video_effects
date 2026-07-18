# KIMI SWARM TASK — CREATION — gen-audio-reactive-tide-pools

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
Create a new generative shader: `gen-audio-reactive-tide-pools`.

Visual concept: a dark basalt shore scattered with glowing tide pools (voronoi cells with rounded, smin-blended rims). Inside each pool, concentric cymatic ripple rings expand from the cell center — ring amplitude pulses with **bass** (use `bass_env` envelope). **Mids** drift the caustic hue of the water from deep teal → emerald → gold. **Treble** sprinkles sharp foam sparkle along pool rims and ring crests. Mouse position acts as a dropped pebble: an extra expanding ripple source at `zoom_config.yz` while `zoom_config.w` (mouse_down) is held. Depth texture fades distant pools into a wet-haze. The pools should feel like a resonating tide flat at night — water as a living drum skin, NOT a hex mandala and NOT a fern.

## DIFFERENTIATE FROM
- `gen-cymatic-hex-mandala`: hexagonal standing-wave mandala — yours is organic voronoi pools.
- `gen-cymatic-bloom-fronds`: fern + rim — yours is water ripple rings.
- `rain-ripples`: rain-on-surface — yours is discrete resonating pools with bass envelopes.

## OUTPUT CONTRACT
1. After closing ```: empty.
2. Use the exact 13-binding header below.
3. Include a full Standard Hybrid Header with Category `generative`.
4. Use at least three tactics: voronoi/smin, bass_env + hue_preserve_clamp + ACES + IGN dither.
5. Alpha encodes water depth / foam contribution (basalt rock between pools stays low-alpha), premultiplied write.

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
//  gen-audio-reactive-tide-pools
//  Category: generative
//  Features: audio-reactive, cymatic-ripples, voronoi-pools, mouse-driven, depth-aware
//  Complexity: Medium
//  Chunks From: voronoi, smin, bass_env, hue_preserve_clamp, aces, ign
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
    // TODO: implement tide pools
    textureStore(writeTexture, pixel, vec4<f32>(0.0));
}
```

## ROLE TOOLKIT — Algorithmist + Visualist + Interactivist
- Voronoi (F1/F2, 3×3 neighborhood) for pool shapes; pool interior = `smoothstep` on F1 with per-cell hash radius; use `smin` to blend neighboring pool rims organically.
- Ripple rings per pool: `sin(dist_to_center * freq - time * speed) * exp(-dist_to_center * decay)`, amplitude scaled by `bass_env`.
- Mouse pebble: extra ring source at `zoom_config.yz`, amplitude gated by `zoom_config.w`, same ring equation.
- Bass = ring amplitude + pool glow. Mids = caustic hue (teal→emerald→gold ramp). Treble = foam sparkle on rims and ring crests (IGN-thresholded).
- Depth haze: fade far pools toward dark blue-grey using readDepthTexture sample.
- Params: p1 = pool scale, p2 = ring frequency, p3 = bass sensitivity, p4 = foam amount.
- Final alpha = water mask (pool interior + ripple energy + foam), rock = ~0.15 alpha; premultiplied write.
- Depth write: pool depth field (deeper pools darker).

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
Target: 150–180 lines. One WGSL code block, nothing after the closing fence.
