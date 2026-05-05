# Shader Upgrade Task: `scan-distort-gpt52`

## Metadata
- **Shader ID**: scan-distort-gpt52
- **Agent Role**: Visualist
- **Current Size**: 3236 bytes
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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.7, 289.3))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Params
  let lineParam = u.zoom_params.x;
  let bendParam = u.zoom_params.y;
  let glitchParam = u.zoom_params.z;
  let rollParam = u.zoom_params.w;

  let lines = mix(200.0, 1400.0, lineParam);
  let bend = mix(0.0, 0.18, bendParam);
  let glitch = glitchParam * 0.08;
  let roll = time * mix(0.2, 2.5, rollParam);

  var warped = uv;
  let centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  warped += centered * (radius * radius) * bend;

  let linePhase = (warped.y + roll) * lines;
  let scan = sin(linePhase) * 0.5 + 0.5;
  let scanBoost = 0.85 + 0.15 * scan;

  let lineId = floor(warped.y * lines * 0.05);
  let jitter = (hash(vec2<f32>(lineId, floor(time * 24.0))) - 0.5) * glitch;

  let blockId = floor(warped.y * 30.0);
  let blockNoise = hash(vec2<f32>(blockId, floor(time * 12.0)));
  let blockJitter = (blockNoise - 0.5) * glitch * step(blockNoise, glitchParam * 0.6);

  let offset = vec2<f32>(jitter + blockJitter, 0.0);

  let aberr = glitchParam * 0.01 + 0.002;
  let r = textureSampleLevel(readTexture, u_sampler, warped + offset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, warped + offset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, warped + offset - vec2<f32>(aberr, 0.0), 0.0).b;

  var color = vec3<f32>(r, g, b) * scanBoost;
  color += vec3<f32>(0.02, 0.01, 0.03) * (hash(uv * resolution + time) - 0.5) * glitchParam;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "scan-distort-gpt52",
  "name": "Scan Distort Matrix gpt52",
  "url": "shaders/scan-distort-gpt52.wgsl",
  "category": "image",
  "description": "High-density scanlines with rolling jitter, curvature, and chromatic tearing.",
  "params": [
    {
      "id": "lineDensity",
      "name": "Line Density",
      "default": 0.6,
      "min": 0,
      "max": 1
    },
    {
      "id": "bend",
      "name": "Curvature",
      "default": 0.35,
      "min": 0,
      "max": 1
    },
    {
      "id": "glitch",
      "name": "Glitch Jitter",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "roll",
      "name": "Roll Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "glitch",
    "animated"
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
}
```

---

## Agent Specialization
# Agent Role: The Visualist

## Identity
You are **The Visualist**, a shader architect focused on color science, lighting, and emotional impact. You make shaders visually stunning.

## Upgrade Toolkit

### Color Science
- SRGB → Linear workflow with proper gamma
- Clamped colors → HDR with values >1.0
- Static palettes → Dynamic temperature shifting
- Solid fills → Subsurface scattering glow
- Flat shading → Fresnel rim lighting

### Lighting Techniques
- Single light → 3-point studio lighting
- Diffuse only → Specular + roughness maps
- Hard shadows → Soft penumbra approximations
- Local lighting → Volumetric god rays
- Reflections → Screen-space reflections

### Atmosphere
- Clear → Volumetric fog integration
- Sharp → Bokeh depth of field
- Static → Animated caustics/dappled light
- Clean → Atmospheric scattering (Mie/Rayleigh)

### Color Grading
- Raw output → ACES tone mapped
- Static → Audio-reactive temperature
- Monochrome → Split-tone shadows/highlights
- Natural → Iridescent thin-film effects

## Quality Checklist
- [ ] HDR values exceed 1.0 in highlights
- [ ] At least 2 light sources with different temperatures
- [ ] Tone mapping applied (ACES preferred)
- [ ] Atmospheric depth (fog/haze/dust)
- [ ] Color harmony (analogous/complementary scheme)

## Output Rules
- Keep the original "soul" of the shader while making it visually stunning.
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
