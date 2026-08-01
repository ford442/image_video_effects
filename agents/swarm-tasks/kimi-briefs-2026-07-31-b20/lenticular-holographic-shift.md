# Swarm Brief: lenticular-holographic-shift

**Role:** Visualist
**Name:** Lenticular Holographic Shift
**Category:** image
**Description:** Simulates a lenticular/holographic print that dramatically shifts perspective, color, and moiré interference as you move the mouse or as audio beats. Stunning on portraits and detailed imagery.
**Current lines:** 105
**Target lines:** 155–195 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This lenticular print stores MASKS in dataTextureA (strip, moire, viewAngle, alpha) instead of display color - the A slot is for display, masks belong in B. Fix the plumbing, then give the view a glide:
- FIX THE A-SLOT ROLE (priority 1): write the DISPLAY color (col, semantic_alpha) to dataTextureA and move the debug/mask quad (strip, moire, viewAngle, semantic_alpha) to dataTextureB. dataTextureC is unread in this shader so nothing breaks today, but chained slots read C (= prev A) expecting COLOR - masks in A poison chains.
- Spring-damper the view angle: ease mouse.x with a critically-damped 1D spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the perspective shift rocks smoothly like tilting a real lenticular print; raw mouse.x stays the spring target. Keep the slow sin(time * 0.3) drift added AFTER the spring.
- Click holo flashes + vertical view tilt: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying moire flash ring at its click point (moireMask boost in an expanding band, ~1.2s fade), so clicks flare the foil. Wire the unused mouse.y as a vertical strip-phase tilt (small: strip phase += (mouse.y - 0.5) * 0.3) so both axes play.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash21 helper, the lenticular strip/band construction, the three-channel view-angle offsets (0.012/0.003/-0.009), the moire interference + pow 1.6 mask, the holo sin palette, and the vignette VERBATIM. All 4 sliders honestly wired (non-0..1 ranges - View Shift max 1.6, Frequency 0.1-1.0) - keep roles AND ranges EXACTLY. dataTextureB is write-only storage - fine for masks. extraBuffer in [133..255] ONLY.

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
  "id": "lenticular-holographic-shift",
  "name": "Lenticular Holographic Shift",
  "url": "shaders/lenticular-holographic-shift.wgsl",
  "description": "Simulates a lenticular/holographic print that dramatically shifts perspective, color, and moir\u00e9 interference as you move the mouse or as audio beats. Stunning on portraits and detailed imagery.",
  "tags": [
    "lenticular",
    "holographic",
    "moire",
    "print",
    "perspective",
    "audio-reactive",
    "interactive"
  ],
  "features": [
    "audio-reactive",
    "audio-driven",
    "mouse-driven",
    "semantic-alpha",
    "depth-aware"
  ],
  "params": [
    {
      "id": "shift",
      "name": "View Shift",
      "default": 0.8,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "id": "frequency",
      "name": "Lenticular Frequency",
      "default": 0.55,
      "min": 0.1,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "color",
      "name": "Holo Color Shift",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "beat",
      "name": "Audio Beat Pulse",
      "default": 0.65,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "View Shift",
      "default": 0.8,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Lenticular Frequency",
      "default": 0.55,
      "min": 0.1,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Holo Color Shift",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Audio Beat Pulse",
      "default": 0.65,
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
//  Lenticular Holographic Shift
//  Category: image
//  Features: lenticular, holographic, moire, perspective-shift, audio-beat, mouse-view, semantic-alpha
//  Complexity: Medium-High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — holographic lenticular print that shifts color and perspective with mouse and audio rhythm)
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
  zoom_params: vec4<f32>,  // x=Shift, y=Frequency, z=Color, w=Beat
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let shiftAmt = u.zoom_params.x * (0.8 + bass * 0.5);
    let freq = u.zoom_params.y * 22.0 + 6.0;
    let colorShift = u.zoom_params.z;
    let beat = u.zoom_params.w * (0.7 + treble * 0.9);

    let mouse = u.zoom_config.yz;
    let viewAngle = (mouse.x - 0.5) * 1.6 + sin(time * 0.3) * 0.1;

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Lenticular slicing — vertical strips that shift with view
    let strip = fract(uv.x * freq + viewAngle * shiftAmt * 1.8);
    let band = smoothstep(0.0, 0.18, strip) - smoothstep(0.82, 1.0, strip);

    // Three color channels offset by view angle (holographic)
    let rUV = uv + vec2<f32>(viewAngle * shiftAmt * 0.012, 0.0);
    let gUV = uv + vec2<f32>(viewAngle * shiftAmt * 0.003, 0.0);
    let bUV = uv + vec2<f32>(viewAngle * shiftAmt * -0.009, 0.0);

    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var col = vec3<f32>(r, g, b);

    // Strong moiré interference when view + audio align
    let moire = sin(strip * 38.0 + viewAngle * 14.0 + time * beat * 4.0) * 0.5 + 0.5;
    let moireMask = pow(moire * band, 1.6) * (0.4 + mids * 0.5);

    // Holographic color cycling
    let hue = fract(uv.y * 0.6 + viewAngle * 0.4 + time * 0.08 + colorShift);
    let holo = vec3<f32>(
        0.5 + 0.5 * sin(hue * 6.28318),
        0.5 + 0.5 * sin(hue * 6.28318 + 2.094),
        0.5 + 0.5 * sin(hue * 6.28318 + 4.188)
    );

    col = mix(col, col * holo, moireMask * 0.85);

    // Audio beat pulses the interference
    col += holo * moireMask * beat * 0.35;

    // Subtle vignette for print feel
    let vign = smoothstep(0.72, 0.38, length(uv - 0.5));
    col *= 0.7 + vign * 0.3;

    // Semantic alpha — higher on strong holographic bands
    let semantic_alpha = clamp(0.68 + moireMask * 0.55, 0.55, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Depth from holographic energy
    let d = clamp(0.28 + moireMask * 0.5, 0.0, 0.94);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    textureStore(dataTextureA, global_id.xy, vec4<f32>(strip, moire, viewAngle, semantic_alpha));
}
```
