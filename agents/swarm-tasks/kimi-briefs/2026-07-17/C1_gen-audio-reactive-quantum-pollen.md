# KIMI SWARM TASK — CREATION — gen-audio-reactive-quantum-pollen

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
Create a new generative shader: `gen-audio-reactive-quantum-pollen`.

Visual concept: hundreds of tiny luminous pollen grains floating in a dark field. Bass makes them cluster into spiral/galaxy-like groups. Mids add harmonic orbital motion. Treble scatters them in sharp bursts. Mouse position attracts nearby grains when held down. Depth (readDepthTexture) makes foreground grains crisp and background grains fade into haze.

It must feel like a living spectrogram made of particles — not a particle system, but a procedural field where density and color react to audio in real time.

## DIFFERENTIATE FROM
- `gen-quantum-pollen`: existing pollen shader — yours must be more audio-reactive and cluster/disperse dramatically.
- `gen-nebula-light-trail-swarm`: trail-heavy — yours is grain/pollen density driven.

## OUTPUT CONTRACT
1. After closing ```: empty.
2. Use the exact 13-binding header below.
3. Include a full Standard Hybrid Header with Category `generative`.
4. Use at least three tactics: warpedFBM, hue_preserve_clamp + ACES + IGN dither, and audio-reactive envelope.
5. Alpha encodes particle density / contribution.

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
//  gen-audio-reactive-quantum-pollen
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, particle-field
//  Complexity: Medium
//  Chunks From: warpedFBM, hue_preserve_clamp, bass_env, ign
//  Created: 2026-07-17
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
    // TODO: implement quantum pollen particle field
    textureStore(writeTexture, pixel, vec4<f32>(0.0));
}
```

## ROLE TOOLKIT — Algorithmist + Visualist + Interactivist
- Use warpedFBM or domain warp to create a procedural density field.
- Spawn "grains" via a grid of hash seeds; animate their position with orbit equations.
- Bass = clustering strength. Mids = orbital speed / color hue shift. Treble = scatter burst.
- Mouse down = attractor at mouse_uv; mouse move = vortex.
- Depth = background haze, foreground crisp.
- Use hue_preserve_clamp + ACES + IGN dither.
- Final alpha = density * (1.0 - depth * 0.4), premultiplied writeback.

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
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p+vec2(0.0,t), 3), fbm(p+vec2(5.2,1.3), 3));
    return p + 0.25 * q;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
```

## LINE BUDGET & FINAL REMINDER
Target: 150–170 lines. Math density over commentary.

Stop the moment the WGSL fence closes. Nothing after it.
