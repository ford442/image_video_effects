# KIMI SWARM TASK — REPAIR — rainbow-vector-field

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This shader is **PASS 1 of 2** in a multipass pair: it generates a psychedelic polar rainbow pattern on `writeTexture` and a displacement-strength field on `writeDepthTexture`, which `prismatic-feedback-loop.wgsl` (Pass 2) consumes. **The Pass-2 contract is sacred: keep the displacement write to `writeDepthTexture` semantically identical (brightness × displacementScale + mouse wave).** The current file is a mess: TWO duplicate `custom_custom_mod`/`custom_custom_custom_mod` functions, a banned stub header marker, a buggy mouse mapping (`zoom_config.yz` is already normalized mouse UV — the code wrongly divides by resolution again), zero audio reactivity, and no tone mapping. Clean all of this up. Then make the rainbow **spin with music**: bass drives hue-rotation speed, mids drive saturation, treble amplifies the mouse-wave interference ripple. Final writeTexture alpha should encode normalized displacement magnitude (meaningful for downstream compositing), premultiplied.

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `audio-reactive-rgb-dispersion`: plain channel split — yours is a polar rainbow field generator.
- `hypnotic-spiral`: spiral bands — yours is an angle/distance hue wheel with mouse-wave interference.

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. **Preserve the Pass-1→Pass-2 contract**: `writeDepthTexture` receives `displacement` exactly as before (brightness * scale + mouseWave term), `vec4(displacement, 0.0, 0.0, 0.0)`.
4. Alpha must carry semantic meaning (normalized displacement magnitude), premultiplied write.
5. Use at least two tactics from the 12 Kimi Graphical Tactics (ACES + IGN dither recommended).
6. Include a modern Standard Hybrid Header with accurate Category / Features / Chunks From — and a `PASS 1 of 2` note naming `prismatic-feedback-loop.wgsl` as the consumer.
7. NO duplicate mod functions. NO stub header marker.

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
fn custom_custom_mod(x: f32, y: f32) -> f32 { return x - y * floor(x / y); }
fn custom_custom_custom_mod(x: f32, y: f32) -> f32 { return x - y * floor(x / y); }  // DUPLICATE — delete

// (stub header marker + 13 bindings — replace with modern header)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y); // BUG: yz already normalized
    let clickIntensity = u.zoom_config.x;

    var center = vec2<f32>(0.5, 0.5);
    let delta = uv - center;
    let angle = atan2(delta.y, delta.x);
    let dist = length(delta);

    let mouseDist = length(uv - mousePos);
    let mouseWave = sin(mouseDist * u.zoom_params.x - time * 4.0) * clickIntensity * 0.5;

    let hue = (angle + dist * u.zoom_params.x * 2.0 + time * 0.5 + mouseWave) / (2.0 * 3.14159);
    let hueFract = fract(hue);

    let h = hueFract * 6.0;
    let c = u.zoom_params.z; // brightness
    let x = c * (1.0 - abs(custom_custom_mod(h, 2.0) - 1.0));
    var rainbow = vec3<f32>(0.0);
    if (h < 1.0) { rainbow = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rainbow = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rainbow = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rainbow = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rainbow = vec3<f32>(x, 0.0, c); }
    else { rainbow = vec3<f32>(c, 0.0, x); }

    let saturation = mix(0.3, 1.0, u.zoom_params.y);
    rainbow = mix(vec3<f32>(length(rainbow)), rainbow, saturation);

    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(rainbow, 1.0));

    let brightness = dot(rainbow, vec3<f32>(0.299, 0.587, 0.114));
    let displacement = brightness * u.zoom_params.w + mouseWave * 2.0;
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(displacement, 0.0, 0.0, 0.0));
}
```

## ROLE TOOLKIT — Visualist + Interactivist
- Fix mouse: `let mousePos = u.zoom_config.yz;` (already normalized UV).
- Add `bass`, `mids`, `treble` reads from `plasmaBuffer[0]`.
- Bass: hue-rotation speed — `time * 0.5` becomes `time * (0.5 + bass * 1.5)`.
- Mids: `saturation = mix(0.3, 1.0, clamp(u.zoom_params.y + mids * 0.3, 0.0, 1.0))`.
- Treble: `mouseWave` amplitude `* (1.0 + treble * 2.0)`.
- Replace the if/else hue chain with a branchless HSV→RGB (`fract`-based), keeping identical visual output.
- Keep `clickIntensity = u.zoom_config.w` (mouse_down) per the canonical struct — map it the same way the old code used `zoom_config.x`.
- Alpha: `alpha = clamp(abs(displacement) * 0.5 + 0.35, 0.0, 1.0)`; premultiplied write `vec4(rainbow * alpha, alpha)`.
- Route rainbow through `hue_preserve_clamp` + `aces` + `ign` dither before the write. **Compute `brightness`/`displacement` from the PRE-tone-mapped rainbow so the Pass-2 field stays stable.**

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
Target: ≤ 130 lines. Preserve the polar rainbow + displacement-field generator character and the Pass-2 contract.

Stop the moment the WGSL fence closes. Nothing after it.
