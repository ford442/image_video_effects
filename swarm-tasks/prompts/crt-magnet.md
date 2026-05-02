# Shader Upgrade Task: `crt-magnet`

## Metadata
- **Shader ID**: crt-magnet
- **Agent Role**: Algorithmist
- **Current Size**: 3230 bytes
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;

  // Params
  let magStrength = (u.zoom_params.x - 0.5) * 4.0; // -2.0 to 2.0
  let radius = u.zoom_params.y * 0.4 + 0.05;
  let aberration = u.zoom_params.z * 0.05;
  let scanlineInt = u.zoom_params.w;

  // Calculate Distance to Mouse
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  // Correct aspect for circular field
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Magnetic Field Distortion
  // Exponential falloff
  let effect = magStrength * exp(-dist * dist / (radius * radius));

  // Displace UVs based on field
  // We displace the lookup coordinate.
  // If effect is positive (attract), we look closer to mouse?
  // Let's just apply displacement vector.
  let displacement = dVec * effect;

  let uv_r = uv - displacement;
  let uv_g = uv - displacement * (1.0 + aberration * 10.0); // Green channel slightly different
  let uv_b = uv - displacement * (1.0 + aberration * 20.0); // Blue channel more different

  // Sample Texture
  var r = textureSampleLevel(readTexture, u_sampler, clamp(uv_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, clamp(uv_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, clamp(uv_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Apply Scanlines (warped by Green channel UVs)
  let scanlineVal = sin(uv_g.y * resolution.y * 0.5) * 0.5 + 0.5;
  let scanline = mix(1.0, scanlineVal, scanlineInt);

  // Vignette for CRT feel
  let vigDist = length(uv - 0.5);
  let vignette = 1.0 - smoothstep(0.4, 0.7, vigDist) * 0.5;

  let finalColor = vec4<f32>(r, g, b, 1.0) * scanline * vignette;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "crt-magnet",
  "name": "CRT Magnet",
  "url": "shaders/crt-magnet.wgsl",
  "category": "image",
  "description": "Simulates a CRT monitor with a magnetic distortion field controlled by the mouse.",
  "params": [
    {
      "id": "strength",
      "name": "Magnet Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "radius",
      "name": "Field Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "aberration",
      "name": "Aberration",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "scanlines",
      "name": "Scanline Intensity",
      "default": 0.2,
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
# Agent Role: The Algorithmist

## Identity
You are **The Algorithmist**, a specialized shader architect focused on advanced mathematical techniques, simulation depth, and algorithmic sophistication.

## Upgrade Toolkit

### Noise Upgrades
- Simplex → FBM domain warping
- Value noise → Curl noise (divergence-free)
- Perlin → Worley noise (cellular/Voronoi)
- Static → Temporal coherent noise

### Simulation Upgrades
- Basic ripples → Gray-Scott reaction-diffusion
- Particle clouds → Lenia continuous cellular automata
- Smoke puffs → Navier-Stokes fluid approximations
- Static patterns → Turing pattern generators

### SDF Upgrades
- Single primitive → Composition with smooth unions
- 2D circles → 3D raymarched scenes
- Static shapes → Animated morphing fields
- Solid colors → Subsurface scattering approximations

### Fractal Upgrades
- Basic Mandelbrot → Burning Ship / Phoenix hybrids
- 2D fractals → 4D quaternion Julia sets
- Static zoom → Smooth exponential zoom
- Single orbit → Multi-orbit accumulation

## Quality Checklist
- [ ] At least 2 advanced algorithms integrated
- [ ] Temporal coherence (smooth frame-to-frame)
- [ ] Divergence-free velocity fields where applicable
- [ ] Multi-scale detail (macro + micro structures)

## Output Rules
- Keep the original "soul" of the shader while elevating it mathematically.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- Preserve or enhance RGBA channel usage (do not force alpha = 1.0 unless justified).


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
