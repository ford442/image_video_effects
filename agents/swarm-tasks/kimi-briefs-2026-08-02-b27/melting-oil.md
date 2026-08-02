# Swarm Brief: melting-oil

**Role:** Algorithmist
**Name:** Melting Oil
**Category:** artistic
**Description:** Sobel gradient-driven oil-paint flow with viscosity and hue shifts.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Three of this oil flow's four sliders are LIES - 'Turbulence' drives the mouse force, 'Ripple Strength' drives the hue shift, 'Color Shift' drives the audio boost - and its ripple loop is a legacy non-standard 8-iteration form with no rippleCount guard. Make the labels honest and the clicks standard:
- REWIRE THE 3 MISLABELED SLIDERS (priority 1 - ids/names/defaults EXACTLY, defaults reproduce today's look bit-exact): y ('Turbulence', 0.4) must drive real chaotic flow - add a time-varying sinusoidal turbulence perturbation to flow_dir scaled by y, with y=0.4 reproducing the current feel (the old mouseForce role moves to a fixed constant 0.4 so the mouse gate is unchanged at default). z ('Ripple Strength', 0.5) must scale the click-stir amplitude (the `stir` accumulation *= mix(0.0, 2.0, z) - default 0.5 = 1.0 bit-exact). w ('Color Shift', 0.3) must drive the hue-shift mix (hueShiftK = w - default 0.3 lands on today's hue behavior; the old audioK role becomes a fixed 1.0 multiplier on the bass boost).
- CONVERT THE LEGACY RIPPLE LOOP to the standard guarded form: `let rippleCount = min(u32(u.config.y), 50u); for (var i = 0u; i < rippleCount; i++)` - keep the existing stir math (exp(-dR2*60) swirl pulse, 3s alive window) as the per-ripple behavior, now honoring the real click count. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.
- Spring-damper the mouse influence + per-region FFT: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the flow bend glides; raw mouse stays the spring target. Modulate the hue-shift phase by 8 vertical-band bins (`plasmaBuffer[(band % 8u) + 1u].x * 0.3`) so the oil sheen shimmers across the spectrum. Fix the stale header ('Category: simulation' -> artistic, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 9-tap Sobel gradient (r0/r1/r2 textureLoad grid), the grad/flow_dir construction, the mouseGate gaussian, the advection sampling (last_pos/dimF), the hue_shift PHI math, and the alpha formula VERBATIM - the flow identity is hand-tuned. dataTextureA stays DISPLAY color. The engine manages the A->C history copy; keep reads of dataTextureC as-is. extraBuffer in [133..255] ONLY. All slider ids/names/defaults/ranges EXACTLY (saved-preset contract).

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
  "id": "melting-oil",
  "name": "Melting Oil",
  "url": "shaders/melting-oil.wgsl",
  "description": "Sobel gradient-driven oil-paint flow with viscosity and hue shifts.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "simulation",
    "physics"
  ],
  "params": [
    {
      "id": "viscosity",
      "name": "Viscosity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Liquid thickness/resistance"
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Chaotic flow intensity"
    },
    {
      "id": "ripple_strength",
      "name": "Ripple Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Wave distortion amount"
    },
    {
      "id": "color_shift",
      "name": "Color Shift",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Color manipulation amount"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Viscosity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Turbulence",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Ripple Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Shift",
      "default": 0.3,
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
//  Melting Oil
//  Category: simulation
//  Features: gradient-flow, branchless-ripples, audio-reactive, advection, upgraded-rgba
//  Complexity: Medium
//  Created: Phase B / Optimizer
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Viscosity, y=MouseForce, z=HueShift, w=Audio
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    let dim = textureDimensions(dataTextureA);
    let dimF = vec2<f32>(f32(dim.x), f32(dim.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let viscosity = clamp(0.85 + u.zoom_params.x * 0.13, 0.5, 0.99);
    let mouseForceK = clamp(u.zoom_params.y, 0.0, 1.0);
    let hueShiftK = clamp(u.zoom_params.z, 0.0, 1.0);
    let audioK = clamp(u.zoom_params.w * (1.0 + bass * 0.5), 0.0, 2.0);

    let r0 = vec3<f32>(
        textureLoad(dataTextureC, coord + vec2<i32>(-1, -1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 0, -1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 1, -1), 0).r);
    let r1 = vec3<f32>(
        textureLoad(dataTextureC, coord + vec2<i32>(-1,  0), 0).r,
        textureLoad(dataTextureC, coord, 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 1,  0), 0).r);
    let r2 = vec3<f32>(
        textureLoad(dataTextureC, coord + vec2<i32>(-1,  1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 0,  1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 1,  1), 0).r);

    let gx = (r0.z + 2.0 * r1.z + r2.z) - (r0.x + 2.0 * r1.x + r2.x);
    let gy = (r2.x + 2.0 * r2.y + r2.z) - (r0.x + 2.0 * r0.y + r0.z);
    let grad = vec2<f32>(gx, gy);
    let gradLen = max(length(grad), 1e-4);
    var flow_dir = grad / gradLen;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
    let dM = length(toMouse);
    let mouseGate = exp(-dM * dM * 12.0) * (mouseForceK + mouseDown * 0.5);
    let mouseDir = toMouse / max(dM, 1e-4);
    flow_dir = normalize(mix(flow_dir, mouseDir, mouseGate));

    var stir = vec2<f32>(0.0);
    for (var i = 0; i < 8; i++) {
        let rip = u.ripples[i];
        let rippleActive = step(1e-4, rip.z);
        let age = max(time - rip.z, 0.0);
        let alive = step(age, 3.0);
        let toR = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
        let dR2 = dot(toR, toR);
        let pulse = exp(-dR2 * 60.0) * (1.0 - age / 3.0) * rippleActive * alive;
        stir += vec2<f32>(-toR.y, toR.x) * 0.5 * pulse;
    }
    flow_dir = normalize(flow_dir + stir);

    let advectStep = flow_dir * viscosity * (1.0 + audioK * 0.4);
    let last_pos = vec2<f32>(coord) - advectStep;
    let color = textureSampleLevel(readTexture, u_sampler, clamp(last_pos / dimF, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let hue_shift = (gradLen * 0.8 + time * 0.05) * hueShiftK * PHI;
    let hueMat = vec3<f32>(0.5 + 0.5 * sin(hue_shift),
                           0.5 + 0.5 * sin(hue_shift + 2.094),
                           0.5 + 0.5 * sin(hue_shift + 4.188));
    var shifted = mix(color.rgb, color.rgb * (0.6 + hueMat * 0.8), hueShiftK);

    let luma = dot(shifted, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.5 + gradLen * 0.6 + mouseGate * 0.2 + treble * 0.05 + 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(shifted, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
