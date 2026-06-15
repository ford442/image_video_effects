# Shader Upgrade Task: `stereoscopic-3d`

## Metadata
- **Shader ID**: stereoscopic-3d
- **Agent Role**: Optimizer
- **Current Size**: 3386 bytes
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
//  Stereoscopic 3D
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
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

fn bass_env(prev: f32, raw: f32) -> f32 {
    let k = select(0.15, 0.8, raw > prev);
    return mix(prev, raw, k);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Read persistent state from previous frame (dataTextureC)
    let prev = textureLoad(dataTextureC, coords, 0);

    // Smoothed audio envelope eliminates raw bass strobe
    let rawBass = bass;
    let envBass = bass_env(prev.r, rawBass);

    // Spring-damper mouse follow with per-pixel exponential smoothing
    let rawMouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let snap = select(0.06, 0.3, mouseDown > 0.5);
    let smoothMouse = mix(prev.gb, rawMouse, vec2<f32>(snap));

    // Params
    let maxSep = u.zoom_params.x * 0.05;
    let focusOffset = u.zoom_params.y;
    let glitchStr = u.zoom_params.z;
    let lensRot = (u.zoom_params.w - 0.5) * 0.4;

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Mouse affects convergence bias (X) and focal plane (Y)
    let mouseBias = (smoothMouse.x - 0.5) * 2.0;
    let focalWarp = (smoothMouse.y - 0.5) * 0.3;
    let sceneDepth = (uv.y - focusOffset + focalWarp) + mouseBias;

    // Beat-reactive separation with click boost
    let clickBoost = select(1.0, 1.3, mouseDown > 0.5);
    let audioPulse = 1.0 + envBass * 0.4 * clickBoost;
    var sepOffset = vec2<f32>(sceneDepth * maxSep * audioPulse, 0.0);

    // Glitch with envelope-driven amplitude
    let jitter = sin(uv.y * 200.0 + time * 30.0) * cos(time * 15.0);
    let block = floor(uv.y * 20.0);
    let blockNoise = fract(sin(block * 12.9898 + time) * 43758.5453);
    let glitchFactor = (jitter * 0.5 + blockNoise * 0.5) * (1.0 + envBass * 3.0);
    sepOffset = vec2<f32>(sepOffset.x + glitchFactor * glitchStr * 0.02, sepOffset.y);

    // Rotation: param + mouse-driven nudge
    let rot = lensRot + smoothMouse.x * 0.15 + (smoothMouse.y - 0.5) * 0.1;
    let c = cos(rot);
    let s = sin(rot);
    sepOffset = vec2<f32>(sepOffset.x * c - sepOffset.y * s, sepOffset.x * s + sepOffset.y * c);

    // Temporal feedback trails: ghost offset from previous intensity
    let prevIntensity = prev.a;
    let ghost = prevIntensity * 0.003;
    let redUV = clamp(uv - sepOffset - vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let cyanUV = clamp(uv + sepOffset + vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let redColor = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
    let cyanColor = textureSampleLevel(readTexture, u_sampler, cyanUV, 0.0).gb;
    var finalColor = vec3<f32>(redColor, cyanColor.x, cyanColor.y);

    // Treble sparkle on highlights + mids color warmth
    finalColor = finalColor + vec3<f32>(treble * 0.08 + mids * 0.03, treble * 0.04 + mids * 0.02, treble * 0.12);

    // Smooth intensity for temporal trail decay
    let currentIntensity = clamp(abs(sceneDepth) * 2.0 + length(sepOffset) * 20.0 + glitchStr * 0.5, 0.0, 1.0);
    let trailIntensity = mix(prevIntensity, currentIntensity, 0.12);
    let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));

    // Audio-reactive color boost
    finalColor = finalColor * (1.0 + envBass * 0.25 + mids * 0.1);

    // Alpha encodes trail age / interaction intensity
    let alpha = clamp(mix(0.6, 1.0, trailIntensity * 0.5 + luminance * 0.3 + envBass * 0.2), 0.0, 1.0);

    let outColor = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, global_id.xy, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "stereoscopic-3d",
  "name": "Stereoscopic 3D",
  "url": "shaders/stereoscopic-3d.wgsl",
  "description": "Interactive Anaglyph 3D effect. Mouse X/Y controls convergence bias and focal plane with spring-damped smoothing. Audio bass drives smoothed separation pulse and glitch amplitude. Temporal feedback creates ghost trails from previous intensity.",
  "params": [
    {
      "id": "separation",
      "name": "Max Separation",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "focus",
      "name": "Focus Offset",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "glitch",
      "name": "Glitch Jitter",
      "default": 0,
      "min": 0,
      "max": 1
    },
    {
      "id": "rotation",
      "name": "Lens Rotation",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "temporal",
    "upgraded-rgba"
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "audio-reactive",
    "anaglyph",
    "3d",
    "temporal",
    "feedback",
    "trails"
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
