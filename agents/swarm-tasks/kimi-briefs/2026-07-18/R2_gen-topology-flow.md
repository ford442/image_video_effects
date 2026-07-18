# KIMI SWARM TASK — REPAIR — gen-topology-flow

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This shader visualizes a Morse-theory height field: FBM terrain with ridge/saddle features, gradient-flow streamlines (integrated per-pixel over up to 300 seed particles × 20 steps — expensive!), critical-point highlighting (peaks/valleys/saddles), contour lines, and feedback trails. It has zero audio reactivity and a hard `alpha = 1.0` write. Upgrade it so the terrain **flows with music**: bass accelerates the flow (use `bass_env` for attack/release), mids warm the valley→peak palette, treble makes critical points glint. Add a performance guard: early-exit the particle loop once `flowAccum` saturates (e.g. > 4.0), and cap effective particle density on small resolutions. Preserve the height-field function, streamline integration model, and contour rendering. Final alpha should encode flow intensity + critical-point highlight so calm regions stay translucent.

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `gen-strange-field-flow`: attractor-based flow — yours is Morse-theory terrain flow.
- `gen-magnetic-field-lines`: dipole tracing — yours is gradient streamlines on FBM terrain.

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. Alpha must carry semantic meaning (flow intensity / critical highlight).
4. Use at least two tactics from the 12 Kimi Graphical Tactics (bass_env + ACES + IGN dither recommended).
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
Full file: `public/shaders/gen-topology-flow.wgsl` (202 lines). Key structure:
- `hash21` / `noise` / `fbm(p, octaves)` value-noise stack.
- `heightField(p, complexity, t)`: FBM + ridge sin/cos features + saddle term `(p.x²-p.y²)`.
- `gradient(p, ...)`: central-difference eps=0.01.
- `detectCritical(grad, laplacian)`: 0=none, 1=peak, 2=valley, 3=saddle.
- `heightColor(h)`: valley blue (0.1,0.3,0.8) → mid green (0.2,0.6,0.3) → peak red (0.9,0.2,0.1).
- `main`: params flowSpeed/complexity/particleDensity/trailPersistence from zoom_params; per-pixel loop over `numParticles` seeds, each advected 20 gradient steps accumulating `flowAccum` when within 0.03 of pixel; flow colored by direction; critical-point tinting; contour darkening `abs(fract(h*10)-0.5)`; feedback `col*0.3 + prev*trailPersistence` via dataTextureC→A; hard alpha 1.0; depth write `h*0.5+0.5`.

## ROLE TOOLKIT — Algorithmist + Optimizer
- Add `bass`, `mids`, `treble` reads from `plasmaBuffer[0]`; `bass_env` envelope for flowSpeed (fast attack, slow release).
- Mids: warm the `heightColor` ramp (shift mid color toward amber when mids are high).
- Treble: white glint added at critical points (`critical != 0`).
- Optimizer: `break` out of the particle loop when `flowAccum > 4.0`; scale `numParticles` down when `resolution.x * resolution.y < 1_000_000`.
- Semantic alpha: `alpha = clamp(0.35 + flowIntensity * 0.5 + criticalBoost, 0.0, 1.0)`; premultiplied write `vec4(col * alpha, alpha)`; keep feedback store alpha at 1.0 for the trail buffer.
- Route final color through `hue_preserve_clamp` + `aces` + `ign` dither BEFORE the feedback mix, so trails stay tone-mapped.

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
Target: ≤ 220 lines. Preserve the Morse-theory flow character; do not turn it into a generic noise field.

Stop the moment the WGSL fence closes. Nothing after it.
