# Swarm Brief: heat-haze-mirage

**Role:** Algorithmist
**Name:** Heat Haze Mirage
**Category:** image
**Description:** Vertical heat shimmer driven by a rising hot-air column. Time-varying noise is advected upward, displacing the UV sample with chromatic separation. Bass injects fresh heat bursts; mouse creates a heat source.
**Current lines:** 119
**Target lines:** 169–209 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This mirage reads its 'audio' from extraBuffer[0..2] - the RESERVED zone ([0..4] reserved; the FFT bands live in plasmaBuffer and extraBuffer[5..132]) - so bass/mid/treble are reading reserved zeros and the whole audio-reactive feature tag is dead. Fix the plumbing, then make the heat rise:
- FIX THE AUDIO SOURCE (priority 1): replace `extraBuffer[0]/[1]/[2]` with `plasmaBuffer[0].x/.y/.z` (real bass/mid/treble) - the heatIntensity bass boost (x2.0!), the mid glow, and the dataTextureB.w stored bass all become live. This is the only extraBuffer access in the file; after the fix the shader touches NO reserved state.
- Spring-damper the heat source + aspect fix: ease the mouse with a critically-damped spring (extraBuffer[133..136] - the FIRST extraBuffer state this shader may write, [0..4] reserved, [5..132] = engine FFT) so the hot spot drifts like a real thermal; raw mouse stays the spring target. Aspect-correct mDist (currently elliptical) so the heat column is circular.
- Click heat bursts + per-band FFT: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying heat bloom at its click point (heatFactor += exp(-age * 1.5) * aspect-corrected ~0.2 falloff, ~2s - no mouseDown needed), so clicks pop mirages. Modulate the wavy displacement per 8 vertical bands (`plasmaBuffer[(band % 8u) + 1u].x * 0.3` on disp amplitude), so the shimmer varies across the spectrum. Fix the stale comment (comment-only): config.y = ripple COUNT.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash/vnoise/fbm2 helpers, the risingUV advection, the heatBase column, the vertical-bias heatDisp, the chromatic r/g/b tap structure, the warm tint, the glow, the hazeAcc 0.85 accumulation (A write / C read contract - keep the mix form), and the dataTextureB packing (heatDisp, heatFactor, bass) VERBATIM. All 4 slider ids/names/defaults EXACTLY. extraBuffer writes in [133..255] ONLY (reads: none after the fix).

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "heat-haze-mirage",
  "name": "Heat Haze Mirage",
  "url": "shaders/heat-haze-mirage.wgsl",
  "category": "image",
  "description": "Vertical heat shimmer driven by a rising hot-air column. Time-varying noise is advected upward, displacing the UV sample with chromatic separation. Bass injects fresh heat bursts; mouse creates a heat source.",
  "tags": [
    "heat",
    "haze",
    "mirage",
    "distortion",
    "atmospheric",
    "audio-reactive",
    "mouse-driven"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "temporal",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "heat_intensity",
      "name": "Heat Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "rise_speed",
      "name": "Rise Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "wavy_scale",
      "name": "Wave Scale",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "chroma_shift",
      "name": "Chroma Shift",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Heat Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Rise Speed",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Wave Scale",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chroma Shift",
      "default": 0.4,
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
//  Heat Haze Mirage
//  Category: image
//  Features: audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
//  Vertical heat shimmer driven by a rising hot-air column. A
//  time-varying noise field is advected upward, displacing the UV
//  sample. Temporal feedback (dataTextureC) stores the accumulated
//  heat state and slowly cools. Bass injects fresh heat bursts.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=HeatIntensity, y=RiseSpeed, z=WavyScale, w=ChromaShift
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                       hash(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    ) * 2.0 - 1.0;
}

fn fbm2(p: vec2<f32>) -> vec2<f32> {
    let n1 = vnoise(p);
    let n2 = vnoise(p + vec2<f32>(5.2, 1.3));
    return vec2<f32>(n1, n2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio
    let bass   = extraBuffer[0];
    let mid    = extraBuffer[1];
    let treble = extraBuffer[2];

    // Params
    let heatIntensity = mix(0.0, 0.025, u.zoom_params.x) * (1.0 + bass * 2.0);
    let riseSpeed     = mix(0.1, 1.5,   u.zoom_params.y);
    let wavyScale     = mix(2.0, 12.0,  u.zoom_params.z);
    let chromaShift   = mix(0.0, 0.008, u.zoom_params.w);

    // Heat column: stronger at bottom of screen (y~0), rises upward
    let heatBase  = smoothstep(1.0, 0.0, uv.y) * 0.5 + 0.5; // more heat at bottom
    // Also mouse can be a heat source
    let mouse     = u.zoom_config.yz;
    let mDist     = length(uv - mouse);
    let mouseHeat = smoothstep(0.25, 0.0, mDist) * u.zoom_config.w;

    let heatFactor = heatBase + mouseHeat;

    // Rising displacement field
    let risingUV  = vec2<f32>(uv.x * wavyScale, uv.y * wavyScale - time * riseSpeed);
    let disp      = fbm2(risingUV) * heatIntensity * heatFactor;

    // Vertical bias: haze mostly shifts horizontally (shimmer), slight vertical
    let heatDisp  = vec2<f32>(disp.x, disp.y * 0.3);

    // Chromatic shift: red slightly ahead, blue slightly behind (mirage)
    let rUV = clamp(uv + heatDisp + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + heatDisp,                                vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + heatDisp - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Atmospheric haze: slight brightness boost + warm tint at heat zones
    let warmTint   = vec3<f32>(1.04, 1.01, 0.97) * (1.0 + heatFactor * 0.1);
    var col        = vec3<f32>(r, g, b) * warmTint;

    // Heat shimmer glow (subtle)
    let glowMask   = heatFactor * heatIntensity * 50.0;
    col += vec3<f32>(0.05, 0.03, 0.01) * glowMask * (1.0 + mid);

    // Temporal accumulate haze state
    let prev     = textureLoad(dataTextureC, coord, 0);
    let hazeAcc  = mix(vec4<f32>(col, a), prev, 0.85);

    let outColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.3)), a);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(heatFactor, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, hazeAcc);
    textureStore(dataTextureB, coord, vec4<f32>(heatDisp, heatFactor, bass));
}
```
