# Swarm Brief: porcelain-fracture-glow

**Role:** Visualist
**Name:** Porcelain Fracture Glow
**Category:** artistic
**Description:** The image is rendered on delicate porcelain that develops fine luminous cracks. The cracks follow image edges and can be drawn with the mouse. Bass makes the golden light pulse and sing through the fractures.
**Current lines:** 119
**Target lines:** 169–209 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This kintsugi crack network follows the image's own edges - beautiful - but clicks (the natural 'drop the plate' gesture) do nothing and the mouse only cracks while held. Give it impact:
- Click fracture impacts (priority 1): loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple strikes a crack burst at its click point (a decaying radial crack star: totalCrack += aspect-corrected ~0.15 falloff * crackAmt * exp(-age * 1.2), ~2.5s slow heal, PLUS a brief bright vein flash on impact), so clicks drop the porcelain.
- Spring-damper the crack focus: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the press-crack point glides; raw mouse stays the spring target and mousePress keeps its role riding the sprung point.
- Per-band FFT vein song: 8 vertical bands each modulate their leak term by `plasmaBuffer[(band % 8u) + 1u].x * 0.35`, so the glowing veins sing different notes across the spectrum instead of only global bass/treble.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: dataTextureA stores FIELD data (totalCrack, leak, lightTemp, semantic_alpha) - NOT display color - keep that packing VERBATIM. Preserve the hash21/valueNoise/fbm helpers, the edge-following crack network (both fbm octaves + smoothstep), the vein/leak/rim construction, the porcelain base mix, the patina, the semantic alpha, and the depth write VERBATIM. Slider ranges are custom (Crack 0-1.4, Glow 0-1.6) - keep ids/names/defaults/ranges EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "porcelain-fracture-glow",
  "name": "Porcelain Fracture Glow",
  "url": "shaders/porcelain-fracture-glow.wgsl",
  "description": "The image is rendered on delicate porcelain that develops fine luminous cracks. The cracks follow image edges and can be drawn with the mouse. Bass makes the golden light pulse and sing through the fractures.",
  "tags": [
    "porcelain",
    "crack",
    "kintsugi",
    "light",
    "artistic",
    "audio-reactive",
    "interactive"
  ],
  "features": [
    "audio-reactive",
    "audio-driven",
    "mouse-driven",
    "mouse-crack",
    "semantic-alpha",
    "depth-aware"
  ],
  "params": [
    {
      "id": "crack",
      "name": "Crack Amount",
      "default": 0.65,
      "min": 0.0,
      "max": 1.4,
      "step": 0.01
    },
    {
      "id": "glow",
      "name": "Glow Intensity",
      "default": 0.85,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "id": "light",
      "name": "Light Temperature",
      "default": 0.35,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "age",
      "name": "Patina Age",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Crack Amount",
      "default": 0.65,
      "min": 0.0,
      "max": 1.4,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Glow Intensity",
      "default": 0.85,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Light Temperature",
      "default": 0.35,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Patina Age",
      "default": 0.4,
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
//  Porcelain Fracture Glow
//  Category: artistic
//  Features: porcelain, crack, kintsugi, light-vein, audio-pulse, mouse-crack, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21, valueNoise)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — fine porcelain that develops glowing luminous cracks following image structure, audio makes the light sing)
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
  zoom_params: vec4<f32>,  // x=Crack, y=Glow, z=Light, w=Age
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) { v += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let crackAmt = u.zoom_params.x * (0.7 + bass * 0.5);
    let glowAmt = u.zoom_params.y * (0.8 + treble * 0.6);
    let lightTemp = u.zoom_params.z;
    let age = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let mousePress = u.zoom_config.w;

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Crack network — follows image edges + organic noise
    let edge = length(vec2<f32>(
        luma - dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0012, 0.0), 0.0).rgb, vec3<f32>(0.299,0.587,0.114)),
        luma - dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 0.0012), 0.0).rgb, vec3<f32>(0.299,0.587,0.114))
    )) * 2.2;

    let crackNoise = fbm(uv * 18.0 + age * 1.5, 4) * 0.6 + fbm(uv * 41.0 - time * 0.03, 3) * 0.4;
    let crack = smoothstep(0.32, 0.78, edge + crackNoise * 0.55) * crackAmt;

    // Mouse can "draw" new cracks
    let mouseCrack = smoothstep(0.04, 0.0, length(uv - mouse)) * mousePress * 1.4;
    let totalCrack = clamp(crack + mouseCrack * 0.7, 0.0, 1.0);

    // Luminous kintsugi-style veins
    let vein = pow(totalCrack, 1.4) * glowAmt;
    let veinColor = mix(vec3<f32>(1.0, 0.65, 0.25), vec3<f32>(0.4, 0.85, 1.0), lightTemp);

    // Porcelain base (slightly cool, glossy)
    let porcelain = mix(input.rgb, vec3<f32>(0.92, 0.9, 0.88), 0.35);
    var col = mix(porcelain, input.rgb, 0.7 - totalCrack * 0.4);

    // Glowing light leaking from cracks
    let leak = vein * (0.6 + bass * 0.5 + sin(time * 3.0 + uv.x * 9.0) * treble * 0.3);
    col += veinColor * leak * 1.3;

    // Subtle rim light on cracks
    col += veinColor * pow(vein, 2.5) * 0.8;

    // Age patina
    let patina = fbm(uv * 3.0, 2) * age * 0.12;
    col = mix(col, col * vec3<f32>(0.75, 0.82, 0.78), patina);

    // Semantic alpha — cracks glow with light
    let semantic_alpha = clamp(0.62 + leak * 0.7 + vein * 0.35, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    let d = clamp(0.22 + vein * 0.6, 0.0, 0.95);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    textureStore(dataTextureA, global_id.xy, vec4<f32>(totalCrack, leak, lightTemp, semantic_alpha));
}
```
