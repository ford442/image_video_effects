# Shader Upgrade Task: `phosphor-decay`

## Metadata
- **Shader ID**: phosphor-decay
- **Agent Role**: Visualist
- **Current Size**: 3215 bytes
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
    let decayRate = mix(0.8, 0.99, u.zoom_params.x); // Persistence
    let mouseIntensity = mix(0.0, 2.0, u.zoom_params.y);
    let mouseRadius = mix(0.01, 0.2, u.zoom_params.z);
    let colorShift = u.zoom_params.w; // Shift color of trails?

    // Read previous frame (History)
    // dataTextureC is the read-only view of the previous frame's dataTextureA
    // Note: If this is the first frame, it might be empty/black.
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Read current input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mouse Beam
    var mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let beam = smoothstep(mouseRadius, 0.0, dist) * mouseIntensity;
    let beamColor = vec4<f32>(beam, beam, beam, 1.0); // White beam

    // Calculate decayed history
    // Option: shift hue of history?
    var decayed = history * decayRate;

    if (colorShift > 0.1) {
       // Simple tinting of trails: boost G, reduce R/B (Matrix style)
       decayed = decayed * vec4<f32>(0.95, 1.0, 0.95, 1.0);
    }

    // Combine:
    // We want the brighter of (Input + Beam) vs (History).
    // Or (Input + Beam) + History?
    // "Phosphor" logic is usually max(new, old * decay).

    let source = inputColor + beamColor;
    let finalColor = max(source, decayed);

    // Write output
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Store for next frame
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "phosphor-decay",
  "name": "Phosphor Decay",
  "url": "shaders/phosphor-decay.wgsl",
  "category": "visual-effects",
  "description": "Simulates CRT phosphor persistence. Bright areas leave trails. Mouse acts as an electron beam.",
  "params": [
    {
      "name": "Persistence",
      "type": "f32",
      "min": 0.0,
      "max": 1.0,
      "default": 0.8,
      "id": "persistence"
    },
    {
      "name": "Beam Intensity",
      "type": "f32",
      "min": 0.0,
      "max": 1.0,
      "default": 0.5,
      "id": "beam_intensity"
    },
    {
      "name": "Beam Size",
      "type": "f32",
      "min": 0.0,
      "max": 1.0,
      "default": 0.2,
      "id": "beam_size"
    },
    {
      "name": "Color Drift",
      "type": "f32",
      "min": 0.0,
      "max": 1.0,
      "default": 0.0,
      "id": "color_drift"
    }
  ],
  "features": [
    "mouse-driven"
  ],
  "tags": [
    "vfx",
    "particles",
    "glow"
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
