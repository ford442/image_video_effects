# Swarm Brief: neon-topology

**Role:** Algorithmist
**Name:** Neon Topology
**Category:** visual-effects
**Description:** Renders the image as a glowing 3D topographic map.
**Current lines:** 98
**Target lines:** 148–188 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This contour shader is tagged 'mouse-driven' but NEVER READS THE MOUSE - and two of its four sliders are lies. Fix the contract:
- WIRE THE MOUSE + REWIRE THE LIES (priority 1): w ('Mouse Force', default 0.5) currently drives hue shift and the mouse is unread - make w drive a real mouse lens: bump the sampled depth near the cursor (`depth += mouseMask * w * 0.25`, aspect-corrected smoothstep falloff ~0.35 radius) so contours warp around the pointer. y ('Height Scale', default 0.5) currently drives the alpha helper's edge threshold - make it scale the contour field height (`contourPhase = depth * mix(0.5, 2.0, y) * contourLevels`, default 0.5 = factor 1.25; verify the default look stays close). Move the hue shift to a slow constant drift (time * 0.15) so the color identity survives.
- Remove the dead `alpha` variable (computed, never used - finalAlpha is computed separately). Fold anything useful from it into finalAlpha explicitly.
- Click contour quakes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying depth ripple ring at its click point (expanding sinusoidal bump, ~1.5s), so clicks drop pebbles into the topology.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the branchless contour construction (fract phase + smoothstep lines + major step), the edgePreserveAlpha 5-tap depth helper, and the phantom-contour audio term VERBATIM in structure - they are the shader's identity. dataTextureA stays DISPLAY color. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "neon-topology",
  "url": "shaders/neon-topology.wgsl",
  "description": "Renders the image as a glowing 3D topographic map.",
  "params": [
    {
      "id": "density",
      "name": "Line Density",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "height",
      "name": "Height Scale",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "mouse",
      "name": "Mouse Force",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "glow",
      "name": "Glow Strength",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven"
  ],
  "tags": [
    "vfx",
    "particles",
    "glow",
    "audio",
    "music",
    "reactive"
  ],
  "name": "Neon Topology",
  "updatedParams": [
    {
      "index": 0,
      "name": "Line Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Height Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Mouse Force",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Glow Strength",
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
//  Neon Topology
//  Category: visual-effects
//  Features: advanced-alpha, topology, neon, contours, mouse-driven, audio-reactive, depth-haze, upgraded-rgba
//  Complexity: High
//  Chunks From: neon-topology, bass_env, depth-aware-fog
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ContourLevels, y=EdgeThreshold, z=Intensity, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let contourLevels = u.zoom_params.x * 10.0 + 3.0 + audioBass * 4.0;
    let edgeThreshold = u.zoom_params.y * 0.1 + 0.02;
    let intensity = u.zoom_params.z * 2.0 * bass_env(audioBass, mids);
    let colorShift = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Branchless contour lines
    let contourPhase = depth * contourLevels;
    let contour = fract(contourPhase);
    let line = smoothstep(0.05, 0.0, contour);
    let major = step(0.95, fract(contourPhase * 0.2));
    let lineWithMajor = line * (1.0 + major * 0.6);

    // Audio elevation: bass adds phantom contours above actual depth
    let phantomPhase = (depth + audioBass * 0.1) * contourLevels * 0.5;
    let phantomLine = smoothstep(0.03, 0.0, fract(phantomPhase)) * audioBass * 0.5;

    // Neon color with treble shimmer
    let phase = depth * 10.0 + colorShift * TAU + time + treble * 2.0;
    let neonColor = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    // Depth atmospheric haze
    let haze = exp(-depth * 3.0) * 0.3;

    let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let bg = bgSample.rgb;
    let bgGray = vec3<f32>(dot(bg, vec3<f32>(0.299, 0.587, 0.114))) * 0.4;
    let emission = neonColor * (lineWithMajor + phantomLine) * intensity;
    let final_color = mix(bgGray + emission, vec3<f32>(0.1, 0.15, 0.25), haze);

    let alpha = clamp(edgePreserveAlpha(uv, pixelSize, edgeThreshold) * lineWithMajor
                      + dot(emission, vec3<f32>(0.299, 0.587, 0.114)) * 0.3 + phantomLine * 0.2, 0.0, 1.0);
    let finalAlpha = mix(bgSample.a, 1.0, intensity * lineWithMajor * 0.7);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(final_color, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
