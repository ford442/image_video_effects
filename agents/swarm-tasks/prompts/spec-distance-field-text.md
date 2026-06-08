# Shader Upgrade Task: `spec-distance-field-text`

## Metadata
- **Shader ID**: spec-distance-field-text
- **Agent Role**: Optimizer
- **Current Size**: 1247 bytes
- **Target Line Count**: ~180 lines
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
//  spec-distance-field-text
//  Category: generative
//  Features: SDF, procedural-text, glyph, signed-distance-field
//  Complexity: Medium
//  Chunks From: none
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  SDF-Based Procedural Text/Glyph Overlay
//  Generates symbolic glyphs as Signed Distance Fields directly in
//  the shader. Enables infinitely smooth scaling, glowing edges,
//  drop shadows, and outline effects from a single distance value.
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

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdCircle(p: vec2<f32>, c: vec2<f32>, r: f32) -> f32 {
    return length(p - c) - r;
}

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Procedural glyph: abstract rune/symbol composed of geometric primitives
fn sdGlyph(p: vec2<f32>, glyphIndex: i32, scale: f32) -> f32 {
    let sp = p / scale;
    var d = 1000.0;

    if (glyphIndex == 0) {
        // Triangle with internal line
        d = min(d, sdSegment(sp, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, -0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(0.3, -0.3), vec2<f32>(0.0, 0.4)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, 0.4), vec2<f32>(-0.3, -0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.15)));
    } else if (glyphIndex == 1) {
        // Circle with cross
        d = min(d, abs(sdCircle(sp, vec2<f32>(0.0), 0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(-0.3, 0.0), vec2<f32>(0.3, 0.0)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.3)));
    } else if (glyphIndex == 2) {
        // Square with diagonal
        d = min(d, sdBox(sp, vec2<f32>(0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, 0.3)));
    } else if (glyphIndex == 3) {
        // Hexagon approximation
        for (var i = 0; i < 6; i = i + 1) {
            let a1 = f32(i) * 1.0472;
            let a2 = f32(i + 1) * 1.0472;
            let p1 = vec2<f32>(cos(a1), sin(a1)) * 0.3;
            let p2 = vec2<f32>(cos(a2), sin(a2)) * 0.3;
            d = min(d, sdSegment(sp, p1, p2));
        }
        d = min(d, sdCircle(sp, vec2<f32>(0.0), 0.1));
    } else {
        // Diamond with dot
        d = min(d, sdSegment(sp, vec2<f32>(0.0, 0.35), vec2<f32>(0.25, 0.0)));
        d = min(d, sdSegment(sp, vec2<f32>(0.25, 0.0), vec2<f32>(0.0, -0.35)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, -0.35), vec2<f32>(-0.25, 0.0)));
        d = min(d, sdSegment(sp, vec2<f32>(-0.25, 0.0), vec2<f32>(0.0, 0.35)));
        d = min(d, sdCircle(sp, vec2<f32>(0.0), 0.06));
    }

    return d * scale;
}

// Grid of glyphs
fn sdGlyphGrid(p: vec2<f32>, gridScale: f32, time: f32) -> f32 {
    let cell = floor(p * gridScale);
    let local = fract(p * gridScale) - 0.5;
    let glyphIdx = i32(fract(sin(dot(cell, vec2<f32>(12.9898, 78.233))) * 43758.5453) * 5.0);
    let pulse = 1.0 + sin(time * 2.0 + cell.x * 3.0 + cell.y * 2.0) * 0.1;
    return sdGlyph(local, glyphIdx, pulse / gridScale);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let glyphScale = mix(2.0, 12.0, u.zoom_params.x);
    let glyphWidth = mix(0.003, 0.02, u.zoom_params.y);
    let glowRadius = mix(0.0, 0.05, u.zoom_params.z);
    let overlayMix = mix(0.0, 1.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Base image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Glyph SDF
    let centeredUV = (uv - 0.5) * 2.0;
    var d = sdGlyphGrid(centeredUV, glyphScale, time);

    // Mouse reveals glyphs
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let reveal = exp(-mouseDist * mouseDist * 800.0);
        d -= reveal * 0.02; // Bring glyphs closer near mouse
    }

    // SDF rendering: smooth anti-aliased glyph
    let glyphMask = 1.0 - smoothstep(-glyphWidth, glyphWidth, d);

    // Outer glow
    let outerGlow = exp(-d * d / (glowRadius * glowRadius + 0.0001)) * (1.0 - glyphMask);

    // Drop shadow offset
    let shadowD = sdGlyphGrid(centeredUV - vec2<f32>(0.01, 0.015), glyphScale, time);
    let shadowMask = 1.0 - smoothstep(-glyphWidth * 2.0, glyphWidth * 2.0, shadowD);

    // Glyph color cycling
    let hue = time * 0.1 + centeredUV.x * 0.2 + centeredUV.y * 0.15;
    let glyphColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    let glowColor = glyphColor * 1.5;
    let shadowColor = vec3<f32>(0.0, 0.0, 0.1);

    // Composite
    var outColor = baseColor;
    outColor = mix(outColor, outColor * 0.7 + shadowColor * 0.3, shadowMask * 0.4 * overlayMix);
    outColor = mix(outColor, outColor + glowColor * outerGlow, outerGlow * overlayMix);
    outColor = mix(outColor, glyphColor, glyphMask * overlayMix);

    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, glyphMask + outerGlow));
    textureStore(dataTextureA, gid.xy, vec4<f32>(glyphColor, d));
}

