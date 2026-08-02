# Swarm Brief: magnetic-luma-sort

**Role:** Algorithmist
**Name:** Magnetic Luma Sort
**Category:** interactive-mouse
**Description:** Pixels are magnetically pulled by the cursor based on brightness, creating trails.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This luma-flow feedback has a corpse in the code: `finalColor` is computed two different ways and then THROWN AWAY (`mixed` is what actually gets stored) - and the audio uniform is declared but never sampled. Clean up, then wire it:
- REMOVE THE DEAD finalColor (priority 1): the `finalColor = mix(...)` then `finalColor = max(...)` lines compute a value nothing reads - delete them (the dev commentary explaining the approach STAYS - it is this file's personality, comments verbatim). No behavior change: `mixed` already wins.
- Spring-damper the attractor + click vortex pulses: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the magnet glides; raw mouse stays the spring target. Loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying second attractor at its click point (speed contribution from a smoothstep falloff ~0.25 radius, exp(-rippleAge * 2.0)), so clicks stir the flow; compose with the main pull before the offset.
- Wire the dead audio: bass lowers the effective luma threshold (threshold * (1.0 - bass * 0.3), so beats loosen the sort) and per-row FFT drift - 8 horizontal bands each scale their speed by `plasmaBuffer[(band % 8u) + 1u].x * 0.4`, so the smear dances across the spectrum.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the feedback contract is SACRED - dataTextureC is read as history at the upstream offset, dataTextureA is written with `mixed` (history feedback AND display color, same value) - keep this exactly, never tonemap the A write. Preserve ALL the dev thinking-out-loud comments VERBATIM (file personality, same as b21 interactive-emboss/mouse-gravity), the get_luma helper, the threshold speed gate, the aspect correction, and the attract/repel step VERBATIM. All 4 slider ids/names/defaults/ranges EXACTLY (Trail Decay range 0.5-0.99!). extraBuffer in [133..255] ONLY.

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
  "id": "magnetic-luma-sort",
  "name": "Magnetic Luma Sort",
  "url": "shaders/magnetic-luma-sort.wgsl",
  "description": "Pixels are magnetically pulled by the cursor based on brightness, creating trails.",
  "params": [
    {
      "id": "pullStrength",
      "name": "Pull Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "threshold",
      "name": "Luma Threshold",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "trailDecay",
      "name": "Trail Decay",
      "default": 0.9,
      "min": 0.5,
      "max": 0.99
    },
    {
      "id": "mode",
      "name": "Attract/Repel",
      "default": 0,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Pull Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Luma Threshold",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Trail Decay",
      "default": 0.9,
      "min": 0.5,
      "max": 0.99,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Attract/Repel",
      "default": 0,
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
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn get_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let pullStrength = u.zoom_params.x * 0.05; // Scaling for reasonable speed
    let threshold = u.zoom_params.y;
    let decay = u.zoom_params.z;
    let repel = step(0.5, u.zoom_params.w); // 0 or 1

    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Vector to mouse
    var dirToMouse = mousePos - uv;
    dirToMouse.x *= aspect;
    let dist = length(dirToMouse);

    var dir = normalize(dirToMouse);
    if (dist < 0.001) { dir = vec2(0.0, 0.0); }

    if (repel > 0.5) {
        dir = -dir;
    }

    // Read current image source
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(srcColor.rgb);

    // Read history (trail)
    // We want to sample the history from "upstream".
    // If pixels move towards mouse, we (at current pixel) look AWAY from mouse to see what's coming.
    // Movement speed depends on luma. Brighter = faster.

    var speed = 0.0;
    if (luma > threshold) {
        speed = pullStrength * (luma - threshold) / (1.0 - threshold + 0.001);
    }

    // Dampen speed by distance? Maybe infinite reach is better.
    // Let's dampen slightly so the edge of screen doesn't pull too hard if mouse is center.
    // speed *= smoothstep(0.0, 0.1, dist);

    let offset = -dir * speed;

    // Sample history at the upstream position
    let historyUV = uv + offset;
    var historyColor = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

    // Combine
    // If we are just moving the image, we should primarily see the history moving.
    // But we need to inject the new frame's content otherwise it fades out or is empty initially.
    // A common "trail" technique is max(current, history * decay).

    // Let's try a blend:
    // The "moved" content is history. The "source" is the current video frame.
    // If we only use history, the video won't update.
    // So we mix current frame into history.

    var finalColor = mix(historyColor, srcColor, 0.1); // Continually add 10% new image

    // To make it look like "sorting" or "smearing", we heavily favor the displaced history
    // but we clamp it so it doesn't blow out.
    finalColor = max(srcColor * 0.2, historyColor * decay);

    // Alternative: If the pixel is bright enough to move, it "leaves" its spot and "arrives" at the next.
    // This is hard in a gather-based shader.
    // Gather approach: I am pixel P. Who arrived here?
    // The pixel at P + offset (away from mouse) arrived here if it was moving towards mouse.

    // Let's stick to the feedback loop approach.
    // New Value = (Old Value at Upstream P) * Decay + (Current Input) * Blend

    let mixed = mix(srcColor, historyColor, decay);

    // If luma is low, we don't move history much?
    // Actually, if luma is low (speed 0), offset is 0. So we sample history at current UV.
    // This results in a standard feedback trail.

    textureStore(writeTexture, vec2<i32>(global_id.xy), mixed);
    textureStore(dataTextureA, global_id.xy, mixed); // Write to history

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
```
