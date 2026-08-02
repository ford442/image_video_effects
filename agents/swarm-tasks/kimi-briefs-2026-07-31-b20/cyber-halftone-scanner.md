# Swarm Brief: cyber-halftone-scanner

**Role:** Algorithmist
**Name:** Cyber Halftone Scanner
**Category:** image
**Description:** CMYK-style halftone pattern with a scanning glitch line.
**Current lines:** 104
**Target lines:** 154–194 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This halftone's plasma tint reads out of bounds - `plasmaBuffer[palIdx % 256u]` indexes past the real FFT bin count and gets zeros (dead black tint). Third sighting of this bug class. Guard it, then give the scanner a pulse:
- GUARD THE PALETTE READ (priority 1): wrap the palette index to the live bin range (`(palIdx % 8u) + 1u`, bins 1-8) so the scan stripe tint is always real audio data. Remove the dead PHI constant (or use it - your call, but no unused consts).
- Click scan bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns a secondary horizontal scanline sweeping from its click row (same exp(-d^2 * 90) profile, vertical velocity +-0.5 choosing direction by hash of the click position, ~1.5s fade), so clicks fire scanner sweeps.
- Mouse proximity dot bloom (optional flavor, this shader isn't tagged mouse-driven): near the cursor, locally raise `boost` (+0.15 smoothstep falloff ~0.25 radius) so dots bloom under the pointer like a magnifying lamp. Also modulate the scan stripe intensity by its vertical FFT band (`plasmaBuffer[u32(scanY * 8.0) + 1u].x`) so the sweep carries the spectrum.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the grid() helper, the canonical CMYK screen angles (15/75/0/45 + 1.05 K-scale), the step()-based halftone thresholding, the cyber tint palette (cyan/magenta/yellow + K darken), and the scanline exp profile VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "cyber-halftone-scanner",
  "name": "Cyber Halftone Scanner",
  "url": "shaders/cyber-halftone-scanner.wgsl",
  "description": "CMYK-style halftone pattern with a scanning glitch line.",
  "params": [
    {
      "id": "scale",
      "name": "Dot Scale",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Scan Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "separation",
      "name": "RGB Split",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "brightness",
      "name": "Brightness",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
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
      "name": "Dot Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Scan Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "RGB Split",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Brightness",
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
//  Cyber Halftone Scanner
//  Category: image
//  Features: rotated screens, scanline, audio-reactive, plasma-tint, upgraded-rgba
//  Complexity: Medium
//  Phase B / Algorithmist
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DotScale, y=ScanSpeed, z=Separation, w=Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

fn grid(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
    let s = sin(angle);
    let c = cos(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let st = (rot * uv) * scale;
    return (sin(st.x) * sin(st.y)) * 0.5 + 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass amplifies dot density and scan speed, treble boosts brightness
    let dotScale   = mix(50.0, 400.0, u.zoom_params.x) * (1.0 + bass * 0.2);
    let scanSpeed  = u.zoom_params.y * 2.0 * (1.0 + bass * 0.4);
    let sep        = u.zoom_params.z * 0.05;
    let brightness = u.zoom_params.w * 2.0 * (1.0 + treble * 0.2);

    // Scanline
    let scanY = fract(time * scanSpeed * 0.5);
    let scanDist = abs(uv.y - scanY);
    let scanIntensity = exp(-scanDist * scanDist * 90.0);

    // Sample texture with chromatic separation
    let texR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( sep,  sep), 0.0).r;
    let texG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let texB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>( sep,  sep), 0.0).b;

    // Canonical CMYK screen angles
    let patR = grid(uv, 15.0  * PI / 180.0, dotScale);
    let patG = grid(uv, 75.0  * PI / 180.0, dotScale);
    let patB = grid(uv,  0.0,                dotScale);
    let patK = grid(uv, 45.0  * PI / 180.0, dotScale * 1.05);

    let boost = scanIntensity * 0.4;
    let r = step(patR, texR * brightness + boost);
    let g = step(patG, texG * brightness + boost);
    let b = step(patB, texB * brightness + boost);
    let k = step(patK, dot(vec3<f32>(texR, texG, texB), vec3<f32>(0.299, 0.587, 0.114)) * brightness + boost);

    // Cyber-tinted
    let cyan    = vec3<f32>(0.0, 0.85, 1.0) * r;
    let magenta = vec3<f32>(1.0, 0.0, 0.7)  * g;
    let yellow  = vec3<f32>(1.0, 0.85, 0.0) * b;
    let halftone = (cyan + magenta + yellow) * (1.0 - k * 0.4);

    // Plasma palette tint along scan stripe
    let palIdx = u32(clamp((scanY + time * 0.05) * 255.0, 0.0, 255.0));
    let scanTint = plasmaBuffer[palIdx % 256u].rgb;
    let finalColor = halftone + scanTint * scanIntensity * 0.4;

    // Semantic alpha
    let coverage = (r + g + b) / 3.0;
    let alpha = clamp(coverage * 0.6 + scanIntensity * 0.3 + 0.1, 0.0, 1.0);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
```
