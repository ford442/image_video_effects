# Swarm Brief: spectrum-bleed

**Role:** Algorithmist
**Name:** Spectrum Bleed
**Category:** retro-glitch
**Description:** Color channel separation and bleeding effects.
**Current lines:** 118
**Target lines:** 168–208 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This shader reads its 'sliders' from u.zoom_config.x/y/z - which is TIME and the MOUSE POSITION, not parameters - so 'diffusion' ramps forever with the clock and ALL FOUR real sliders (zoom_params) are dead. Bonus bug: the multi-pass blur loop re-samples the source into the same variable every pass, so passes 2+ change nothing. Rebuild the plumbing:
- FIX THE UNIFORM BUG + WIRE ALL 4 DEAD SLIDERS (priority 1 - ids/names/defaults EXACTLY): stop reading zoom_config for parameters entirely. x ('Intensity', 0.5) -> blendFactor = x * 0.6 (default = today's mid-bleed look). y ('Speed', 0.5) -> hue drift rate (newHue = fract(hsv.x + y * time * 0.1)). z ('Scale', 0.5) -> blur radius: sampleBlur takes a radius multiplier (texel * mix(1.0, 4.0, z)) making the spread real instead of the idempotent loop - DELETE the dead passes loop. w ('Detail', 0.5) -> satBoost = w * 0.5 (default 0.25, a vivid but legal bleed). zoom_config.yz returns to its TRUE role: the mouse.
- HONEST MOUSE + CLICKS: tagged mouse-driven - add a bleed lens: near the (aspect-corrected, spring-damped - extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) cursor, blendFactor rises (+= lensMask * 0.3) so color bleeds outward from the pointer. Loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a saturation bloom at its click point (hsv.y += 0.4 * falloff * exp(-age*2.0), ~1.5s), so clicks splatter ink.
- Per-region FFT voices: 8 vertical bands each shift their hue drift phase by `plasmaBuffer[(band % 8u) + 1u].x * 0.2`, so the bleed rainbow shimmers across the spectrum.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the rgb2hsv/hsv2rgb helpers, the sampleBlur 4-tap kernel (parameterized by radius), the persist/max temporal feedback (A=(persist, 1.0) write, C read, 0.93 decay), and the depth passthrough VERBATIM. The hsv2rgb branchy tier style may stay (file character). All 4 slider ids/names/defaults/ranges EXACTLY (generic names Intensity/Speed/Scale/Detail are the saved-preset contract - do NOT rename). extraBuffer in [133..255] ONLY.

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
  "id": "spectrum-bleed",
  "name": "Spectrum Bleed",
  "url": "shaders/spectrum-bleed.wgsl",
  "description": "Color channel separation and bleeding effects.",
  "tags": [
    "filter",
    "image-processing"
  ],
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
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
// ---------------------------------------------------------------
//  Spectrum Bleed – vibrant colors bleed outward like ink diffusion
//  Adjustable diffusion speed, hue drift, and saturation boost.
// ---------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=diffusion, y=hueDrift, z=satBoost, w=unused
  zoom_params: vec4<f32>,       // reserved for future use
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Colour utilities
// ---------------------------------------------------------------
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ---------------------------------------------------------------
//  Simple Gaussian blur kernel (2x2) for diffusion
// ---------------------------------------------------------------
fn sampleBlur(uv: vec2<f32>, tex: texture_2d<f32>, sampler_: sampler) -> vec3<f32> {
    let texel = 1.0 / u.config.zw;
    var sum = vec3<f32>(0.0);
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb * 0.25;
    return sum;
}

// ---------------------------------------------------------------
//  Main
// ---------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // 1️⃣ Read source colour and depth
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // 2️⃣ Uniforms
    let diffusion = u.zoom_config.x;   // speed of colour spread
    let hueDrift  = u.zoom_config.y;   // how fast hue rotates
    let satBoost  = u.zoom_config.z;   // extra saturation for bleed

    // 3️⃣ Compute blurred colour (diffusion)
    var blurred = src;
    // Apply multiple blur passes based on diffusion amount
    let passes = u32(diffusion * 4.0 + 1.0);
    for (var i: u32 = 0u; i < passes; i = i + 1u) {
        blurred = sampleBlur(uv, readTexture, u_sampler);
    }

    // 4️⃣ Hue drift over time
    let hsv = rgb2hsv(blurred);
    let newHue = fract(hsv.x + hueDrift * time * 0.05);
    let drifted = hsv2rgb(newHue, hsv.y, hsv.z);

    // 5️⃣ Boost saturation for vivid bleed effect
    let finalCol = hsv2rgb(newHue, min(hsv.y + satBoost, 1.0), hsv.z);

    // 6️⃣ Blend original with bleed based on diffusion strength
    let blendFactor = diffusion * 0.6;
    var outCol = mix(src, finalCol, blendFactor);

    // 7️⃣ Temporal persistence (memory of previous frame)
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let persist = max(prev * 0.93, outCol);
    outCol = max(outCol, persist * 0.2);

    // 8️⃣ Output colour and depth
    textureStore(writeTexture, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    
    // Also update dataTextureA (dataTextureA)
    textureStore(dataTextureA, gid.xy, vec4<f32>(persist, 1.0));
}
```
