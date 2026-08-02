# Swarm Brief: glass-wipes

**Role:** Interactivist
**Name:** Rainy Window
**Category:** liquid-effects
**Description:** Simulates rain on a window that distorts the view. Use the mouse to wipe the glass clean.
**Current lines:** 115
**Target lines:** 165–205 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This rainy window has a working wiper and real Beer-Lambert physics - but the wiper snaps to the cursor, clicks never splash, and the audio uniform is declared yet never sampled. Make it feel alive:
- Spring-damper the wiper (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the wiper trails the hand with weight; raw mouse stays the spring target. Keep the aspect-corrected distance.
- Click splashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a wetness splash at its click point (wetness += 0.5 * aspect-corrected ~0.15 radius smoothstep, one-shot on young ripples, clamp wetness to 1.0), so clicks spatter rain onto the glass.
- Wire the dead audio: bass-driven rain bursts (rainIntensity *= 1.0 + bass * 0.8, so downpours follow the beat) and per-band droplet glint - 8 horizontal bands each sparkle their specular by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`. Fix the stale header comment ('Category: distortion' -> liquid-effects, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the wetness state contract is SACRED - dataTextureA stores (wetness, 0, 0, wetness) STATE and dataTextureC is read as prev wetness; the engine only reads history via C - keep this packing EXACTLY and never tonemap the A write. Preserve the Beer-Lambert absorption, the Fresnel (R0=0.02), the thickness/transmission math, the droplet distortion noise, and the specular highlight VERBATIM. zoom_params.w intentionally double-duties (evaporation + glassDensity) - keep BOTH roles. All slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "glass-wipes",
  "name": "Rainy Window",
  "url": "shaders/glass-wipes.wgsl",
  "description": "Simulates rain on a window that distorts the view. Use the mouse to wipe the glass clean.",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "intensity",
      "name": "Rain Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "wiper",
      "name": "Wiper Size",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "distortion",
      "name": "Distortion",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "dry_speed",
      "name": "Drying Speed",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Rain Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Wiper Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Distortion",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Drying Speed",
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
// ═══════════════════════════════════════════════════════════════
// Glass Wipes - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: rain simulation, wiper interaction, physically-based alpha
// ═══════════════════════════════════════════════════════════════

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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RainIntensity, y=WiperSize, z=DistortionScale, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let rainIntensity = 0.005 + u.zoom_params.x * 0.05;
    let wiperSize = 0.05 + u.zoom_params.y * 0.25;
    let distortionScale = u.zoom_params.z * 0.05;
    let evaporation = 0.001 + u.zoom_params.w * 0.01;
    let glassDensity = u.zoom_params.w * 1.5 + 0.3; // Beer-Lambert density for water/glass

    // Read previous wetness state
    let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var wetness = prevState.r;

    // Add Rain
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (noise > (1.0 - rainIntensity)) {
        wetness = min(1.0, wetness + 0.3);
    }

    // Natural evaporation
    wetness = max(0.0, wetness - evaporation);

    // Mouse Wiper Interaction
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < wiperSize) {
             let wipeFactor = smoothstep(wiperSize, wiperSize * 0.5, dist);
             wetness = wetness * (1.0 - wipeFactor);
        }
    }

    // Droplet distortion
    let dripNoiseX = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5;
    let dripNoiseY = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(39.346, 11.135))) * 43758.5453) - 0.5;
    let distortion = vec2<f32>(dripNoiseX, dripNoiseY) * wetness * distortionScale;

    // Save state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(wetness, 0.0, 0.0, wetness));

    // Physical water properties
    // Water has slightly different refractive index (~1.33 vs glass ~1.5)
    // and absorption characteristics
    let waterColor = vec3<f32>(0.85, 0.95, 1.0); // Blue-tinted water
    
    // Calculate normal from distortion
    let normal = normalize(vec3<f32>(distortion * 100.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel for water
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.02; // Water-air interface (lower than glass)
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    
    // Water thickness based on wetness
    let thickness = wetness * 0.05;
    
    // Beer-Lambert absorption for water
    let absorption = exp(-(1.0 - waterColor) * thickness * glassDensity);
    
    // Transmission coefficient
    let transmission = mix(1.0, (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0, wetness);

    // Render with distortion
    let distortedUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Apply water tint and alpha based on wetness
    color = vec4<f32>(mix(color.rgb, color.rgb * waterColor, wetness * 0.5), transmission);

    // Add specular highlight for water droplets
    let lightDir = normalize(vec2<f32>(0.5, 0.5) - uv);
    let light = max(0.0, dot(normal, normalize(vec3<f32>(lightDir, 1.0))));
    let specular = pow(light, 20.0) * wetness * 0.5;

    color = color + vec4<f32>(specular, specular, specular, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
```
