# KIMI SWARM TASK — REPAIR — gen-mycelium-network

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This shader grows a diffusion-limited-aggregation-style mycelium network: 3 procedural roots wandering outward with noise-steered branching, earthy brown hyphae that darken with age, bioluminescent green pulsing tips, an FBM nutrient-field background, age rings, and persistent growth via feedback. It has zero audio reactivity and a hard `alpha = 1.0` write. Upgrade it so the fungus **feeds on music**: bass pulses the growth rate and tip bioluminescence (use `bass_env`), mids shift the nutrient field hue from umber toward teal, treble adds sharp sparkle bursts at the growing tips. Preserve the wandering-branch generator, segment-distance rendering, and the `max(col, prev * 0.98)` persistent-growth feedback. Final alpha should encode hyphae presence + tip glow so the dark nutrient background stays translucent for layer compositing.

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `gen-audio-reactive-mycelium-pulse` (Batch 15 creation): voronoi hyphae network — yours is DLA-style wandering branches; keep the branch-segment soul.
- `gen-cybernetic-mycelium-neural-web`: neon cyber aesthetic — yours stays earthy + bioluminescent.

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. Alpha must carry semantic meaning (hyphae mask + tip glow contribution).
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
Full file: `public/shaders/gen-mycelium-network.wgsl` (213 lines). Key structure:
- `hash21` / `noise` / `fbm` value-noise stack; `distToSegment(uv, a, b)`.
- `generateMycelium(uv, t, growthRate, branching, seed) -> vec4(dist, age, isTip, generation)`: 3 roots, up to `20 + branching*50` wandering segments each, noise-steered direction, probabilistic side branches.
- `main`: params growthRate/branching/nutrientDensity/biolumIntensity; animated seed per growth cycle; earthy hyphae ramp young (0.6,0.45,0.3) → old (0.25,0.15,0.1); tip glow `(0.2,0.9,0.4) * isTip * exp(-dist*30)`; FBM nutrient background; age rings `sin(ringDist*20)`; vignette; persistent feedback `max(col, prev*0.98)`; hard alpha 1.0; depth write `age*0.5`.

## ROLE TOOLKIT — Algorithmist + Visualist
- Add `bass`, `mids`, `treble` reads from `plasmaBuffer[0]`; `bass_env` envelope on growthRate (fast attack, slow release).
- Bass: also boost `biolumIntensity` tip pulse amplitude.
- Mids: shift nutrient background hue umber → teal (`mix` toward vec3(0.05,0.10,0.09)).
- Treble: sharp sparkle burst at tips — `tipGlow *= 1.0 + treble * 2.0 * step(0.7, isTip)` (branchless `select` ok).
- Semantic alpha: `alpha = clamp(hyphaeMask * 0.85 + tipGlow * 0.6 + nutrient * 0.15, 0.0, 1.0)`; premultiplied write `vec4(col * alpha, alpha)`; keep feedback store alpha 1.0.
- Route final color through `hue_preserve_clamp` + `aces` + `ign` dither BEFORE the persistent max() feedback so trails don't blow out.

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
Target: ≤ 230 lines. Preserve the wandering-branch mycelium character; do not turn it into a voronoi network.

Stop the moment the WGSL fence closes. Nothing after it.
