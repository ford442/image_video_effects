# Swarm Brief: cyber-trace

**Role:** Interactivist
**Name:** Cyber Trace
**Category:** interactive-mouse
**Description:** A glowing neon trail that follows your mouse cursor and reacts to clicks, overlaid on the video feed.
**Current lines:** 117
**Target lines:** 167–207 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This neon tracer's raw-history feedback is solid - but it never samples the audio, the brush snaps, and clicks leave no mark beyond the held drag. Light it up:
- Spring-damper the brush (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the trace ribbons behind the cursor; raw mouse stays the spring target. Keep the aspect correction and the down/idle brush strength select.
- WIRE THE DEAD AUDIO: bass pulses the glow (glowIntensity * (1.0 + bass * 0.5) at the composite only - history stays raw), mids drive the hue cycle speed (colorTick rate * (1.0 + mids * 0.8)), and 8 vertical bands each shimmer their composite glow by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`.
- Click stamp blooms: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a soft round bloom into the history at its click point (same drawColor pipeline, radius ~ brushSize * 1.5, decaying with ripple age ~1.5s), so clicks paint stars without dragging.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the history contract is SACRED - dataTextureC read as prev history, dataTextureA written RAW (historyColor * decaySpeed + drawColor * brush, clamp to 2.0) - never tonemap the A write; audio modulation of glow happens ONLY at the composite. Preserve the hue2rgb/hslToRgb helpers and ALL dev commentary comments VERBATIM (file personality). Custom slider ranges are EXACT (Trail Decay 0.8-0.99, Glow Intensity 0-3, Brush Size 0.005-0.2). extraBuffer in [133..255] ONLY.

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
  "id": "cyber-trace",
  "name": "Cyber Trace",
  "url": "shaders/cyber-trace.wgsl",
  "description": "A glowing neon trail that follows your mouse cursor and reacts to clicks, overlaid on the video feed.",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "decay",
      "name": "Trail Decay",
      "min": 0.8,
      "max": 0.99,
      "default": 0.96
    },
    {
      "id": "glow",
      "name": "Glow Intensity",
      "min": 0,
      "max": 3,
      "default": 1.5
    },
    {
      "id": "color",
      "name": "Color Shift",
      "min": 0,
      "max": 1,
      "default": 0
    },
    {
      "id": "size",
      "name": "Brush Size",
      "min": 0.005,
      "max": 0.2,
      "default": 0.05
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Trail Decay",
      "default": 0.96,
      "min": 0.8,
      "max": 0.99,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Glow Intensity",
      "default": 1.5,
      "min": 0.0,
      "max": 3.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Color Shift",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Brush Size",
      "default": 0.05,
      "min": 0.005,
      "max": 0.2,
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
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Helper function for HSL to RGB conversion
fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
    var t_clamped = t;
    if (t_clamped < 0.0) { t_clamped = t_clamped + 1.0; }
    if (t_clamped > 1.0) { t_clamped = t_clamped - 1.0; }
    if (t_clamped < 1.0/6.0) { return p + (q - p) * 6.0 * t_clamped; }
    if (t_clamped < 1.0/2.0) { return q; }
    if (t_clamped < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t_clamped) * 6.0; }
    return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    var r: f32;
    var g: f32;
    var b: f32;

    if (s == 0.0) {
        r = l;
        g = l;
        b = l;
    } else {
        var q: f32;
        if (l < 0.5) {
            q = l * (1.0 + s);
        } else {
            q = l + s - l * s;
        }
        var p = 2.0 * l - q;
        r = hue2rgb(p, q, h + 1.0/3.0);
        g = hue2rgb(p, q, h);
        b = hue2rgb(p, q, h - 1.0/3.0);
    }
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Params
    let decaySpeed = u.zoom_params.x; // 0.90 to 0.99
    let glowIntensity = u.zoom_params.y; // 0.5 to 3.0
    let hueShift = u.zoom_params.z; // 0.0 to 1.0
    let brushSize = u.zoom_params.w; // 0.01 to 0.1

    // Mouse Interaction
    // Correct for aspect ratio to make brush circular
    let aspect = f32(dims.x) / f32(dims.y);
    var mousePos = u.zoom_config.yz;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Brush
    var brush = 0.0;
    // Always active or only when mouse down?
    // u.zoom_config.w is 1.0 if mouse is down.
    // Let's make it always trace but stronger when down.
    let isMouseDown = u.zoom_config.w > 0.5;

    let baseBrush = smoothstep(brushSize, brushSize * 0.5, dist);
    brush = baseBrush * (select(0.5, 1.0, isMouseDown));

    // History (Read from C, Write to A)
    let historyColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Calculate new color to add
    let time = u.config.x;
    let colorTick = time * 0.2 + hueShift;
    let drawColor = hslToRgb(fract(colorTick), 1.0, 0.5);

    // Add brush to history
    let newHistory = clamp(historyColor.rgb * decaySpeed + drawColor * brush, vec3<f32>(0.0), vec3<f32>(2.0));

    // Write State
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newHistory, 1.0));

    // Composition
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Mix input with glowing trail
    // Additive blending for the glow
    let finalColor = inputColor + newHistory * glowIntensity;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