```

## Current JSON Definition
```json
{
  "id": "spec-distance-field-text",
  "name": "Distance Field Text",
  "url": "shaders/spec-distance-field-text.wgsl",
  "description": "SDF-based procedural glyph overlay. Generates abstract runes and symbols as signed distance fields with infinitely smooth scaling, glowing edges, drop shadows, and chromatic cycling.",
  "tags": [
    "SDF",
    "distance-field",
    "procedural-text",
    "glyph",
    "overlay",
    "runes"
  ],
  "features": [
    "SDF",
    "procedural-text",
    "mouse-driven"
  ],
  "params": [
    {
      "id": "glyph_scale",
      "name": "Glyph Scale",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "glyph_width",
      "name": "Glyph Width",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "glow",
      "name": "Glow Radius",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "overlay",
      "name": "Overlay Mix",
      "default": 0.7,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.5
}

```

---

## Agent Specialization
# Agent Role: The Optimizer

## Identity
You are **The Optimizer**, a shader architect focused on performance, elegance, and pipeline integration.

## Upgrade Toolkit

### Performance Techniques
- Brute force → Early exit conditions
- Full resolution → Quarter-res blur + full-res combine
- Per-pixel pseudo-random → **Blue noise or Halton sequence** (same cost, less banding)
- Redundant texture samples → Bilinear LOD
- Nested loops → Unrolled small kernels
- Expensive trig → Precomputed or polynomial approximations:
  ```wgsl
  // Fast atan2 approximation (max error ~0.0015 rad)
  fn fast_atan2(y: f32, x: f32) -> f32 {
      let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
      let s = a * a;
      var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
      if (abs(y) > abs(x)) { r = 1.5707963 - r; }
      if (x < 0.0) { r = 3.1415927 - r; }
      if (y < 0.0) { r = -r; }
      return r;
  }
  // Fast exp approximation
  fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }
  ```

#### 7-tap hex bokeh kernel (perceptually equals 19-tap circular at lower cost)
```wgsl
const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>( 0.0,  0.0),
    vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
    vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);
```
Use for radial-blur, DOF, and glow shaders. Scale each tap by `radius / res` before sampling `readTexture`.

#### Anti-moiré LOD bias for procedural noise
```wgsl
let lod = clamp(log2(max(fwidth(uv).x, fwidth(uv).y) * cell_freq), 0.0, 4.0);
let p = uv * (cell_freq * exp2(-lod));
```
Kills the shimmer that plagues high-frequency procedural patterns (fractal / kaleidoscope shaders) when zoomed out. `cell_freq` is the base tile frequency.

### Workgroup Shared Memory (tiling pattern for blur/filter kernels)
```wgsl
var<workgroup> tile: array<array<vec4<f32>, 18>, 18>; // 16x16 + 1px border
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>) {
    // Load tile including borders, then sync
    tile[lid.y+1][lid.x+1] = textureSampleLevel(readTexture, u_sampler,
        vec2<f32>(gid.xy) / vec2<f32>(u.config.zw), 0.0);
    workgroupBarrier();
    // All accesses to tile[] now L1-cached — no global texture reads in hot loop
}
```

### Code Elegance
- Magic numbers → Named constants (see Algorithmist for PI/TAU/PHI/etc.)
- Duplicated code → Helper functions
- Long functions → Logical sections with comments
- Hard-coded params → Uniform-based tuning via `zoom_params`
- GPU-unfriendly ops → Precomputed lookups

### Pipeline Integration
- Standalone → Designed for slot chaining
- No feedback → Uses dataTextureA/B for state
- LDR only → HDR output ready for tone map
- Single pass → Multi-pass decomposition hint
- Fixed quality → Level-of-detail scaling

### Post-Process Ready
- Expose bloom threshold via alpha channel (`alpha = bloom_weight`)
- Tag as "expects pp-tone-map" if HDR
- Document slot recommendations
- Provide quality presets (low/medium/high)

## Quality Checklist
- [ ] No per-pixel branching on uniforms
- [ ] Texture samples minimized (caching used)
- [ ] Workgroup size optimized (16x16 for Pixelocity)
- [ ] Early exit for sky/background pixels
- [ ] LOD quality scaling based on frame time
- [ ] Anti-moiré LOD bias applied for high-frequency procedural patterns
- [ ] Hex bokeh kernel used in place of naive circular sampling where applicable

## Output Rules
- Keep the original "soul" of the shader while making it production-ready.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- Preserve or enhance RGBA channel usage.
- Add JSON params if new tunable values are introduced (max 4 params mapped to zoom_params).

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 180 lines (±20%).
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
