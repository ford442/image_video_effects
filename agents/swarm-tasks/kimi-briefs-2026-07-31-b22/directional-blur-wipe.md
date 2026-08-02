# Swarm Brief: directional-blur-wipe

**Role:** Algorithmist
**Name:** Directional Blur Wipe
**Category:** image
**Description:** Splits the screen with an audio-reactive directional blur. Mouse controls split position; chromatic offset scatters RGB per treble. Depth-scatter increases blur radius on distant objects.
**Current lines:** 110
**Target lines:** 160–200 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. The description says 'Mouse controls split position' and there's a 'Split Pos' slider - but split_pos_param is read and NEVER USED: the wipe line is nailed to the cursor and the slider is a lie. There's also a dead `chroma` var computed per loop iteration. Wire what you sell:
- WIRE THE DEAD SLIDER (priority 1): offset the wipe line along its own normal by the slider (`p_line = mouse + normal * (split_pos_param - 0.5) * 0.6`, aspect-consistent) - default 0.5 = line exactly on the cursor, bit-identical to today. Also use the dead `chroma` inside the blur loop (per-channel taps: accumulate r from sampleUV + dir * chroma and b from sampleUV - dir * chroma) so the per-sample chromatic offset actually disperses.
- Spring-damper the wipe: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the split line sweeps with weight; raw mouse stays the spring target (the (mouse.y - 0.5) * 3.14 angle lean rides the SPRUNG y).
- Click wipe flashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple brightens the wipe line vicinity briefly (decaying line glow boost, ~1.0s) and kicks the blur strength locally, so clicks flash the transition. Fix the stale header ('Category: post-processing' -> image, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the bass_env helper, the angle/dir/normal construction, the dist < 0 branch split, the num_samples loop structure, the per-channel 1.1/0.9 dispersion taps, and the line_width glow VERBATIM. Sliders honestly wired except the dead split_pos - keep ids/names/defaults EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "directional-blur-wipe",
  "name": "Directional Blur Wipe",
  "category": "image",
  "description": "Splits the screen with an audio-reactive directional blur. Mouse controls split position; chromatic offset scatters RGB per treble. Depth-scatter increases blur radius on distant objects.",
  "url": "shaders/directional-blur-wipe.wgsl",
  "params": [
    {
      "name": "Split Pos",
      "id": "split_pos",
      "min": 0,
      "max": 1,
      "step": 0.01,
      "default": 0.5
    },
    {
      "name": "Angle",
      "id": "angle",
      "min": 0,
      "max": 1,
      "step": 0.01,
      "default": 0
    },
    {
      "name": "Strength",
      "id": "strength",
      "min": 0,
      "max": 1,
      "step": 0.01,
      "default": 0.5
    },
    {
      "name": "Samples",
      "id": "samples",
      "min": 0,
      "max": 1,
      "step": 0.01,
      "default": 0.5
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "upgraded-rgba",
    "chromatic-offset"
  ],
  "tags": [
    "blur",
    "wipe",
    "directional",
    "audio-reactive",
    "depth-aware",
    "chromatic"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Split Pos",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Angle",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Samples",
      "default": 0.5,
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
//  Directional Blur Wipe
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, blur-wipe, depth-scatter, chromatic-offset, upgraded-rgba
//  Complexity: High
//  Chunks From: directional-blur-wipe, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScatter = mix(0.7, 1.3, depth);

    let split_pos_param = u.zoom_params.x;
    let angle_param = u.zoom_params.y;
    let strength_param = u.zoom_params.z * bass_env(bass, mids);
    let samples_param = u.zoom_params.w;

    let angle = angle_param * 6.28 + (mouse.y - 0.5) * 3.14;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let normal = vec2<f32>(-dir.y, dir.x);

    let p_line = mouse;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let p_line_aspect = vec2<f32>(p_line.x * aspect, p_line.y);
    let dist = dot(uv_aspect - p_line_aspect, normal);

    var color = vec4<f32>(0.0);
    if (dist < 0.0) {
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        let num_samples = i32(samples_param * 50.0) + 5;
        let strength = strength_param * 0.05 * depthScatter;

        var accum = vec3<f32>(0.0);
        var weight = 0.0;

        // Chromatic offset: R and B sample at slightly different offsets per sample
        for (var i = 0; i < num_samples; i = i + 1) {
            let t = f32(i) / f32(num_samples - 1);
            let offset = dir * t * strength;
            let chroma = treble * 0.01 * t;

            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
            accum = accum + sampleColor.rgb;
            weight = weight + 1.0;
        }
        let blurRGB = accum / weight;

        // Per-channel blur for chromatic dispersion
        let rUV = clamp(uv + dir * strength * 1.1, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(uv - dir * strength * 0.9, vec2<f32>(0.0), vec2<f32>(1.0));
        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

        color = vec4<f32>(mix(blurRGB.r, r, 0.3), blurRGB.g, mix(blurRGB.b, b, 0.3), 1.0);

        // Bass drives blur-side brightness pulse
        color = color + vec4<f32>(bass * 0.1 * (dist * 0.5 + 0.5), bass * 0.05, 0.0, 0.0);

        let line_width = 0.005;
        if (dist < line_width) {
             color = color + vec4<f32>(0.2 + mids * 0.1, 0.15 + treble * 0.1, 0.1, 0.0);
        }
    }

    let alpha = color.a;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color.rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
