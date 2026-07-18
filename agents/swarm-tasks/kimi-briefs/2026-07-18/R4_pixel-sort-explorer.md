# KIMI SWARM TASK — REPAIR — pixel-sort-explorer

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This is an **input-driven** interactive pixel-sort effect: inside a mouse-centered mask it scans a row/column of source samples, finds the brightest sample above a threshold, and pulls it into the current pixel — a classic pixel-sort smear. It has zero audio reactivity and no tone mapping. Upgrade it so the sort **dances with music**: bass pulses the mask radius, mids modulate the luma threshold (lower threshold on heavy mids = more sorting), treble adds a subtle chromatic fringe along the sort direction (offset R/B samples by ±1 stride). **Preserve the input-driven sampling chain exactly** — audio modulates, never replaces, the source image. Keep the `origAlpha` preservation and bounds-checked sampling. Convert the `if (direction > 0.5)` branch to branchless `select()`. Alpha stays the source alpha (that IS meaningful here); apply ACES + IGN to the rgb only.

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `pixel-sorter` / `luma-pixel-sort`: full-frame threshold sorts — yours is a mouse-local explorer mask.
- `pixel-stretch-interactive`: stretch smear — yours picks the brightest sample (sort behavior).

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. Alpha must carry semantic meaning (preserve source alpha; document why in the header).
4. Use at least two tactics from the 12 Kimi Graphical Tactics (ACES + IGN dither recommended).
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
```wgsl
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);

    let sortThreshold = clamp(u.zoom_params.x, 0.0, 1.0);
    let radius = clamp(u.zoom_params.y, 0.0, 1.0);
    let direction = clamp(u.zoom_params.z, 0.0, 1.0);
    let smoothness = clamp(u.zoom_params.w, 0.0, 1.0);

    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    let mask = 1.0 - smoothstep(radius, radius + 0.1, dist);

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let origAlpha = color.a;

    if (mask > 0.01) {
        var bestVal = -1.0;
        var bestColor = color;
        let samples = 10;
        let stride = mix(0.001, 0.05, smoothness);
        var dirVec = vec2(0.0, 1.0);
        if (direction > 0.5) { dirVec = vec2(1.0, 0.0); }

        for (var i = 1; i <= samples; i++) {
             let offset = f32(i) * stride * dirVec;
             let sUV = uv - offset;
             if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) { continue; }
             let sColor = textureSampleLevel(readTexture, u_sampler, sUV, 0.0);
             let lum = dot(sColor.rgb, vec3(0.299, 0.587, 0.114));
             if (lum > sortThreshold) {
                  if (lum > bestVal) { bestVal = lum; bestColor = sColor; }
             }
        }

        let myLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        if (bestVal > myLum) { color = mix(color, bestColor, mask); }
    }

    let outsideDim = mix(0.1, 1.0, mask);
    color = vec4(color.rgb * outsideDim, origAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
}
```
(Existing header comment claims Category `image` but the JSON def lives in `interactive-mouse` — use Category `interactive-mouse` in the new header.)

## ROLE TOOLKIT — Interactivist + Visualist
- Add `bass`, `mids`, `treble` reads from `plasmaBuffer[0]`.
- Bass: `radius *= 1.0 + bass * 0.5` (pulse the explorer mask).
- Mids: `sortThreshold *= 1.0 - mids * 0.4` (more sorting on heavy mids).
- Treble: chromatic fringe — when computing `bestColor`, also sample `sUV ± dirVec * stride` for R and B channels and mix by `treble * mask`.
- Branchless: `let dirVec = select(vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), direction > 0.5);`
- Keep `origAlpha` as the output alpha; apply `hue_preserve_clamp` + `aces` + `ign` dither to `.rgb` only.
- Soften `outsideDim` floor from 0.1 → 0.25 so the unmasked image stays readable.

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
Target: ≤ 140 lines. Preserve the mouse-local pixel-sort explorer character; do not turn it into a full-frame sorter.

Stop the moment the WGSL fence closes. Nothing after it.
