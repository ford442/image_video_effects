# Shader Upgrade Task: `hyperbolic-crystal-symbiosis`

## Metadata
- **Shader ID**: hyperbolic-crystal-symbiosis
- **Agent Role**: Interactivist
- **Current Size**: 1852 bytes
- **Target Line Count**: ~190 lines
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
//  Hyperbolic Crystal Symbiosis v2
//  Category: generative
//  Features: poincare-disk, geodesic-voronoi, gray-scott,
//            iridescent-facets, audio-driven, mouse-warp
//  Complexity: Very High
//  Chunks From: hyperbolic geometry + reaction-diffusion + ACES tm
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

// Poincaré disk model: Euclidean point to hyperbolic metric
fn poincareMetric(uv: vec2<f32>, center: vec2<f32>) -> f32 {
  let d = uv - center;
  let r2 = dot(d, d);
  let r = clamp(sqrt(r2), 0.0, 0.999);
  return atanh(r) * 2.0;
}

// Geodesic distance between two points in Poincaré disk
fn hyperbolicDist(a: vec2<f32>, b: vec2<f32>, center: vec2<f32>) -> f32 {
  let da = a - center;
  let db = b - center;
  let ra2 = clamp(dot(da, da), 0.0, 0.999);
  let rb2 = clamp(dot(db, db), 0.0, 0.999);
  let delta = 2.0 * ra2 * rb2;
  let num = ra2 + rb2 - 2.0 * dot(da, db);
  let denom = (1.0 - ra2) * (1.0 - rb2);
  let arg = clamp(1.0 + 2.0 * num / max(denom, 0.001), 1.0, 1000.0);
  return acosh(arg) * 0.3;
}

fn iridescentFacet(theta: f32, boundary: f32) -> vec3<f32> {
  let t = theta * 6.283185;
  return vec3<f32>(
    0.5 + 0.5 * cos(t + boundary * 4.0),
    0.5 + 0.5 * cos(t + boundary * 7.0 + 2.1),
    0.5 + 0.5 * cos(t + boundary * 10.0 + 4.2)
  ) * (0.6 + boundary * 0.8);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.35;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let warpStrength = mouseDown * p4 * 0.35;
  let diskCenter = mix(vec2<f32>(0.5), mouse, warpStrength);
  let curvature = mix(0.0, 1.0, clamp(p1 + mids * 0.5 - 0.25, 0.0, 1.0));
  let isEuclidean = curvature < 0.15;
  let isHyperbolic = curvature > 0.65;

  let seeds = array<vec2<f32>, 5>(
    vec2<f32>(0.3, 0.35), vec2<f32>(0.7, 0.3), vec2<f32>(0.5, 0.7),
    vec2<f32>(0.2, 0.65), vec2<f32>(0.8, 0.6)
  );

  var minDist = 999.0;
  var secondMin = 999.0;
  var nearest = 0;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let d = select(hyperbolicDist(uv, seeds[i], diskCenter), length(uv - seeds[i]), isEuclidean);
    if (d < minDist) { secondMin = minDist; minDist = d; nearest = i; }
    else if (d < secondMin) { secondMin = d; }
  }

  let growthRate = 0.8 + bass * 2.0 + p2 * 1.5;
  let facetPhase = f32(nearest) * 1.2566 + time * (0.5 + growthRate * 0.3);
  let boundary = secondMin - minDist;
  let edge = smoothstep(0.12, 0.0, boundary);
  let triple = smoothstep(0.04, 0.0, boundary) * (1.0 - smoothstep(0.15, 0.25, minDist));

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let uField = prev.r;
  let vField = prev.g;

  let ps = 1.0 / res;
  let rx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let lx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let uy = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let dy = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let lapU = rx.r + lx.r + uy.r + dy.r - 4.0 * uField;
  let lapV = rx.g + lx.g + uy.g + dy.g - 4.0 * vField;

  let Du = select(0.18, 0.26, isHyperbolic);
  let Dv = select(0.09, 0.13, isHyperbolic);
  let F = 0.03 + treble * 0.02;
  let K = 0.056 + p3 * 0.02;
  let uv2 = uField * vField * vField;

  let newU = clamp(uField + Du * lapU - uv2 + F * (1.0 - uField), 0.0, 1.0);
  let newV = clamp(vField + Dv * lapV + uv2 - (F + K) * vField, 0.0, 1.0);

  textureStore(dataTextureA, gid.xy, vec4<f32>(newU, newV, prev.r, 0.0));

  let crystalPurity = smoothstep(0.1, 0.55, newU);
  let centrality = smoothstep(0.4, 0.0, minDist);
  let irid = iridescentFacet(facetPhase + minDist * 3.0, edge) * edge * 1.2;
  let domainCol = mix(vec3<f32>(0.15, 0.45, 0.75), vec3<f32>(0.85, 0.55, 0.25), f32(nearest % 2));
  let depth = smoothstep(0.0, 1.0, minDist * 2.0);
  let shade = domainCol * (0.4 + depth * 0.6 + crystalPurity * 0.5);
  let sparkle = hash12(uv * 200.0 + time * 3.0) * edge * treble * 1.5;
  let bloom = triple * vec3<f32>(1.0, 0.9, 0.7) * 2.0;
  let tone = acesToneMap((shade + irid + bloom + vec3<f32>(sparkle)) * (0.85 + p1 * 0.25));

  let alpha = clamp(centrality * 0.7 + crystalPurity * 0.5 + depth * 0.3 + edge * 0.4, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(crystalPurity * depth * 0.7, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "hyperbolic-crystal-symbiosis",
  "name": "Hyperbolic Crystal Symbiosis",
  "url": "shaders/hyperbolic-crystal-symbiosis.wgsl",
  "category": "generative",
  "description": "Voronoi crystal facets on a true Poincaré disk with geodesic distance and Gray-Scott reaction-diffusion. Iridescent thin-film coloring on facet edges with HDR bloom at triple junctions. Bass drives crystal growth, mids morph between hyperbolic/parabolic/Euclidean curvature, treble adds sparkle. Mouse warps the disk center.",
  "features": [
    "poincare-disk",
    "geodesic-voronoi",
    "gray-scott",
    "iridescent-facets",
    "audio-driven",
    "mouse-warp",
    "temporal"
  ],
  "tags": [
    "hyperbolic",
    "crystalline",
    "symbiosis",
    "geometric",
    "audio-reactive",
    "abstract",
    "iridescent",
    "reaction-diffusion"
  ],
  "params": [
    {
      "id": "curvature",
      "name": "Base Curvature",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Strength of the hyperbolic distortion"
    },
    {
      "id": "competition",
      "name": "Species Tension",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "How strongly the two crystal types compete"
    },
    {
      "id": "symbiosis",
      "name": "Symbiotic Tendency",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Encourages beautiful blending between species"
    },
    {
      "id": "mousePower",
      "name": "Mouse Curvature Power",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "How strongly the mouse warps local geometry"
    }
  ]
}

```

---

## Agent Specialization
# Agent Role: The Interactivist

## Identity
You are **The Interactivist**, a shader architect focused on input reactivity, feedback loops, and emergent behavior.

## Upgrade Toolkit

### Mouse Interaction
- Position tracking → Gravity wells / attractors
- Click events → Spawn bursts / shockwaves
- Velocity tracking → Motion blur trails
- Multi-touch → Multi-agent systems

### Audio Reactivity
- Bass pulse → Scale/brightness modulation
- Mid frequencies → Pattern morphing speed
- Treble → Sparkle/additive particles
- FFT buckets → Multi-band color splitting

### Video Feedback
- Static overlay → Optical flow distortion
- Fixed transparency → Alpha blending based on depth
- Simple masking → Luma-keyed particle spawn
- Direct color → Motion-vector advection

### Depth Integration
- 2D effects → Parallax depth separation
- Uniform blur → Depth-of-field bokeh
- Flat shading → Ambient occlusion darkening
- Screen space → Volumetric depth fog

#### Depth-aware compositing for slot-2/3 effects
```wgsl
let z   = textureLoad(readDepthTexture, gid.xy, 0).r;
let fog = 1.0 - exp(-z * u.zoom_params.z);   // exponential depth fog
let out = mix(srcColor, fxColor, fog);        // effect strengthens with depth
```
Keeps foreground subjects crisp while letting the effect "breathe" in the background — essential when this shader runs in slot 2 or 3 of the chain.

### Feedback Loops
- Single pass → Temporal accumulation
- Static state → Ping-pong buffer feedback (dataTextureA ↔ dataTextureB)
- Linear time → Recursive subdivision
- Fixed camera → Smooth follow with lag
- Direct value → Exponential smoothing: `smoothed = mix(smoothed, target, 0.05)`

### Emergent Dynamics Patterns
```wgsl
// Spring-damper for smooth mouse follow (prevents jitter)
fn spring(current: vec2<f32>, target: vec2<f32>, velocity: ptr<function,vec2<f32>>, k: f32, damping: f32, dt: f32) -> vec2<f32> {
    let force = (target - current) * k - *velocity * damping;
    *velocity = *velocity + force * dt;
    return current + *velocity * dt;
}

// Attractor / gravity well (mouse as gravitational source)
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;  // avoid singularity
    return normalize(d) * strength / dist2;
}

