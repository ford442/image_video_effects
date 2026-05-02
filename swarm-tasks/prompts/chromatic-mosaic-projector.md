# Shader Upgrade Task: `chromatic-mosaic-projector`

## Metadata
- **Shader ID**: chromatic-mosaic-projector
- **Agent Role**: Interactivist
- **Current Size**: 3242 bytes
- **Target Line Count**: ~140 lines
- **Status**: pending

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The `Uniforms` struct definition.
3. `@workgroup_size` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

---

## Current WGSL Source
```wgsl
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let cellSize = mix(10.0, 100.0, u.zoom_params.x); // Cells
    let spread = u.zoom_params.y * 2.0;
    let aberration = u.zoom_params.z * 0.1;
    let tint = u.zoom_params.w;

    // Grid coordinates
    let gridUV = floor(uv * cellSize) / cellSize;
    let cellCenter = gridUV + (0.5 / cellSize);

    var mouse = u.zoom_config.yz;

    // Vector from mouse to cell (Projector light direction)
    // Correct for aspect
    let vecToCell = (cellCenter - mouse) * vec2(aspect, 1.0);
    let dist = length(vecToCell);
    var dir = normalize(vecToCell);

    // Calculate sample offset based on light direction (Shadow casting logic)
    // Actually, let's just use the direction to shift RGB channels

    // Sample texture at cell center (Mosaic effect)
    // Add offset based on direction * spread
    let baseOffset = dir * dist * spread * 0.1;

    // Chromatic Aberration
    let rOffset = baseOffset + (dir * aberration);
    let gOffset = baseOffset;
    let bOffset = baseOffset - (dir * aberration);

    let r = textureSampleLevel(readTexture, u_sampler, cellCenter + rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, cellCenter + gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, cellCenter + bOffset, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Vignette per cell
    let cellUV = fract(uv * cellSize); // 0-1 within cell
    let cellDist = distance(cellUV, vec2(0.5));
    // Soft circle
    let shape = smoothstep(0.5, 0.4, cellDist);

    color = color * shape;

    // Tint based on mouse distance (light falloff)
    let lightFalloff = 1.0 / (1.0 + dist * 2.0);
    color = color * lightFalloff;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "chromatic-mosaic-projector",
  "name": "Chromatic Mosaic",
  "url": "shaders/chromatic-mosaic-projector.wgsl",
  "category": "image",
  "description": "Projects the image onto a mosaic grid with chromatic aberration controlled by the mouse light source.",
  "params": [
    {
      "id": "cells",
      "name": "Cell Count",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "spread",
      "name": "Light Spread",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "chroma",
      "name": "Aberration",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "tint",
      "name": "Light Tint",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0
    }
  ],
  "features": [
    "mouse-driven"
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
}
```

---

## Agent Specialization
# Agent Role: The Interactivist

## Identity
You are **The Interactivist**, a shader architect focused on input reactivity, feedback loops, and emergent behavior.

## Upgrade Toolkit

### Mouse Interaction
- Position tracking → Gravity wells / attractors
- Click events → Spawn bursts / shockwaves
- Velocity tracking → Motion blur trails
- Multi-touch → Multi-agent systems

### Audio Reactivity
- Bass pulse → Scale/brightness modulation
- Mid frequencies → Pattern morphing speed
- Treble → Sparkle/additive particles
- FFT buckets → Multi-band color splitting

### Video Feedback
- Static overlay → Optical flow distortion
- Fixed transparency → Alpha blending based on depth
- Simple masking → Luma-keyed particle spawn
- Direct color → Motion-vector advection

### Depth Integration
- 2D effects → Parallax depth separation
- Uniform blur → Depth-of-field bokeh
- Flat shading → Ambient occlusion darkening
- Screen space → Volumetric depth fog

### Feedback Loops
- Single pass → Temporal accumulation
- Static state → Ping-pong buffer feedback
- Linear time → Recursive subdivision
- Fixed camera → Smooth follow with lag

## Quality Checklist
- [ ] Mouse affects at least 2 parameters
- [ ] Audio drives at least 1 visual element
- [ ] Video input influences the effect
- [ ] Temporal feedback creates trails/smoothing
- [ ] Emergent behavior (not 1:1 input mapping)

## Output Rules
- Keep the original "soul" of the shader while making it alive and reactive.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- `plasmaBuffer[0].x` = bass, `.y` = mids, `.z` = treble. Use them.
- `u.zoom_config.yz` = mouse position (0-1). `u.zoom_config.w` = mouse down.
- Preserve or enhance RGBA channel usage.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 140 lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. ```wgsl
[upgraded shader source]
```
2. ```json
[updated shader definition]
```

If the JSON does not need changes, return the original JSON unchanged.
