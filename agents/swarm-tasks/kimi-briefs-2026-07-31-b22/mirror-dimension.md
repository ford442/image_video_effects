# Swarm Brief: mirror-dimension

**Role:** Visualist
**Name:** Mirror Dimension
**Category:** artistic
**Description:** A rotating kaleidoscope that fractures reality. Mouse moves the center of symmetry.
**Current lines:** 109
**Target lines:** 159–199 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This kaleidoscope's fold math is beautiful and honest - but the symmetry center snaps with the cursor and clicks never touch the mirror. Make the dimension breathe:
- Spring-damper the symmetry center (priority 1): ease the mouse offset with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the fracture point drifts smoothly; raw mouse stays the spring target. Keep the branchless mouseActive gate on the RAW mouse.
- Click mirror spins: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying rotation kick to `a` (a one-way spin impulse exp(-age * 2.0) * 2.0 radians, signed by hash of the click position), so clicks whirl the kaleidoscope.
- Per-segment FFT shimmer: tint each folded segment subtly by its own bin (`plasmaBuffer[(segIdx % 8u) + 1u].x` where segIdx derives from the pre-fold angle) as a +-8% brightness modulation, so segments pulse across the spectrum. Fix the stale header ('Category: kaleidoscope' -> artistic, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the polar conversion, the fract-based segment modulo, the triangle fold (abs), the zoom/offset application, and the aspect un-correction VERBATIM - the fold is the identity. All 4 sliders honestly wired (Shift default 0) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "mirror-dimension",
  "name": "Mirror Dimension",
  "url": "shaders/mirror-dimension.wgsl",
  "description": "A rotating kaleidoscope that fractures reality. Mouse moves the center of symmetry.",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "segments",
      "name": "Segments",
      "min": 0,
      "max": 1,
      "default": 0.5
    },
    {
      "id": "rotation-speed",
      "name": "Spin Speed",
      "min": 0,
      "max": 1,
      "default": 0.6
    },
    {
      "id": "offset",
      "name": "Shift",
      "min": 0,
      "max": 1,
      "default": 0
    },
    {
      "id": "zoom",
      "name": "Zoom",
      "min": 0,
      "max": 1,
      "default": 0.5
    }
  ],
  "tags": [
    "stylized",
    "artistic"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Segments",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Spin Speed",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Shift",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Zoom",
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
//  Mirror Dimension
//  Category: kaleidoscope
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let segments  = floor(mix(2.0, 12.0, u.zoom_params.x));
    let baseRotSpeed = mix(-1.0, 1.0, u.zoom_params.y);
    // Bass modulates rotation speed
    let rotSpeed  = baseRotSpeed * (1.0 + bass * 0.5);
    let offsetVal = u.zoom_params.z;
    // Mids modulate zoom intensity
    let zoom      = mix(0.5, 2.0, u.zoom_params.w) * (1.0 + mids * 0.15);

    // Center UV and correct aspect
    var p = uv - 0.5;
    let aspect = resolution.x / max(resolution.y, 0.001);
    p.x *= aspect;

    // Branchless mouse offset: apply when zoom_config.y > 0
    let mouseActive = step(0.001, u.zoom_config.y);
    let m = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    p -= m * mouseActive;

    // Polar coords
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Animate rotation
    a += u.config.x * rotSpeed;

    // Segment angle
    let segmentAngle = 3.14159265 * 2.0 / max(segments, 1.0);

    // Branchless modulo into [0, segmentAngle] using fract — handles negatives
    a = fract(a / segmentAngle) * segmentAngle;

    // Triangle fold (mirror half of the segment)
    a = abs(a - segmentAngle * 0.5);

    // Convert back to cartesian
    var uv_new = vec2<f32>(cos(a), sin(a)) * r;

    // Offset and zoom
    uv_new += vec2<f32>(offsetVal * 0.1);
    uv_new *= zoom;

    // Un-correct aspect and un-center
    uv_new.x /= aspect;
    uv_new += 0.5;

    // Clamp displaced UV before sampling
    let uv_clamped = clamp(uv_new, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampled = textureSampleLevel(readTexture, u_sampler, uv_clamped, 0.0);

    // Meaningful alpha: encodes radial position + fold angle closeness + bass energy
    let foldCloseness = 1.0 - clamp(a / max(segmentAngle * 0.5, 0.001), 0.0, 1.0);
    let radialFactor  = clamp(1.0 - r * 0.8, 0.0, 1.0);
    let alpha = clamp(radialFactor * 0.5 + foldCloseness * 0.3 + bass * 0.2, 0.0, 1.0);

    let finalColor = vec4<f32>(sampled.rgb, alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
```
