# Shader Upgrade Task: `scanline-sorting`

## Metadata
- **Shader ID**: scanline-sorting
- **Agent Role**: Optimizer
- **Current Size**: 3363 bytes
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
//  Scanline Sorting
//  Category: interactive-mouse
//  Features: mouse-driven, sorting, audio-reactive, palette-mapped, chromatic-edge, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-01-01
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn luma_of(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

fn dimmer(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return select(b, a, step(luma_of(a), luma_of(b)) > 0.5);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sort_threshold   = clamp(u.zoom_params.x, 0.0, 1.0);
    let scan_width       = u.zoom_params.y * 0.2 * (1.0 + bass * 0.3);
    let scan_speed       = u.zoom_params.z;
    let direction_toggle = step(0.5, u.zoom_params.w);
    let mouseDown        = u.zoom_config.w;
    let mouse            = u.zoom_config.yz;

    let scan_pos = mix(mix(mouse.y, mouse.x, direction_toggle),
                       fract(time * scan_speed),
                       step(0.01, scan_speed));

    let coord_along = mix(uv.y, uv.x, direction_toggle);
    let dist_to_scan = abs(coord_along - scan_pos);
    let band_t = 1.0 - smoothstep(0.0, max(scan_width, 1e-4), dist_to_scan);

    let aspect = resolution.x / max(resolution.y, 1.0);
    let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let cursorBoost = exp(-dMouse * dMouse * 6.0) * (0.4 + mouseDown * 0.6);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var color = original.rgb;

    let luma = luma_of(color);
    let band_active = step(1e-4, band_t);
    let sort_strength = smoothstep(sort_threshold, 1.0, luma) * (20.0 + bass * 20.0 + mids * 10.0) * (1.0 + cursorBoost) * band_active;

    let pix = mix(vec2<f32>(0.0, -1.0 / resolution.y),
                  vec2<f32>(-1.0 / resolution.x, 0.0),
                  direction_toggle);
    let sample_pos = clamp(uv + pix * sort_strength, vec2<f32>(0.0), vec2<f32>(1.0));
    let neighbor = textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0).rgb;

    let sorted = dimmer(color, neighbor);
    color = mix(color, sorted, band_t);

    let ghost = (1.0 - band_t) * scan_width * 8.0;
    let r_uv = select(uv, sample_pos + pix * ghost, band_active > 0.5);
    let b_uv = select(uv, sample_pos - pix * ghost, band_active > 0.5);
    let r2 = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let b2 = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
    color = mix(color, vec3<f32>(r2, color.g, b2), band_t * 0.4);

    let pIdx = u32(clamp((luma + sort_strength * 0.005) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[pIdx].rgb;
    color = mix(color, color * (0.6 + palette * 0.8), band_t * 0.5);

    let lf = luma_of(color);
    let bloom = max(0.0, lf - 0.7) * 3.0;
    let alpha = clamp(0.55 + band_t * 0.35 + bloom * 0.5 + cursorBoost * 0.2 + treble * 0.05, 0.0, 1.0);

    let finalColor = vec4<f32>(color, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "scanline-sorting",
  "name": "Scanline Sorting",
  "url": "shaders/scanline-sorting.wgsl",
  "description": "Sorts pixels by luminance within a moving scanline band controlled by the mouse. Reacts to audio bass for intensified sorting.",
  "params": [
    {
      "id": "thresh",
      "name": "Sort Threshold",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "width",
      "name": "Scan Width",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Auto Speed",
      "default": 0,
      "min": 0,
      "max": 1
    },
    {
      "id": "dir",
      "name": "Dir (H/V)",
      "default": 0,
      "min": 0,
      "max": 1,
      "labels": [
        "Horizontal",
        "Vertical"
      ]
    }
  ],
  "features": [
    "mouse-driven",
    "sorting",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
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
