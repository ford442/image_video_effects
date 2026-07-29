# Swarm Brief: neural-nexus

**Role:** Interactivist
**Name:** Neural Nexus
**Category:** interactive-mouse
**Description:** Biological neural network simulation with pulsing electrical signals; mouse sends shockwaves through synapses.
**Current lines:** 97
**Target lines:** 147–187 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This neural field is honest but every neuron dances to the same global bands and clicks do nothing - give each neuron its own voice and make clicks fire synapses:
- Click synapse bursts (priority 1): the ripples[] uniform is unused. Loop it (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a temporary extra 'neuron' at its click point injecting a decaying pulse wave into `activity` (age = time - ripple.z, ~2s fade), so clicks visibly fire the network.
- Spring-damper the signal origin: ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so signal waves propagate from a gliding cursor rather than a snapping one; the raw clamped mouse stays the spring target.
- Per-neuron FFT voices: derive a bin index from the neuron seed (`u32(hash(...)*8.0) % 8u + 1u`) and let that bin's `plasmaBuffer[bin].x` modulate that neuron's pulse amplitude, so different neurons listen to different frequencies instead of all following global bass.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the neuron hash placement, the dendrite cos() structure, and the sampleUV displacement VERBATIM - the network identity is hand-tuned. dataTextureA stores (totalActivity, sparks, mousePulse, alpha) mask data - keep that packing, it is not display color. extraBuffer in [133..255] ONLY.

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
  "id": "neural-nexus",
  "name": "Neural Nexus",
  "category": "interactive-mouse",
  "url": "shaders/neural-nexus.wgsl",
  "description": "Biological neural network simulation with pulsing electrical signals; mouse sends shockwaves through synapses.",
  "params": [
    {
      "id": "networkDensity",
      "name": "Density",
      "default": 1,
      "min": 0.1,
      "max": 4
    },
    {
      "id": "signalSpeed",
      "name": "Signal Speed",
      "default": 1,
      "min": 0,
      "max": 4
    },
    {
      "id": "decayRate",
      "name": "Decay",
      "default": 0.5,
      "min": 0,
      "max": 2
    },
    {
      "id": "branchComplexity",
      "name": "Branches",
      "default": 2,
      "min": 1,
      "max": 8
    }
  ],
  "features": [
    "interactive",
    "organic",
    "network",
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "neural",
    "synapse",
    "electric",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Density",
      "default": 1,
      "min": 0.1,
      "max": 4.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Signal Speed",
      "default": 1,
      "min": 0.0,
      "max": 4.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Decay",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Branches",
      "default": 2,
      "min": 1.0,
      "max": 8.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Neural Nexus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: neural-nexus
//  Upgraded: 2026-05-30
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let density = clamp(u.zoom_params.x, 0.5, 4.0);
    let signalSpeed = clamp(u.zoom_params.y, 0.0, 4.0);
    let decayRate = clamp(u.zoom_params.z, 0.05, 2.5);
    let branches = clamp(u.zoom_params.w, 1.0, 8.0);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    var activity = 0.0;
    var sparks = 0.0;
    let nodeCount = 5u + u32(density * 2.0);

    for (var i: u32 = 0u; i < nodeCount; i = i + 1u) {
        let seed = f32(i) * 17.23;
        let neuronPos = vec2<f32>(
            hash(vec2<f32>(seed, 0.13)),
            hash(vec2<f32>(seed, 9.71))
        );
        let toNeuron = uv - neuronPos;
        let dist = max(length(toNeuron), 0.001);
        let connectionDist = distance(neuronPos, mousePos);
        let signalPhase = time * (3.0 + bass * 6.0) - connectionDist * (2.5 + signalSpeed * 2.0) * 6.0;
        let pulse = sin(signalPhase) * exp(-connectionDist * (1.5 + decayRate));
        let angle = atan2(toNeuron.y, toNeuron.x);
        let dendrite = 0.5 + 0.5 * cos(angle * branches + time * (1.2 + treble * 3.0) + seed);
        let aura = pulse * dendrite / (dist * (2.5 + density) + 0.35);
        activity += aura;
        sparks += exp(-dist * (20.0 + treble * 15.0)) * (0.3 + 0.7 * abs(pulse));
    }

    let mouseDist = distance(uv, mousePos);
    let mousePulse = sin(mouseDist * (16.0 + treble * 12.0) - time * (7.0 + bass * 4.0)) *
        exp(-mouseDist * (3.0 + density)) * (0.3 + bass * 0.7);

    let totalActivity = activity + mousePulse;
    let sampleUV = clamp(
        uv + vec2<f32>(totalActivity * 0.025, activity * 0.015 + mousePulse * 0.01),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );
    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let electricBlue = vec3<f32>(0.05, 0.45 + treble * 0.15, 1.0) * max(totalActivity, 0.0);
    let synapsePurple = vec3<f32>(0.9, 0.15, 1.0) * max(-totalActivity, 0.0) * 0.65;
    let warmSparks = vec3<f32>(1.0, 0.7 + mids * 0.2, 0.25) * sparks * (0.12 + bass * 0.08);
    let finalColor = baseColor.rgb + electricBlue + synapsePurple + warmSparks;
    let alpha = clamp(baseColor.a * 0.38 + abs(totalActivity) * 0.28 + sparks * 0.2 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + abs(totalActivity) * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(totalActivity, sparks, mousePulse, alpha));
}
```
