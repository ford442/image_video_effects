# Swarm Brief: multi-scale-evolutionary-cellular-gardens

**Role:** Algorithmist
**Name:** Multi-Scale Evolutionary Cellular Gardens
**Category:** generative
**Description:** Two competing cellular species whose growth rules slowly evolve under audio pressure. The garden changes its fundamental behavior over time while remaining visually coherent.
**Current lines:** 124
**Target lines:** 174–214 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on the simulation's depth and emergent behavior:
- Upgrade the 4-neighbor sampling to full 8-neighbor (add diagonals) with distance-correct weights (1.0 orthogonal, ~0.707 diagonal) — the species/resource diffusion gets visibly smoother.
- Worley colony-border accent: detect species territory boundaries (where s1 and s2 dominance flips between neighbors) and add a restrained bioluminescent glow line there.
- Replace the generic applyGenerativePrimaryControls boilerplate mapping with shader-specific control: sliders must drive real sim constants (mutation rate, competition, fertility, nurture radius) — the boilerplate intensity/speed/contrast remapping is not meaningful control for a CA sim.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: dataTextureA carries the sim state (s1, s2, resource) and dataTextureC is the readback — keep the channel layout and the update ordering intact, only strengthen the rules around it.

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
  "id": "multi-scale-evolutionary-cellular-gardens",
  "name": "Multi-Scale Evolutionary Cellular Gardens",
  "url": "shaders/multi-scale-evolutionary-cellular-gardens.wgsl",
  "category": "generative",
  "description": "Two competing cellular species whose growth rules slowly evolve under audio pressure. The garden changes its fundamental behavior over time while remaining visually coherent.",
  "features": [
    "multi-state-ca",
    "rule-evolution",
    "audio-mutation",
    "multi-scale",
    "organic-growth",
    "upgraded-rgba",
    "chromatic-species",
    "temporal-color-memory"
  ],
  "tags": [
    "cellular-automata",
    "evolutionary",
    "organic",
    "garden",
    "audio-reactive",
    "emergent"
  ],
  "params": [
    {
      "id": "mutationPressure",
      "name": "Mutation Pressure",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "How quickly the growth rules evolve"
    },
    {
      "id": "competition",
      "name": "Species Competition",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "How fiercely the two species compete"
    },
    {
      "id": "fertility",
      "name": "Resource Fertility",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "How much new resources appear"
    },
    {
      "id": "mouseNurture",
      "name": "Mouse Nurturing Power",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "How much the mouse can locally boost growth"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Mutation Pressure",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Species Competition",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Resource Fertility",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Mouse Nurturing Power",
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
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Features: multi-state-ca, rule-evolution, audio-mutation, multi-scale, organic-growth,
//            chromatic-species, bass-mutation-waves, temporal-color-memory, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Chunks From: cellular automata + slow parameter evolution
//  Created: 2026-05-31
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.25;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let s1 = state.r;
    let s2 = state.g;
    let resourceLevel = state.b;

    let mutationRate = 0.3 + mids * 0.9;
    let competition = 0.2 + bass * 0.6;

    let ps = 1.0 / res;
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( ps.x, 0.0), 0.0);
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>( ps.x, 0.0), 0.0);
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0,  ps.y), 0.0);
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0,  ps.y), 0.0);

    let avgS1 = (n1.r + n2.r + n3.r + n4.r) * 0.25;
    let avgS2 = (n1.g + n2.g + n3.g + n4.g) * 0.25;
    let avgRes = (n1.b + n2.b + n3.b + n4.b) * 0.25;

    let growth1 = 0.04 + mutationRate * 0.03;
    let growth2 = 0.035 + mutationRate * 0.025;

    var newS1 = s1 + (avgRes * growth1 - competition * s1 * s2);
    var newS2 = s2 + (avgRes * growth2 - competition * s1 * s2 * 0.8);
    var newRes = resourceLevel * 0.98 + 0.01 - (newS1 + newS2) * 0.008;

    let mouseDist = length(uv - mouse);
    let mouseNurture = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 0.6;
    newRes += mouseNurture;
    newS1 += mouseNurture * 0.3;
    newS2 += mouseNurture * 0.25;

    newS1 = clamp(newS1, 0.0, 1.8);
    newS2 = clamp(newS2, 0.0, 1.8);
    newRes = clamp(newRes, 0.0, 1.5);

    textureStore(dataTextureA, gid.xy, vec4<f32>(newS1, newS2, newRes, 0.0));

    // Chromatic species separation: species1 = green/cyan, species2 = magenta/purple
    let c1 = vec3<f32>(0.1, 0.7 + bass * 0.2, 0.5 + treble * 0.2) * newS1;
    let c2 = vec3<f32>(0.8 + mids * 0.1, 0.2, 0.6 + treble * 0.2) * newS2;
    let resCol = vec3<f32>(0.3, 0.5, 0.3) * newRes * 0.4;

    // Temporal color memory: previous frame tint bleeds in
    let prevCol = state.rgb;
    let col = mix(c1 + c2 + resCol, prevCol * vec3<f32>(0.95, 0.9, 0.85), 0.08 + bass * 0.03);

    let totalLife = newS1 * 0.6 + newS2 * 0.6;
    let alpha = clamp(totalLife * 0.85 + newRes * 0.2 + bass * 0.05, 0.15, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, applyGenerativePrimaryControls(vec4<f32>(col, a)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalLife * 0.6, 0.0, 0.0, 0.0));
}
```
