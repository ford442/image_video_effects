# Swarm Brief: laser-burn

**Role:** Interactivist
**Name:** Laser Burn
**Category:** interactive-mouse
**Description:** Temporal burn accumulation with ember glow and audio spark showers. Mouse beam chars the surface persistently; embers fade slower than heat for lingering glow. Treble creates flying spark particles near the beam, bass deepens the char.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This burn sim's char/heat/ember state machine is solid - but the beam snaps to the cursor and clicks (mouseDown is the ONLY burn trigger) never brand a lasting mark. Give the laser some weight:
- Spring-damper the beam (priority 1): ease the mouse with a HEAVY critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT, omega ~6) so the beam lags the hand like real hardware; raw mouse stays the spring target. The lag streak naturally extends burn paths.
- Click brand stamps: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple sears a brand at its click point (heatLevel += 0.6 * aspect-corrected ~0.08 radius smoothstep * exp(-rippleAge * 1.5), one pulse), so single clicks tattoo the surface without holding the button. These feed the SAME char/ember pipeline.
- Per-region spark bins: divide the beam zone into 8 angular sectors around the beam center; each sector's sparkChance threshold rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x`) instead of only global treble, so spark showers dance around the beam. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown (not 'Generic2').
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the burn state contract is SACRED - dataTextureA stores (charLevel, cooledHeat, emberLevel, burnAlpha) STATE and dataTextureC is read as prev state; the engine only reads history via C - keep this packing EXACTLY and never tonemap/clamp the A write beyond the existing clamps. Preserve the hash12/bass_env helpers, the heat->char->ember accumulation math, the healFactor/ember decay, the fireColor/emberColor/sparkColor ramps, and the burnAlpha formula VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "laser-burn",
  "name": "Laser Burn",
  "url": "shaders/laser-burn.wgsl",
  "description": "Temporal burn accumulation with ember glow and audio spark showers. Mouse beam chars the surface persistently; embers fade slower than heat for lingering glow. Treble creates flying spark particles near the beam, bass deepens the char.",
  "params": [
    {
      "id": "beamSize",
      "name": "Beam Size",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "burnSpeed",
      "name": "Burn Intensity",
      "default": 0.8,
      "min": 0,
      "max": 1
    },
    {
      "id": "healRate",
      "name": "Heal Rate",
      "default": 0,
      "min": 0,
      "max": 1
    },
    {
      "id": "heatMode",
      "name": "Heat Glow",
      "default": 1,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "temporal-accumulation",
    "ember-glow",
    "audio-sparks",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "laser",
    "burn",
    "interactive",
    "fire",
    "embers",
    "sparks"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Beam Size",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Burn Intensity",
      "default": 0.8,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Heal Rate",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Heat Glow",
      "default": 1,
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
//  Laser Burn
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-accumulation, ember-glow, audio-sparks, upgraded-rgba
//  Complexity: High
//  Chunks From: laser-burn, bass_env, temporal-feedback
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = mix(1.0, 0.7, depth);

    let beamSize = mix(0.01, 0.15, u.zoom_params.x) * (1.0 + bass * 0.2);
    let burnSpeed = u.zoom_params.y * 0.2 * (1.0 + treble * 0.3);
    let healFactor = mix(1.0, 0.9, u.zoom_params.z);
    let heatMix = u.zoom_params.w;

    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var charLevel = prev.r;
    var heatLevel = prev.g;
    var emberLevel = prev.b;

    let mouse = u.zoom_config.yz;
    let mouseDown = step(0.5, u.zoom_config.w);

    let aspect = resolution.x / max(resolution.y, 0.001);
    var dVec = uv - mouse;
    dVec.x *= aspect;
    let dist = length(dVec);

    let inBeam = step(dist, beamSize) * mouseDown;
    let intensity = smoothstep(beamSize, beamSize * 0.5, dist);
    heatLevel += intensity * burnSpeed * inBeam;

    // Ember accumulation: heat chars the surface, embers glow after
    let cooledHeat = heatLevel * 0.9;
    charLevel += cooledHeat * 0.1;
    charLevel = clamp(charLevel, 0.0, 1.0);
    charLevel *= healFactor;

    // Ember persistence: embers fade slower than heat
    emberLevel = mix(emberLevel, cooledHeat, 0.1);
    emberLevel *= 0.95;

    // Audio spark showers: treble creates flying sparks near the beam
    let sparkChance = hash12(uv * 100.0 + time * 10.0);
    let spark = step(1.0 - treble * 0.3, sparkChance) * inBeam * 0.5;
    emberLevel += spark;
    emberLevel = clamp(emberLevel, 0.0, 1.0);

    let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Visuals: char darkens source, ember glow adds warmth
    var finalColor = source.rgb * (1.0 - charLevel);
    let fireColor = vec3<f32>(1.0, 0.6 + mids * 0.2, 0.2);
    let emberColor = vec3<f32>(1.0, 0.4, 0.1) * emberLevel * 2.0;
    finalColor += fireColor * cooledHeat * (0.5 + heatMix * 2.0);
    finalColor += emberColor * depthMod;

    // Audio sparks are bright white-yellow
    let sparkColor = vec3<f32>(1.0, 0.9, 0.6) * spark * 3.0;
    finalColor += sparkColor;

    let burnAlpha = clamp(charLevel * 0.6 + cooledHeat * 0.3 + emberLevel * 0.2 + dot(finalColor, vec3<f32>(0.299, 0.587, 0.114)) * 0.2, 0.0, 1.0);
    let outputColor = vec4<f32>(finalColor, burnAlpha);

    let stateColor = vec4<f32>(charLevel, cooledHeat, emberLevel, burnAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), stateColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
