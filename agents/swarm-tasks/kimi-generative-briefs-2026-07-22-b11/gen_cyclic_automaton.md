# Swarm Brief: gen_cyclic_automaton

**Role:** Algorithmist
**Name:** Greenberg-Hastings Automaton
**Category:** generative
**Description:** Excitable cellular medium with firing, refractory cooling, bass-driven spontaneous ignition, and mouse-triggered wavefronts.
**Current lines:** 138
**Target lines:** 188–228 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on the excitable-media dynamics and wave readability:
- Wavefront leading-edge tracer: use the refractoryProgress gradient across neighbors to detect the firing wave's leading edge and render a thin bright ring there — propagating waves become legible instead of a uniform glow.
- Treble ignition sparks: plasmaBuffer[0].z raises the spontaneous-ignition probability in a fine hash-noise pattern so hi-hats seed new wave centers across the field.
- Directional mouse painting: while mouse-down, bias ignition along the mouse motion direction (compare current mouse to previous via extraBuffer[5..7]) so dragging draws cardiac-style wavefronts, not just radial blobs.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: The Greenberg-Hastings state machine (resting=0, firing=1, refractory>=2 with the select-chain) must stay logically intact — upgrade around it, don't rewrite the rule. extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional — only declare it if the shader already uses it.

## JSON Parameters / Controls

```json
{
  "id": "gen-cyclic-automaton",
  "name": "Greenberg-Hastings Automaton",
  "url": "shaders/gen_cyclic_automaton.wgsl",
  "description": "Excitable cellular medium with firing, refractory cooling, bass-driven spontaneous ignition, and mouse-triggered wavefronts.",
  "features": [
    "upgraded-rgba",
    "depth-aware",
    "audio-reactive",
    "mouse-driven",
    "temporal"
  ],
  "tags": [
    "procedural",
    "generative",
    "cellular-automaton",
    "excitable-media",
    "audio-reactive",
    "waves"
  ],
  "params": [
    {
      "id": "param1",
      "name": "States",
      "default": 0.45,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Spontaneity",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Bloom",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Cooldown",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "States",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Spontaneity",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Bloom",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Cooldown",
      "default": 0.4,
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
//  Greenberg-Hastings Excitable Automaton
//  Category: generative
//  Features: upgraded-rgba, aces-tone-map, depth-aware, audio-reactive, mouse-driven, temporal
//  Complexity: Medium
//  Scientific: Greenberg-Hastings excitable media with cardinal-wave triggering, refractory cooling, and bass-driven spontaneous ignition
//  Upgraded: 2026-06-06
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0, 0), size - vec2<i32>(1, 1));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn decodeState(v: f32, numStates: i32) -> i32 {
  return clamp(i32(floor(v * f32(numStates) + 0.5)), 0, numStates - 1);
}

fn loadState(coord: vec2<i32>, size: vec2<i32>, numStates: i32) -> i32 {
  return decodeState(textureLoad(dataTextureC, clampCoord(coord, size), 0).r, numStates);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let size = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let numStates = i32(round(mix(4.0, 24.0, u.zoom_params.x)));
  let spontaneousBase = mix(0.0001, 0.012, u.zoom_params.y);
  let bloomStrength = mix(0.15, 0.8, u.zoom_params.z);
  let cooldownBoost = mix(0.85, 1.25, u.zoom_params.w);

  let currentState = loadState(coord, size, numStates);
  let n = loadState(coord + vec2<i32>(0, -1), size, numStates);
  let s = loadState(coord + vec2<i32>(0, 1), size, numStates);
  let e = loadState(coord + vec2<i32>(1, 0), size, numStates);
  let w = loadState(coord + vec2<i32>(-1, 0), size, numStates);
  let ne = loadState(coord + vec2<i32>(1, -1), size, numStates);
  let nw = loadState(coord + vec2<i32>(-1, -1), size, numStates);
  let se = loadState(coord + vec2<i32>(1, 1), size, numStates);
  let sw = loadState(coord + vec2<i32>(-1, 1), size, numStates);

  let cardFiring = select(0, 1, n == 1) + select(0, 1, s == 1) + select(0, 1, e == 1) + select(0, 1, w == 1);
  let allFiring = cardFiring + select(0, 1, ne == 1) + select(0, 1, nw == 1) + select(0, 1, se == 1) + select(0, 1, sw == 1);

  let mouse = u.zoom_config.yz;
  let mouseMask = (1.0 - smoothstep(0.0, 0.11, distance(uv, mouse))) * u.zoom_config.w;
  let rand = hash21(vec2<f32>(f32(coord.x), f32(coord.y)) + vec2<f32>(time * 31.1, time * 17.3));
  let spontaneousProb = spontaneousBase * (0.2 + bass * 4.2);
  let ignite = (cardFiring > 0) || (rand < spontaneousProb) || (mouseMask > 0.02);

  let isResting = currentState == 0;
  let isFiring = currentState == 1;
  let isRefractory = currentState >= 2;
  let refractoryNext = select(currentState + 1, 0, currentState >= numStates - 1);

  var nextState = currentState;
  nextState = select(nextState, 1, isResting && ignite);
  nextState = select(nextState, 2, isFiring);
  nextState = select(nextState, refractoryNext, isRefractory);

  let firingMask = select(0.0, 1.0, nextState == 1);
  let refractoryMask = select(0.0, 1.0, nextState >= 2);
  let refractoryProgress = clamp(f32(max(nextState - 2, 0)) / max(1.0, f32(numStates - 2)), 0.0, 1.0);
  let neighborGlow = f32(allFiring) / 8.0;
  let bloom = neighborGlow * bloomStrength;

  let restColor = vec3<f32>(0.01, 0.03, 0.10) + vec3<f32>(0.10, 0.18, 0.34) * bloom * 0.18;
  let firingColor = mix(vec3<f32>(1.0, 0.93, 0.56), vec3<f32>(1.0, 1.0, 1.0), smoothstep(0.4, 1.0, bass + mouseMask));
  let refractoryColor = mix(vec3<f32>(0.18, 0.98, 1.0), vec3<f32>(0.03, 0.12, 0.45), refractoryProgress * cooldownBoost);

  var generatedColor = mix(restColor, refractoryColor, refractoryMask);
  generatedColor = mix(generatedColor, firingColor, firingMask);
  generatedColor += vec3<f32>(1.0, 0.96, 0.72) * bloom * 0.4;
  generatedColor += vec3<f32>(0.16, 0.44, 1.0) * bloom * (1.0 - firingMask) * 0.28;
  generatedColor += vec3<f32>(0.08, 0.12, 0.22) * smoothstep(0.2, 1.0, mids) * (1.0 - refractoryMask) * 0.15;

  let opacity = 0.92;
  let finalColor = mix(inputColor.rgb, generatedColor, opacity);
  let finalAlpha = max(inputColor.a, 0.85 + firingMask * 0.15);
  let depthSignal = max(firingMask, (1.0 - refractoryProgress) * refractoryMask);
  let finalDepth = mix(inputDepth, clamp(0.16 + depthSignal * 0.72 + bloom * 0.22 + treble * 0.06, 0.0, 1.0), 0.88);

  let caStr = 0.003 * (1.0 + bass) + finalDepth * 0.001;
  let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(acesToneMap(chromaticColor * 1.1), finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(f32(nextState) / f32(numStates), firingMask, refractoryProgress, bloom));
  textureStore(dataTextureB, coord, vec4<f32>(f32(cardFiring) / 4.0, spontaneousProb * 20.0, mouseMask, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
```
