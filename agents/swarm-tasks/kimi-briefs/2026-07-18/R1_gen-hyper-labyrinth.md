# KIMI SWARM TASK — REPAIR — gen-hyper-labyrinth

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This shader raymarches a 4D gyroid labyrinth with neon cyan/magenta veins and a cyber rim. It has a **stub header marker** (`// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---`) that must be removed, zero audio reactivity, and a hard-coded `alpha = 1.0` final write. Upgrade it so the labyrinth **breathes with music**: bass surges the 4D rotation speed and glow pulse, mids slide the neon vein balance between cyan and magenta, treble adds sparkle to the fresnel rim. Preserve the gyroid SDF, the spherical mouse-orbit camera with organic drift, and the dark metallic wall material. The final alpha should fade with ray distance/fog so deep void regions composite loosely in slot 2/3.

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `gen-hyperbolic-tessellation`: angular tessellation — yours is a smooth gyroid maze.
- `gen-mandelbox-explorer`: box-fold fractal — yours keeps the 4D gyroid soul.

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. Alpha must carry semantic meaning (hit confidence / fog transmittance).
4. Use at least two tactics from the 12 Kimi Graphical Tactics (bass_env + ACES + IGN dither recommended).
5. Include a modern Standard Hybrid Header with accurate Category / Features / Chunks From.
6. NO stub header marker line anywhere.

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

## CURRENT SOURCE (preserve its soul while upgrading)
```wgsl
// ═══════════════════════════════════════════════════════════════
// Hyper Labyrinth - 4D Maze Visualization
// Category: generative
// Features: 4D geometry, raymarching, neon aesthetics
// ═══════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data

// ---------------------------------------------------
struct Uniforms {
    config: vec4<f32>, // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>, // x=Param1 (scale), y=Param2 (morph speed), z=Param3 (glow), w=Param4 (thickness)
    ripples: array<vec4<f32>, 50>,
};

// 4D Rotation in XW plane
fn rotate4D(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        p.x * c - p.w * s,
        p.y,
        p.z,
        p.x * s + p.w * c
    );
}

// Map function (SDF) - merged best of both
fn map(pos3: vec3<f32>) -> vec2<f32> {
    var p4 = vec4<f32>(pos3, 1.0);
    var speed = mix(0.1, 2.0, u.zoom_params.y);
    var time = u.config.x * speed;
    p4 = rotate4D(p4, time);
    var rotYZ = u.config.x * 0.1;
    var cy = cos(rotYZ);
    var sy = sin(rotYZ);
    var tempY = p4.y * cy - p4.z * sy;
    var tempZ = p4.y * sy + p4.z * cy;
    p4.y = tempY;
    p4.z = tempZ;
    var scale = mix(1.0, 5.0, u.zoom_params.x);
    var q = p4 * scale;
    let val = sin(q.x) * cos(q.y) + sin(q.y) * cos(q.z) + sin(q.z) * cos(q.w) + sin(q.w) * cos(q.x);
    let thickness = mix(0.1, 1.2, u.zoom_params.w);
    let d = (abs(val) - thickness * 0.5) / scale;
    return vec2<f32>(d * 0.5, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var m = 0.0;
    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        if (d < 0.001 || t > 50.0) {
            if (d < 0.001) { m = res.y; }
            break;
        }
        t += d;
    }
    return vec2<f32>(t, m);
}
// (main: spherical mouse-orbit camera + drift, raymarch, dark metallic walls,
//  neon cyan/magenta gyroid veins, fresnel cyber rim, exp fog, hard alpha=1.0,
//  depth write t/50 — see repo file public/shaders/gen-hyper-labyrinth.wgsl)
```

## ROLE TOOLKIT — Algorithmist + Visualist
- Add `bass`, `mids`, `treble` reads from `plasmaBuffer[0]`; smooth bass with `bass_env` via dataTextureC feedback or a simple attack curve.
- Bass: boost 4D rotation speed and vein glow pulse amplitude.
- Mids: mix vein color between cyan (0.0) and magenta (1.0).
- Treble: additive sparkle on the fresnel rim term.
- Semantic alpha: `alpha = 1.0 - exp(-t * 0.10)` on hit (near walls opaque, far fog translucent), low alpha in void miss regions; premultiplied write `vec4(color * alpha, alpha)`.
- Route final color through `hue_preserve_clamp` + `aces` + `ign` dither.
- Keep depth write `t / 50.0`.

## 12 KIMI GRAPHICAL TACTICS (apply where appropriate)
```wgsl
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
Use depth-aware fog, anti-moiré LOD, polar kaleidoscope fold, and hex bokeh taps as needed.

## LINE BUDGET & FINAL REMINDER
Target: ≤ 220 lines. Preserve the 4D gyroid labyrinth character; do not turn it into a generic fractal.

Stop the moment the WGSL fence closes. Nothing after it.
