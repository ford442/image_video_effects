# KIMI SWARM TASK — REPAIR — heat-haze-mirage

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This is an **input-driven** heat-shimmer mirage: a rising FBM displacement field bends the source image vertically, with chromatic r/g/b splits, a bottom-weighted heat column, mouse-as-heat-source, warm-tint glow, and temporal feedback. **CRITICAL BUG TO FIX:** it reads audio from `extraBuffer[0..2]` — nothing in the renderer ever writes audio there, so its "audio-reactive" feature is dead code. Migrate audio to the canonical `plasmaBuffer[0]` reads. Then finish the job: bass injects heat bursts (already param-scaled — keep), mids drive the warm glow (keep), and ADD treble as a high-frequency micro-shimmer on the displacement. Replace the `clamp(col, 0, 1.3)` blow-out with `hue_preserve_clamp` + `aces` + `ign` dither. **Preserve the chromatic r/g/b sampling chain and the heat-column model exactly** — audio modulates, never replaces, the source image. Alpha stays the sampled source alpha (meaningful here).

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `heat-distortion`: simpler sine wobble — yours is an advected FBM heat column.
- `thermal-vision`: false-color palette — yours refracts the real image.

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. Alpha must carry semantic meaning (preserve source alpha; document why in the header).
4. Use at least two tactics from the 12 Kimi Graphical Tactics (hue_preserve_clamp + ACES + IGN dither required).
5. Include a modern Standard Hybrid Header with accurate Category / Features / Chunks From.

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
Full file: `public/shaders/heat-haze-mirage.wgsl` (119 lines). Key structure:
- `hash` / `vnoise` / `fbm2` (vec2 noise pair) helpers.
- `main`: **dead audio** `let bass = extraBuffer[0]; let mid = extraBuffer[1]; let treble = extraBuffer[2];` → replace with plasmaBuffer reads.
- Params: heatIntensity `mix(0.0,0.025,p.x)*(1.0+bass*2.0)`, riseSpeed, wavyScale, chromaShift.
- Heat column `smoothstep(1.0,0.0,uv.y)*0.5+0.5` + mouse heat `smoothstep(0.25,0.0,mDist)*mouse_down`.
- Rising displacement `fbm2(vec2(uv.x*wavy, uv.y*wavy - time*riseSpeed)) * heatIntensity * heatFactor`; vertical damped ×0.3.
- Chromatic samples: r/g/b at `uv + heatDisp ± vec2(chromaShift,0)` clamped 0..1; alpha from gUV sample.
- Warm tint + mids glow; temporal accumulate `mix(vec4(col,a), prev, 0.85)` → dataTextureA; heat state → dataTextureB; final `clamp(col, 0.0, 1.3)` ← REPLACE with hue_preserve_clamp + aces + ign.
- Depth write `vec4(heatFactor, 0,0,1)` — keep semantics.

## ROLE TOOLKIT — Visualist
- Replace dead audio: `let bass = plasmaBuffer[0].x; let mid = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;`
- Treble micro-shimmer: add `sin(uv.y * 240.0 + time * 30.0) * treble * 0.0015` to `heatDisp.x`.
- Keep bass heat-burst scaling and mids warm glow as-is (they were right, just unwired).
- Tone pipeline: `col = aces(hue_preserve_clamp(col, 1.0)) + (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;` — drop the 1.3 clamp entirely.
- Keep alpha from the gUV sample; keep both feedback stores; keep depth write.
- Update header Features to include `audio-reactive` (now actually true), `aces-tone-map`, `ign-dither`.

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
Target: ≤ 150 lines. Preserve the advected-heat-column mirage character; do not turn it into a generic wobble.

Stop the moment the WGSL fence closes. Nothing after it.
