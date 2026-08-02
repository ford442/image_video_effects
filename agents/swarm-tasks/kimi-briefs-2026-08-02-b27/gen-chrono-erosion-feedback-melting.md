# Swarm Brief: gen-chrono-erosion-feedback-melting

**Role:** Algorithmist
**Name:** Chrono Erosion
**Category:** artistic
**Description:** Datamosh-like flow effect where video melts along a curl-noise vector field with feedback decay and audio-driven turbulence.
**Current lines:** 117
**Target lines:** 167–207 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This datamosh melt has a DEAD SLIDER - 'Feedback Mix' (w) is read into `feedbackMix` and then never referenced; the melt weight is `decay` alone. The mouse smudge is also elliptical (no aspect correction). Fix the plumbing:
- WIRE THE DEAD SLIDER (priority 1 - bit-exact at default 0.6): make feedbackMix scale the feedback weight (`let meltW = clamp(decay * (feedbackMix / 0.6), 0.0, 0.98); let melted = mix(current, feedback, meltW);` - default 0.6 reproduces `decay` exactly, lower values favor the live frame, higher values deepen the mosh). ASPECT-CORRECT the smudge: `mouseDist = length(mouseDelta)` -> correct both uv and mouse by (aspect, 1.0) before the distance so the influence is circular.
- Spring-damper the smudge: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the smear finger drags with weight; raw mouse stays the spring target.
- Click melt vortices + per-region FFT: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying rotational flow vortex at its click point (tangent vector * exp(-rippleAge * 1.8) * 0.02, aspect-corrected ~0.2 radius, ~2s), so clicks stir the melt. Modulate the turbulence per 8 vertical bands (`plasmaBuffer[(band % 8u) + 1u].x * 0.5`) so different strips boil at different energies.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the feedback contract is SACRED - dataTextureC read at displacedUV, dataTextureA written with outCol RAW (clamp 1.5) - never tonemap the A write. Preserve the hash/noise/curlNoise helpers, the curl flow construction, the bass shock block (keep its branchy form - it predates the branchless convention and is the file's character), the flowMag color shift, the beat inversion block, and the displacedUV clamp VERBATIM. All 4 slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "gen-chrono-erosion-feedback-melting",
  "name": "Chrono Erosion",
  "url": "shaders/gen-chrono-erosion-feedback-melting.wgsl",
  "description": "Datamosh-like flow effect where video melts along a curl-noise vector field with feedback decay and audio-driven turbulence.",
  "features": [
    "audio-reactive",
    "temporal",
    "mouse-driven",
    "feedback"
  ],
  "tags": [
    "erosion",
    "melt",
    "datamosh",
    "feedback",
    "curl-noise",
    "audio",
    "artistic"
  ],
  "params": [
    {
      "id": "decay",
      "name": "Trail Decay",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "flowIntensity",
      "name": "Flow Intensity",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "feedbackMix",
      "name": "Feedback Mix",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Trail Decay",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Flow Intensity",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Turbulence",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Feedback Mix",
      "default": 0.6,
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
// ═══════════════════════════════════════════════════════════════════════════════
//  Chrono-Erosion - Feedback Melting
//  Category: artistic
//  Description: Datamosh-like flow where video melts along a curl-noise
//               vector field with feedback decay and audio-driven turbulence.
//  Features: audio-reactive, temporal, feedback
// ═══════════════════════════════════════════════════════════════════════════════

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
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.01;
    let n0 = noise(p + vec2<f32>(eps, 0.0) + t);
    let n1 = noise(p - vec2<f32>(eps, 0.0) + t);
    let n2 = noise(p + vec2<f32>(0.0, eps) + t);
    let n3 = noise(p - vec2<f32>(0.0, eps) + t);
    let dndx = (n0 - n1) / (2.0 * eps);
    let dndy = (n2 - n3) / (2.0 * eps);
    return vec2<f32>(dndy, -dndx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let audioOverall = plasmaBuffer[0].x + plasmaBuffer[0].y + plasmaBuffer[0].z;

    // Parameters
    let decay = u.zoom_params.x * 0.9 + 0.05;
    let flowIntensity = u.zoom_params.y * 0.05 + 0.005;
    let turbulence = u.zoom_params.z * 2.0;
    let feedbackMix = u.zoom_params.w;

    // Curl-noise flow field
    var flow = curlNoise(uv * 3.0, time * 0.1) * flowIntensity;

    // Mouse smudge
    let mouse = u.zoom_config.yz;
    let mouseDelta = uv - mouse;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = smoothstep(0.3, 0.0, mouseDist);
    flow = flow + normalize(mouseDelta + vec2<f32>(0.001)) * mouseInfluence * 0.02;

    // Audio turbulence spikes
    if (bass > 0.6) {
        let shock = bass * 0.03;
        let shockAngle = time * 7.0 + hash(uv * 10.0) * 6.28318;
        flow = flow + vec2<f32>(cos(shockAngle), sin(shockAngle)) * shock;
    }

    // Displaced UV for feedback sample
    let displacedUV = clamp(uv + flow * (1.0 + turbulence), vec2<f32>(0.0), vec2<f32>(1.0));

    // Read current frame and feedback
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let feedback = textureSampleLevel(dataTextureC, u_sampler, displacedUV, 0.0).rgb;

    // Melt blend: weighted mix with decay
    let melted = mix(current, feedback, decay);

    // Color shift based on flow magnitude
    let flowMag = length(flow) * 20.0;
    let shiftR = melted.r * (1.0 + flowMag * bass);
    let shiftG = melted.g * (1.0 + flowMag * 0.5);
    let shiftB = melted.b * (1.0 - flowMag * 0.3);

    var outCol = vec3<f32>(shiftR, shiftG, shiftB);

    // Audio-reactive color inversion on strong beats
    if (audioOverall > 0.7) {
        outCol = mix(outCol, vec3<f32>(1.0) - outCol, (audioOverall - 0.7) * 0.5);
    }

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.5));

    // Write feedback to dataTextureA for next frame
    textureStore(dataTextureA, id.xy, vec4<f32>(outCol, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, id.xy, vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