// Beat-reactive pulse with decay
fn beatPulse(bass: f32, decay: f32, time: f32) -> f32 {
    return bass * exp(-decay * fract(time * 2.0));  // 2Hz beat assumption
}
```

### Audio Binding Reference
```
plasmaBuffer[0].x = bass    (20–250 Hz)
plasmaBuffer[0].y = mids    (250–4000 Hz)
plasmaBuffer[0].z = treble  (4000–20000 Hz)
plasmaBuffer[0].w = overall RMS amplitude
```

#### Attack/release audio envelope (preferred over raw `plasmaBuffer[0].x`)
```wgsl
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
```
Store previous value in `dataTextureA.r` across frames. Eliminates the "strobe every frame" look that raw `plasmaBuffer[0].x` produces. Typical values: `attack = 0.8`, `release = 0.15`.

Reactive patterns:
- Bass → scale, brightness pulse, warp radius
- Mids → rotation speed, color shift, pattern morphing
- Treble → sparkle particles, grain, edge sharpness
- RMS → overall opacity, global scale breathing

## Quality Checklist
- [ ] Mouse affects at least 2 parameters
- [ ] Audio drives at least 1 visual element (use `bass_env` decay, not raw `plasmaBuffer[0].x`)
- [ ] Video input influences the effect
- [ ] Temporal feedback creates trails/smoothing
- [ ] Emergent behavior (not 1:1 input mapping)
- [ ] Alpha encodes interaction intensity or trail age

## Output Rules
- Keep the original "soul" of the shader while making it alive and reactive.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- `plasmaBuffer[0].x` = bass, `.y` = mids, `.z` = treble. Use them.
- `u.zoom_config.yz` = mouse position (0-1). `u.zoom_config.w` = mouse down.
- **Alpha must carry semantic meaning** — trail age, interaction intensity, or depth mask.

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 190 lines (±20%).
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
