# Swarm Brief: reality-tear

**Role:** Visualist
**Name:** Reality Tear
**Category:** interactive-mouse
**Description:** Rips a hole in the image to reveal a static void underneath.
**Current lines:** 115
**Target lines:** 165–205 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This tear's void/burn/static composition is honest and branchless - but the rip center snaps to the cursor and clicks never open secondary rifts. Give reality more wounds:
- Spring-damper the tear center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the tear drifts with menace instead of snapping; raw mouse stays the spring target. Keep the existing aspect correction.
- Click rifts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple opens a small secondary tear at its click point (same void/border/select pipeline evaluated against a radius that grows then collapses over ~1.5s, max radius ~0.15, branchless select() composition with the main tear), so clicks puncture extra holes in reality.
- Angular FFT voices: modulate the jagged noiseVal by angular sector bins (`plasmaBuffer[(u32((angle + PI) / TAU * 8.0) % 8u) + 1u].x * 0.3`) so different sectors of the tear edge writhe to different frequencies, and let treble bins 5-8 flicker the burn color per sector instead of only global treble.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash21/valueNoise2D helpers, the dual-octave angular noise, the currentRadius construction, the branchless select() void/border composition, the void static/inverted mix, and the meaningful-alpha formula VERBATIM - the tear identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY. Keep new logic branchless (select/step/smoothstep).

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
  "id": "reality-tear",
  "name": "Reality Tear",
  "url": "shaders/reality-tear.wgsl",
  "description": "Rips a hole in the image to reveal a static void underneath.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "name": "Tear Size",
      "id": "size",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "name": "Jaggedness",
      "id": "jagged",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "name": "Burn Edge",
      "id": "border",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "name": "Static Noise",
      "id": "static",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Tear Size",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Jaggedness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Burn Edge",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Static Noise",
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
// ═══════════════════════════════════════════════════════════════════
//  Reality Tear
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i + vec2<f32>(0.0, 0.0));
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params with audio modulation
    let radiusBase = u.zoom_params.x * 0.5 * (1.0 + bass * 0.4);
    let jaggedness = u.zoom_params.y * (1.0 + mids * 0.5);
    let borderWidth = u.zoom_params.z * 0.05 * (1.0 + treble * 0.6);
    let staticAmt = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let aspectRatio = resolution.x / resolution.y;
    let uv_c = vec2<f32>(uv.x * aspectRatio, uv.y);
    let mouse_c = vec2<f32>(mouse.x * aspectRatio, mouse.y);

    let dist = distance(uv_c, mouse_c);
    let angle = atan2(uv_c.y - mouse_c.y, uv_c.x - mouse_c.x);

    let noiseVal = valueNoise2D(vec2<f32>(angle * 3.0, time * 0.5)) * 0.5 +
                   valueNoise2D(vec2<f32>(angle * 10.0, time * 2.0)) * 0.5;

    let currentRadius = radiusBase + (noiseVal - 0.5) * jaggedness * radiusBase;

    // Base sample (full vec4 to preserve alpha)
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseRGB = baseSample.rgb;
    let baseA = baseSample.a;

    // Void region
    let staticNoise = hash21(uv * 100.0 + time);
    let distUV = clamp(uv + vec2<f32>(staticNoise * 0.05), vec2<f32>(0.0), vec2<f32>(1.0));
    let distortedSample = textureSampleLevel(readTexture, u_sampler, distUV, 0.0);
    let voidStatic = vec3<f32>(staticNoise * staticAmt);
    let inverted = vec3<f32>(1.0) - distortedSample.rgb;
    let voidColor = mix(inverted, voidStatic, 0.5);

    // Border region (burning edge with audio sparkle)
    let borderFactor = clamp((dist - currentRadius) / max(borderWidth, 0.0001), 0.0, 1.0);
    let burnColor = vec3<f32>(1.0, 0.4, 0.1) * (2.0 + treble * 1.5);
    let borderColor = mix(burnColor, baseRGB, borderFactor);

    let inVoid = dist < currentRadius;
    let inBorder = (dist < currentRadius + borderWidth) && !inVoid;

    var finalRGB = baseRGB;
    finalRGB = select(finalRGB, borderColor, inBorder);
    finalRGB = select(finalRGB, voidColor, inVoid);

    // Meaningful alpha: encodes whether pixel is torn, plus base alpha
    let edgeProx = 1.0 - smoothstep(0.0, borderWidth * 2.0, abs(dist - currentRadius));
    let voidMask = select(0.0, 1.0, inVoid);
    let borderMask = select(0.0, 1.0, inBorder);
    let alpha = clamp(baseA * 0.4 + voidMask * 0.4 + borderMask * 0.6 + edgeProx * 0.3 + bass * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
```
