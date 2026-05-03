# Shader Upgrade Task: `spiral-lens`

## Metadata
- **Shader ID**: spiral-lens
- **Agent Role**: Interactivist
- **Current Size**: 3266 bytes
- **Target Line Count**: ~115 lines
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Mag, z=Twist, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;

    let radius = u.zoom_params.x * 0.5; // Scale radius
    let magnification = u.zoom_params.y * 3.0 + 0.1; // 0.1 to 3.1
    let twist = (u.zoom_params.z - 0.5) * 20.0; // -10 to 10
    let aberration = u.zoom_params.w * 0.05;

    let aspect = resolution.x / resolution.y;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    var finalUV = uv;

    // Smooth falloff
    let mask = smoothstep(radius, 0.0, dist);

    if (mask > 0.0) {
        // Twist
        let angle = twist * mask * mask;
        let s = sin(angle);
        let c = cos(angle);
        let rot = mat2x2<f32>(c, -s, s, c);

        let offset = uv - mouse;
        // Correct to square space for rotation
        var p = offset * vec2<f32>(aspect, 1.0);
        p = rot * p;
        // Back to UV space
        p = p / vec2<f32>(aspect, 1.0);

        // Magnification (Spherize)
        // If mag > 1, we want to sample closer to center.
        let zoom_factor = 1.0 / magnification;
        let current_zoom = mix(1.0, zoom_factor, mask);

        p = p * current_zoom;

        finalUV = mouse + p;
    }

    // Chromatic Aberration
    let r_uv = finalUV + (mouse - finalUV) * aberration * mask;
    let b_uv = finalUV - (mouse - finalUV) * aberration * mask;

    let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, 1.0));

    // Depth pass-through (using center UV for simplicity)
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "spiral-lens",
  "category": "image",
  "url": "shaders/spiral-lens.wgsl",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Lens Radius",
      "default": 0.5,
      "min": 0.1,
      "max": 1.0
    },
    {
      "id": "param2",
      "name": "Magnification",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "param3",
      "name": "Twist",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "param4",
      "name": "Aberration",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "name": "Spiral Lens"
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

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 115 lines (±20%).
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
