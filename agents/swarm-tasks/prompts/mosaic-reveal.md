# Shader Upgrade Task: `mosaic-reveal`

## Metadata
- **Shader ID**: mosaic-reveal
- **Agent Role**: Visualist
- **Current Size**: 3247 bytes
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
// ═══════════════════════════════════════════════════════════════════
//  mosaic-reveal - Interactive mosaic reveal effect
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, mosaic, interactive-reveal
//  Upgraded: 2026-03-22
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let mosaicSize = mix(20.0, 200.0, u.zoom_params.x);
    let radius = u.zoom_params.y * 0.5;
    let softness = u.zoom_params.z;

    var mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Calculate Mosaic UV
    let uvPix = floor(uv * mosaicSize) / mosaicSize;
    let uvCenter = uvPix + (0.5 / mosaicSize);

    // Sample Mosaic and Full Res
    let colMosaic = textureSampleLevel(readTexture, non_filtering_sampler, uvCenter, 0.0).rgb;
    let colFull = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Mask: 0 = Mosaic, 1 = Full
    let mask = 1.0 - smoothstep(radius, radius + 0.1 + softness * 0.2, dist);

    let color = mix(colMosaic, colFull, mask);

    // Calculate alpha based on mask transition and luminance
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let maskAlpha = mix(0.9, 1.0, mask);
    let alpha = mix(maskAlpha * 0.8, maskAlpha, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "mosaic-reveal",
  "name": "Mosaic Reveal",
  "url": "shaders/mosaic-reveal.wgsl",
  "category": "image",
  "description": "A low-resolution mosaic filter that clarifies into high-resolution video near the mouse cursor.",
  "features": [
    "upgraded-rgba",
    "depth-aware",
    "mosaic",
    "interactive-reveal",
    "mouse-driven"
  ],
  "params": [
    {
      "id": "size",
      "name": "Mosaic Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "radius",
      "name": "Focus Radius",
      "default": 0.4,
      "min": 0.1,
      "max": 1.0
    },
    {
      "id": "softness",
      "name": "Edge Softness",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "unused",
      "name": "Unused",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0
    }
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
