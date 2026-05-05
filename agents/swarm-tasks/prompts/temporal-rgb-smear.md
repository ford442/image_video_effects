# Shader Upgrade Task: `temporal-rgb-smear`

## Metadata
- **Shader ID**: temporal-rgb-smear
- **Agent Role**: Interactivist
- **Current Size**: 3065 bytes
- **Target Line Count**: ~130 lines
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=GreenLag, y=BlueLag, z=Feedback, w=unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  // x: Green Channel Lag (0.0 - 1.0)
  // y: Blue Channel Lag (0.0 - 1.0)
  // z: Feedback amount (0.0 - 0.99)
  let greenLag = mix(0.1, 0.95, u.zoom_params.x);
  let blueLag = mix(0.2, 0.98, u.zoom_params.y);
  let feedback = u.zoom_params.z;

  // Mouse influence - reduce lag near mouse
  var mouse = u.zoom_config.yz;
  let dist = distance(uv, mouse);
  let mouseFactor = smoothstep(0.0, mix(0.1, 0.6, u.zoom_params.w), dist); // 0 near mouse, 1 far

  // Modulate lag with mouse
  let gLag = greenLag * (0.5 + 0.5 * mouseFactor);
  let bLag = blueLag * (0.5 + 0.5 * mouseFactor);

  // Read current frame
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Read history (R=GreenHistory, G=BlueHistory)
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

  // Calculate new history values
  // We want: NewHistory = mix(Current, OldHistory, Lag)
  let newGreenHistory = mix(current.g, history.r, gLag);
  let newBlueHistory = mix(current.b, history.g, bLag);

  // Output color
  // R = Instant
  // G = Green History
  // B = Blue History
  let outputColor = vec4<f32>(current.r, newGreenHistory, newBlueHistory, current.a);

  // Store new history
  // Store G history in R, B history in G
  textureStore(dataTextureA, global_id.xy, vec4<f32>(newGreenHistory, newBlueHistory, 0.0, 1.0));

  // Write to screen
  textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "temporal-rgb-smear",
  "name": "Temporal RGB Smear",
  "category": "image",
  "url": "shaders/temporal-rgb-smear.wgsl",
  "description": "Separates RGB channels in time. Red is instant, Green and Blue trail behind with variable lag.",
  "params": [
    {
      "id": "green_lag",
      "name": "Green Lag",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Lag amount for the green channel"
    },
    {
      "id": "blue_lag",
      "name": "Blue Lag",
      "default": 0.8,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Lag amount for the blue channel"
    },
    {
      "id": "feedback",
      "name": "Feedback",
      "default": 0.0,
      "min": 0.0,
      "max": 0.99,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Feedback amount for temporal smearing"
    },
    {
      "id": "mouse_influence",
      "name": "Mouse Influence Radius",
      "default": 0.5,
      "min": 0.1,
      "max": 0.6,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Radius of mouse influence on lag reduction"
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
4. Ensure the upgraded shader is roughly 130 lines (±20%).
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
