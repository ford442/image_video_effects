# Swarm Brief: interactive-emboss

**Role:** Interactivist
**Name:** Interactive Emboss
**Category:** interactive-mouse
**Description:** Emboss effect where the light source follows the mouse cursor.
**Current lines:** 107
**Target lines:** 157–197 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This emboss aims its light with a raw snapping cursor, ignores clicks, and samples depth only to pass it through despite a 'depth-aware' tag. Give the relief some feel:
- Spring-damper the light source (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the light direction sweeps smoothly across the relief; raw mouse stays the spring target.
- Click relief stamps: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying emboss pop at its click point (a local diff boost modulated by an expanding ring, ~1.2s fade), so clicks dent the surface.
- Depth-aware relief (earn the tag): scale reliefContrast by the sampled depth (`reliefContrast *= mix(0.7, 1.3, depth)`) so near geometry embosses harder than background. Also clamp the gray/color emboss output to [0,1] hue-preserving (diff can push past 1 at high strength) - soft-knee, don't hard-clip.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 4-tap Sobel-ish gradient, the light_dir dot-product emboss core, the gray/color mode step, the mix_amt compositing, AND the dev's thinking-out-loud comments (they're this file's personality - keep them, you may add your own) VERBATIM. All 4 sliders honestly wired (Intensity default 1.0 = full effect; Color Mode is a step switch) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "interactive-emboss",
  "name": "Interactive Emboss",
  "url": "shaders/interactive-emboss.wgsl",
  "description": "Emboss effect where the light source follows the mouse cursor.",
  "params": [
    {
      "id": "strength",
      "name": "Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "mix",
      "name": "Intensity",
      "default": 1,
      "min": 0,
      "max": 1
    },
    {
      "id": "colorMode",
      "name": "Color Mode",
      "default": 0,
      "min": 0,
      "max": 1,
      "labels": [
        "Gray",
        "Color"
      ]
    },
    {
      "id": "emboss_depth",
      "name": "Emboss Depth",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Depth of emboss effect"
    }
  ],
  "features": [
    "mouse-driven",
    "upgraded-rgba",
    "audio-reactive",
    "depth-aware"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Intensity",
      "default": 1,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Color Mode",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Emboss Depth",
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

  var uv = vec2<f32>(global_id.xy) / resolution;
  let texel = vec2<f32>(1.0) / resolution;

  // Audio: bass deepens relief, mids the sample reach, treble the rim glow
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Mouse acts as the light source
  var mouse = u.zoom_config.yz;

  // Vector from pixel to mouse (Light Direction)
  // We want the light to come FROM the mouse.
  // So direction is normalize(mouse - uv).
  // But for simple emboss, usually we dot the gradient with light direction.

  let light_vec = mouse - uv;
  // Normalize, but handle zero length
  var light_dir = vec2<f32>(0.0, 0.0);
  if (length(light_vec) > 0.001) {
    light_dir = normalize(light_vec);
  }

  // Parameters
  let strength = u.zoom_params.x * 5.0 * (1.0 + bass * 0.5); // Scale up for visibility. Default 0.5 -> 2.5
  let mix_amt = u.zoom_params.y;        // 0.0 = Emboss only, 1.0 = Original image
  let color_mode = u.zoom_params.z;     // 0.0 = Gray Emboss, 1.0 = Color Emboss
  let reliefContrast = 0.5 + u.zoom_params.w * 1.5;  // w: relief contrast / depth pop

  // Sample neighbors for Sobel-ish gradient
  // -1 0 1
  // -2 0 2
  // -1 0 1

  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2(-texel.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2(texel.x, 0.0), 0.0).rgb;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, -texel.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, texel.y), 0.0).rgb;

  // Calculate luminance for height map approx
  let l_lum = dot(l, vec3(0.299, 0.587, 0.114));
  let r_lum = dot(r, vec3(0.299, 0.587, 0.114));
  let t_lum = dot(t, vec3(0.299, 0.587, 0.114));
  let b_lum = dot(b, vec3(0.299, 0.587, 0.114));

  // Gradient vector (dx, dy)
  let dx = (l_lum - r_lum); // Left is higher? Or Right?
  // If light comes from right, and right pixel is darker (lower), it's in shadow?
  // Let's just stick to dot product logic.
  let dy = (t_lum - b_lum);

  let grad = vec2<f32>(dx, dy);

  // Emboss value: dot product of gradient and light direction
  let diff = dot(grad, light_dir) * strength * reliefContrast * (1.0 + mids * 0.3);

  // Gray emboss base
  let gray_emboss = vec3<f32>(0.5 + diff);

  // Color emboss: Add diff to original color
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let color_emboss = c + vec3<f32>(diff);

  let result_emboss = mix(gray_emboss, color_emboss, step(0.5, color_mode));

  // Mix with original based on parameter
  let final_color = mix(result_emboss, c, 1.0 - mix_amt); // If mix_amt is "Effect Strength", then 1.0 means full effect.
  // Wait, I said param y is "mix_amt". Let's name it "Intensity" in JSON.
  // If Intensity = 1.0, we see full emboss.

  // Relief-magnitude alpha: embossed ridges opaque, flat areas recede (treble adds rim glow)
  let alpha = clamp(abs(diff) * 2.0 + mix_amt * 0.3 + treble * 0.2 + 0.15, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));

  // Pass depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
