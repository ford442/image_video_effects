# Swarm Brief: gen-ethereal-cyber-chrono-nebula-phoenix

**Role:** Algorithmist
**Name:** Ethereal Cyber-Chrono Nebula-Phoenix
**Category:** generative
**Description:** A majestic, hyper-organic cybernetic phoenix rising from a deep-space nebula, its wings woven from liquid auroral plasma and shattered quantum glass that burst into geometric temporal fractals upon acoustic climax.
**Current lines:** 55
**Target lines:** 105–145 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on mathematical/algorithmic depth:
- Replace naive noise with domain-warped FBM, curl noise, or Worley/Voronoi layers.
- Add SDF primitives, orbit traps, strange attractors, or fractal iterations where thematically appropriate.
- Use branchless select()/mix() instead of per-pixel if blocks.
- Preserve the original "soul" and theme of the shader.


## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.

## JSON Parameters / Controls

```json
{
  "id": "gen-ethereal-cyber-chrono-nebula-phoenix",
  "name": "Ethereal Cyber-Chrono Nebula-Phoenix",
  "description": "A majestic, hyper-organic cybernetic phoenix rising from a deep-space nebula, its wings woven from liquid auroral plasma and shattered quantum glass that burst into geometric temporal fractals upon acoustic climax.",
  "url": "shaders/gen-ethereal-cyber-chrono-nebula-phoenix.wgsl",
  "category": "generative",
  "tags": [
    "organic",
    "quantum",
    "cosmic",
    "biomechanical",
    "phoenix",
    "audio-reactive"
  ],
  "controls": [
    {
      "id": "wingspan",
      "name": "Wingspan",
      "type": "range",
      "min": 0.05,
      "max": 0.5,
      "step": 0.01,
      "default": 0.1,
      "uniformMapping": {
        "struct": "zoom_params",
        "field": "x"
      }
    },
    {
      "id": "plasma_intensity",
      "name": "Plasma Intensity",
      "type": "range",
      "min": 0.1,
      "max": 1.0,
      "step": 0.05,
      "default": 0.2,
      "uniformMapping": {
        "struct": "zoom_params",
        "field": "y"
      }
    }
  ]
}
```

## Current WGSL Code

```wgsl
// ----------------------------------------------------------------
// Ethereal Cyber-Chrono Nebula-Phoenix
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

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

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let uv = vec2<f32>(id.xy) / vec2<f32>(dims);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;

    var color = vec3<f32>(uv.x, uv.y, 0.5 + 0.5 * sin(time));

    // Audio reaction
    color += audio * u.zoom_params.y;
    // Mouse interaction
    if (length(uv - mouse) < u.zoom_params.x) {
        color += vec3<f32>(0.2);
    }

    textureStore(writeTexture, id.xy, vec4<f32>(color, 1.0));
}

```
