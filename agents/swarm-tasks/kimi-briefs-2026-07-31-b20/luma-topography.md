# Swarm Brief: luma-topography

**Role:** Visualist
**Name:** Luma Topography
**Category:** interactive-mouse
**Description:** Visualizes the image as a 3D terrain map where brightness determines height. The mouse controls a dynamic light source.
**Current lines:** 103
**Target lines:** 153–193 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This relief-lighting shader's JSON labels are honest - but its own struct comment lies about the param roles, the mouse light snaps, clicks do nothing, and the depth buffer is sampled then ignored by the lighting. Polish the terrain:
- Spring-damper the light source (priority 1): ease the mouse light position with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the light sweeps across the relief with weight; raw mouse stays the spring target. Keep the attenuation falloff computed from the SPRUNG position.
- Click fill-light flashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying point light at its click point (same Blinn-Phong path as the mouse light, warm tint, ~1.5s fade, contributes to diff+spec additively), so clicks strike matches across the terrain.
- Depth-aware lighting + comment fixes: use the sampled depth to bias the pixel height (`pixelPos3D.z = luma * 0.2 + depth * 0.1`) so near geometry catches more specular - earns the depth read. Fix the stale comments (comment-only): zoom_params roles are x=ReliefHeight, y=LightIntensity, z=Shininess, w=Ambient (per the JSON); header 'Category: image' is stale (JSON lives in interactive-mouse); config.y = ripple COUNT.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the getLuma helper, the 2-tap luma gradient normal, the Blinn-Phong (diff/spec/H) math, the attenuation curve, and the warm lightColor mids shimmer VERBATIM - the relief look is hand-tuned. All 4 sliders are honestly wired - keep roles EXACTLY (saved-preset contract). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "luma-topography",
  "name": "Luma Topography",
  "url": "shaders/luma-topography.wgsl",
  "description": "Visualizes the image as a 3D terrain map where brightness determines height. The mouse controls a dynamic light source.",
  "params": [
    {
      "id": "height",
      "name": "Relief Height",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "intensity",
      "name": "Light Intensity",
      "default": 0.8,
      "min": 0,
      "max": 1
    },
    {
      "id": "shininess",
      "name": "Shininess",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "ambient",
      "name": "Ambient Light",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "lighting",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Relief Height",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Light Intensity",
      "default": 0.8,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Shininess",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Ambient Light",
      "default": 0.2,
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
// ═══════════════════════════════════════════════════════════════════
//  Luma Topography
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Parameters — bass boosts light intensity
    let heightScale = u.zoom_params.x * 20.0 + 1.0;
    let lightIntensity = u.zoom_params.y * 2.0 * (1.0 + bass * 0.4);
    let shininess = u.zoom_params.z * 32.0 + 1.0;
    let ambient = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);

    let colorSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let color = colorSample.rgb;
    let luma = getLuma(color);

    let texelSize = 1.0 / resolution;

    let lumaRight = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb);
    let lumaTop   = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb);

    let dX = lumaRight - luma;
    let dY = lumaTop - luma;

    let normal = normalize(vec3<f32>(-dX * heightScale, -dY * heightScale, 1.0));

    let lightHeight = 0.2;
    let pixelPos3D = vec3<f32>(uv.x * aspect, uv.y, luma * 0.2);
    let lightPos3D = vec3<f32>(mousePos.x * aspect, mousePos.y, lightHeight);

    let L = normalize(lightPos3D - pixelPos3D);
    let V = vec3<f32>(0.0, 0.0, 1.0);

    let diff = max(dot(normal, L), 0.0);
    let H = normalize(L + V);
    let spec = pow(max(dot(normal, H), 0.0), shininess);

    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mousePos.x * aspect, mousePos.y));
    let atten = 1.0 / (1.0 + dist * 5.0);

    // Mids add warm shimmer to specular
    let lightColor = vec3<f32>(1.0, 0.95 + mids * 0.05, 0.8);

    let finalDiffuse  = diff * lightColor * lightIntensity * atten;
    let finalSpecular = spec * lightColor * lightIntensity * atten;

    let litColor = clamp(color * (vec3<f32>(ambient) + finalDiffuse) + finalSpecular, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: specular highlight + diffuse strength + original alpha
    let alpha = clamp(spec * atten * 0.6 + diff * atten * 0.3 + colorSample.a * 0.15 + bass * 0.05, 0.0, 1.0);
    let fc = vec4<f32>(litColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
```
