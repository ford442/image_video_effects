# Shader Upgrade Task: `phase-memory-weave`

## Metadata
- **Shader ID**: phase-memory-weave
- **Agent Role**: Optimizer
- **Current Size**: 1824 bytes
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
//  Phase Memory Weave v2
//  Category: generative
//  Features: ginzburg-landau, allen-cahn, multi-scale-memory,
//            opalescent-interfaces, audio-driven, mouse-thermal
//  Complexity: Very High
//  Chunks From: phase-field + thin-film interference + ACES tm
//  Created: 2026-05-31
//  By: 4-Agent Upgrade Swarm
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn thinFilmIridescence(phase: f32, d: f32) -> vec3<f32> {
  let phi = phase * 6.283185;
  return vec3<f32>(
    0.5 + 0.5 * cos(phi + d * 3.0),
    0.5 + 0.5 * cos(phi + d * 5.0 + 1.0),
    0.5 + 0.5 * cos(phi + d * 7.0 + 2.5)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let clicks = u.config.y;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let cur = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let psiR = cur.r;
  let psiI = cur.g;
  let slowMem = cur.b;
  let rho2 = psiR * psiR + psiI * psiI;
  let rho = sqrt(rho2);
  let theta = atan2(psiI, psiR);

  let ps = 1.0 / res;
  let rx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let lx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let uy = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let dy = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let lapR = rx.r + lx.r + uy.r + dy.r - 4.0 * psiR;
  let lapI = rx.g + lx.g + uy.g + dy.g - 4.0 * psiI;

  let epsilon = 0.035 + p3 * 0.04;
  let mobility = 0.15 + mids * 0.6 + p2 * 0.4;
  let reaction = rho * (1.0 - rho2);
  let dR = lapR * epsilon - reaction * psiR;
  let dI = lapI * epsilon - reaction * psiI;

  // Exponential decay memory from single readable channel
  let memoryBlend = mix(psiR, slowMem, 0.6);
  let memStrength = 0.2 + p2 * 0.7;

  let newR = mix(psiR + dR * mobility, memoryBlend, memStrength * 0.08);
  let newI = mix(psiI + dI * mobility, theta * 0.1, memStrength * 0.03);

  var seedNoise = 0.0;
  if (bass > 0.55) {
    seedNoise = (hash12(uv * 37.0 + time * 0.2) - 0.5) * (bass - 0.55) * 0.4;
  }

  let capillary = sin(uv.x * 30.0 + time * 4.0) * cos(uv.y * 24.0 - time * 3.5) * treble * 0.06;
  let mouseDist = length(uv - mouse);
  let thermal = smoothstep(0.15, 0.0, mouseDist) * mouseDown * (1.0 + p4 * 2.0);
  let isHeat = fract(clicks * 0.5) > 0.25;
  let thermalEffect = select(-thermal * 0.9, thermal * 0.6, isHeat);

  let finalR = clamp(newR + seedNoise + capillary + thermalEffect, -1.2, 1.2);
  let finalI = newI + capillary * 0.5;
  let finalRho = sqrt(finalR * finalR + finalI * finalI);
  let finalTheta = atan2(finalI, finalR);

  let rhoNeighbors = sqrt(rx.r * rx.r + rx.g * rx.g) + sqrt(lx.r * lx.r + lx.g * lx.g)
                   + sqrt(uy.r * uy.r + uy.g * uy.g) + sqrt(dy.r * dy.r + dy.g * dy.g);
  let curvature = abs(rhoNeighbors - 4.0 * finalRho);

  // Write history: A stores current state, B stores slow memory backup
  let newSlow = mix(slowMem, finalR, 0.12);
  textureStore(dataTextureA, gid.xy, vec4<f32>(finalR, finalI, newSlow, 0.0));
  textureStore(dataTextureB, gid.xy, vec4<f32>(newSlow, finalTheta, curvature, 0.0));

  let irid = thinFilmIridescence(finalTheta, curvature * 5.0) * smoothstep(0.1, 0.4, curvature) * 0.8;
  let fluidMask = smoothstep(0.5, 0.2, finalRho);
  let crystalMask = smoothstep(0.3, 0.7, finalRho);
  let caustic = pow(sin(finalTheta * 8.0 + time) * 0.5 + 0.5, 3.0) * fluidMask;
  let subsurface = crystalMask * vec3<f32>(0.85, 0.82, 0.75) * (0.6 + finalRho * 0.5);

  let fluidCol = vec3<f32>(0.15, 0.35, 0.65) * (0.5 + caustic * 0.8);
  let crystalCol = vec3<f32>(0.92, 0.88, 0.72) * (0.5 + finalRho * 0.6);
  let baseCol = mix(fluidCol, crystalCol, crystalMask) + irid + subsurface;
  let tone = acesToneMap(baseCol * (0.7 + finalRho * 0.8) * (0.85 + p1 * 0.3));

  let alpha = clamp(finalRho * 0.9 + curvature * 0.5, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(finalRho * 0.6 + crystalMask * 0.2, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "phase-memory-weave",
  "name": "Phase Memory Weave",
  "url": "shaders/phase-memory-weave.wgsl",
  "category": "generative",
  "description": "Continuous Ginzburg-Landau order parameter with Allen-Cahn interface energy and exponential-decay memory kernel. Opalescent thin-film interference on phase boundaries with fluid caustics and crystalline subsurface scattering. Bass nucleates crystal seeds, mids control grain boundary mobility, treble adds capillary waves. Mouse deposits heat or cold based on click parity.",
  "features": [
    "ginzburg-landau",
    "allen-cahn",
    "multi-scale-memory",
    "opalescent-interfaces",
    "audio-driven",
    "mouse-thermal",
    "temporal"
  ],
  "tags": [
    "viscous",
    "memory",
    "phase",
    "material",
    "audio-reactive",
    "abstract",
    "opalescent",
    "caustics"
  ],
  "params": [
    {
      "id": "phase",
      "name": "Phase",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Fluid vs Crystalline state"
    },
    {
      "id": "memory",
      "name": "Memory Strength",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "How strongly the material remembers its history"
    },
    {
      "id": "chaos",
      "name": "Turbulence",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Adds chaotic movement in fluid state"
    },
    {
      "id": "mouseDisturbance",
      "name": "Mouse Disturbance",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "How strongly the mouse can force local phase changes"
    }
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
