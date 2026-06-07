# Shader Upgrade Task: `pixel-depth-sort`

## Metadata
- **Shader ID**: pixel-depth-sort
- **Agent Role**: Visualist
- **Current Size**: 3195 bytes
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
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);

  var mouse = u.zoom_config.yz;

  // Params
  let depth_scale = mix(0.0, 0.2, u.zoom_params.x); // Max displacement
  let shadow_str = u.zoom_params.y;
  let quality = u.zoom_params.z;

  let num_layers = mix(10.0, 60.0, quality);

  // Tilt direction based on mouse position relative to center
  // Invert mouse y for intuitive tilt
  let tilt = vec2<f32>(0.5 - mouse.x, 0.5 - mouse.y);

  let view_vec = tilt * depth_scale;

  var final_color = vec3<f32>(0.0);

  // Iterate back to front
  // i represents height (0.0 = background, 1.0 = foreground)
  for (var i = 0.0; i <= 1.0; i += 1.0 / num_layers) {
     let layer_height = i;
     // The "higher" the pixel is, the more it shifts relative to the base
     let offset = view_vec * layer_height;

     // We are looking for the pixel that *would be* at 'uv' if it were at 'layer_height'.
     // So we sample at 'uv + offset'.
     let sample_uv = uv + offset;

     if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
       let samp = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
       let luma = getLuma(samp);

       // If the sampled pixel's height (luma) is at least the current layer height,
       // then this pixel exists at this layer and occludes whatever was behind it.
       if (luma >= layer_height) {
         final_color = samp;

         // Simple rim shadowing
         if (luma < layer_height + mix(0.0, 0.2, u.zoom_params.w) && shadow_str > 0.0) {
            final_color *= (1.0 - shadow_str * 0.5);
         }
       }
     }
  }

  textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "pixel-depth-sort",
  "name": "Pixel Depth Sort",
  "url": "shaders/pixel-depth-sort.wgsl",
  "category": "image",
  "description": "Simulates 3D depth by displacing pixels based on their brightness. Mouse controls the viewing perspective.",
  "params": [
    {
      "id": "depth",
      "name": "Depth Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Maximum displacement depth"
    },
    {
      "id": "shadows",
      "name": "Shadow Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Strength of layer rim shadows"
    },
    {
      "id": "layers",
      "name": "Quality",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Number of depth layers to sample"
    },
    {
      "id": "shadow_threshold",
      "name": "Shadow Threshold",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Threshold for applying rim shadowing"
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
