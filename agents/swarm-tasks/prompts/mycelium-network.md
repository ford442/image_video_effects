# Shader Upgrade Task: `mycelium-network`

## Metadata
- **Shader ID**: mycelium-network
- **Agent Role**: Optimizer
- **Current Size**: 1199 bytes
- **Target Line Count**: ~170 lines
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
//  Mycelium Network
//  Category: generative
//  Features: generative, audio-reactive, branching-network, pulsing-nutrients, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let networkDensity = u.zoom_params.x * 12.0 + 4.0;
    let branchAngle = u.zoom_params.y * 1.5;
    let pulseSpeed = u.zoom_params.z * 3.0;
    let glowIntensity = u.zoom_params.w;

    let p = uv * networkDensity;
    let cellId = floor(p);
    let cellUV = fract(p) - 0.5;

    var color = vec3<f32>(0.03, 0.02, 0.04);
    var glow = 0.0;

    // Central trunk + branches per cell
    let seed = cellId;
    let trunkDir = hash22(seed) - 0.5;
    let trunkLen = 0.3 + hash21(seed + vec2<f32>(1.0, 0.0)) * 0.4;
    let branchCount = 2 + i32(hash21(seed + vec2<f32>(2.0, 0.0)) * 3.0);

    // Trunk
    let trunkEnd = trunkDir * trunkLen;
    let toTrunk = cellUV;
    let trunkProj = clamp(dot(toTrunk, normalize(trunkEnd)), 0.0, trunkLen);
    let trunkClosest = normalize(trunkEnd) * trunkProj;
    let trunkDist = length(cellUV - trunkClosest);
    let trunkWidth = 0.015;
    let trunk = smoothstep(trunkWidth, 0.0, trunkDist);

    // Nutrient pulse along trunk
    let pulsePos = fract(time * pulseSpeed * 0.1 + hash21(seed + vec2<f32>(3.0, 0.0)));
    let pulseDist = abs(trunkProj / max(trunkLen, 0.001) - pulsePos);
    let pulse = smoothstep(0.1, 0.0, pulseDist) * (1.0 + bass * 2.0);

    color = color + vec3<f32>(0.4, 0.8, 0.5) * trunk * (0.3 + mids * 0.3);
    color = color + vec3<f32>(1.0, 0.9, 0.6) * pulse * trunk;
    glow = glow + trunk + pulse * 2.0;

    // Branches
    for (var bi = 0; bi < branchCount; bi = bi + 1) {
        let bf = f32(bi);
        let bAngle = atan2(trunkEnd.y, trunkEnd.x) + (bf - 1.0) * branchAngle;
        let bDir = vec2<f32>(cos(bAngle), sin(bAngle));
        let bLen = trunkLen * (0.4 + hash21(seed + vec2<f32>(bf + 4.0, 0.0)) * 0.4);
        let bOrigin = trunkClosest;
        let bProj = clamp(dot(cellUV - bOrigin, bDir), 0.0, bLen);
        let bClosest = bOrigin + bDir * bProj;
        let bDist = length(cellUV - bClosest);
        let bWidth = trunkWidth * 0.6;
        let branch = smoothstep(bWidth, 0.0, bDist);

        // Tip glow
        let tipDist = abs(bProj - bLen);
        let tipGlow = smoothstep(0.05, 0.0, tipDist) * (1.0 + treble);

        let bPulsePos = fract(time * pulseSpeed * 0.15 + bf * 0.3);
        let bPulseDist = abs(bProj / max(bLen, 0.001) - bPulsePos);
        let bPulse = smoothstep(0.08, 0.0, bPulseDist) * (1.0 + bass);

        color = color + vec3<f32>(0.3, 0.7, 0.4) * branch * 0.5;
        color = color + vec3<f32>(0.8, 1.0, 0.7) * tipGlow * branch * glowIntensity;
        color = color + vec3<f32>(1.0, 0.95, 0.7) * bPulse * branch;
        glow = glow + branch + tipGlow * 0.5 + bPulse;
    }

    // Spore clouds at intersections
    let spore = hash21(cellId + vec2<f32>(time * 0.1, 0.0));
    let sporeMask = step(0.97, spore) * smoothstep(0.3, 0.0, length(cellUV));
    color = color + vec3<f32>(0.6, 0.9, 0.7) * sporeMask * glowIntensity;
    glow = glow + sporeMask;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, prev.rgb * 0.92, 0.05 + bass * 0.01);

    let caStr = 0.003 * (1.0 + bass) + glow * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    let alpha = clamp(glow * 0.4 + 0.1 + bass * 0.05, 0.0, 1.0);
    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.3, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "mycelium-network",
  "name": "Mycelium Network",
  "category": "generative",
  "url": "shaders/mycelium-network.wgsl",
  "description": "Underground fungal hyphae network with pulsing nutrient flows traveling along branches. Audio triggers bright nutrient pulses.",
  "features": [
    "audio-reactive",
    "generative",
    "branching-network",
    "upgraded-rgba",
    "pulsing-nutrients"
  ],
  "params": [
    {
      "id": "density",
      "name": "Network Density",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "angle",
      "name": "Branch Angle",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "pulse",
      "name": "Pulse Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "glow",
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "generative",
    "mycelium",
    "fungal",
    "network",
    "branching",
    "nutrients",
    "pulse",
    "audio-reactive",
    "organic"
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
4. Ensure the upgraded shader is roughly 170 lines (±20%).
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
