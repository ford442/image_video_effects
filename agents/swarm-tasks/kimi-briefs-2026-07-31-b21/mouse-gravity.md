# Swarm Brief: mouse-gravity

**Role:** Interactivist
**Name:** Interactive Gravity
**Category:** interactive-mouse
**Description:** Gravitational distortion field that follows the mouse cursor.
**Current lines:** 105
**Target lines:** 155–195 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This gravity well is honest and already warps depth - but the singularity snaps to the cursor and clicks fall on deaf ears. Make the well feel massive:
- Spring-damper the singularity (priority 1): ease the mouse position with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) - heavy and slow is GOOD here (stiffness ~6, the well should feel massive); raw mouse stays the spring target.
- Click gravity pulses: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple creates a temporary SECONDARY gravity well at its click point (same exp(-dist/radius) distortion form, strength exp(-age * 2.0), ~2s fade, combined multiplicatively with the main distortion), so clicks punch dents into spacetime.
- Photon ring shimmer: add a subtle bright accretion ring at the event horizon (`ring = smoothstep(0.02, 0.0, abs(dist - radius * 0.35))`, tinted by treble bins `plasmaBuffer[7].x`, gated by darkness so it only shows when the core is dark) - earns the black-hole look. mouseDown can deepen the well slightly (strength * (1.0 + mouseDown * 0.3)).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the distortion falloff (1.0 - strength * exp(-dist/radius)), the r/g/b aberration offset structure, the core smoothstep darkness mix, the warped-depth read (uvG), AND the dev's thinking-out-loud comments (they are this file's personality) VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "mouse-gravity",
  "name": "Interactive Gravity",
  "url": "shaders/mouse-gravity.wgsl",
  "description": "Gravitational distortion field that follows the mouse cursor.",
  "params": [
    {
      "id": "strength",
      "name": "Gravity Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "radius",
      "name": "Event Radius",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "aberration",
      "name": "Chrom. Aberration",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "darkness",
      "name": "Core Darkness",
      "default": 0.8,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "chromatic-aberration",
    "upgraded-rgba",
    "audio-reactive",
    "depth-aware"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Gravity Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Event Radius",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Chrom. Aberration",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Core Darkness",
      "default": 0.8,
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
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse coords are in u.zoom_config.yz
    // The renderer maps them 0-1.
    var mousePos = u.zoom_config.yz;

    // Audio: bass deepens the well, mids widens its reach, treble splits chromatic aberration
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let strength = u.zoom_params.x * 2.0 * (1.0 + bass * 0.4);    // 0.0 to 2.0
    let radius = max(0.01, u.zoom_params.y * 0.5 * (1.0 + mids * 0.3)); // 0.01 to 0.5
    let aberration = u.zoom_params.z * 0.05 * (1.0 + treble * 0.8); // 0.0 to 0.05
    let darkness = u.zoom_params.w;          // 0.0 to 1.0

    // Vector from UV to Mouse
    let toMouse = uv - mousePos;
    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    let distVec = toMouse * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Gravity calculation
    // Force falls off with distance.
    // We want a warp that pulls pixels *away* from the mouse? No, a gravity well pulls space *towards* it.
    // If I look at pixel P, I want to know what light ray hits it.
    // If space is compressed towards the center, then a ray hitting P (near center) came from further out?
    // Let's implement a simple radial distortion.
    // NewUV = Mouse + (UV - Mouse) * DistortionFactor

    // If factor < 1.0, we zoom in (pull from closer to center).
    // If factor > 1.0, we zoom out (pull from further out).

    // Gravity pulls light towards it.
    // So if we look "near" the black hole, we see light from "behind" it being bent around.
    // Effectively, it magnifies the background.

    // Let's use a smooth falloff.
    // Distort = 1.0 - Strength * exp(-dist / Radius)
    let distortion = 1.0 - strength * exp(-dist / radius);

    // Apply separate distortion for RGB for chromatic aberration
    let offsetR = toMouse * (distortion - aberration);
    let offsetG = toMouse * distortion;
    let offsetB = toMouse * (distortion + aberration);

    let uvR = mousePos + offsetR;
    let uvG = mousePos + offsetG;
    let uvB = mousePos + offsetB;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Darkness at the singularity (center)
    let core = smoothstep(radius * 0.2, radius * 0.5, dist);
    color = mix(vec3<f32>(0.0), color, mix(1.0, core, darkness));

    // Handle out of bounds (optional, sampler clamps or repeats usually)
    // If we want black edges:
    // if (any(uvR < vec2(0.0)) || any(uvR > vec2(1.0))) { r = 0.0; } etc.
    // But sampler is usually set to repeat or clamp. Renderer sets it to 'repeat'.

    // Lensing-mask alpha: brighter near the warped core, luma-keyed elsewhere
    let alpha = clamp(dot(color, vec3<f32>(0.299, 0.587, 0.114)) + (1.0 - core) * darkness * 0.5, 0.0, 1.0);
    let finalOut = vec4<f32>(color, alpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalOut);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalOut);

    // Passthrough depth for now, or warp it too?
    // Warping depth might be more correct for compositing.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
