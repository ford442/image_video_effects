# Shader Upgrade Task: `gen-ifs-fractal-flame`

## Metadata
- **Shader ID**: gen-ifs-fractal-flame
- **Agent Role**: Interactivist
- **Current Size**: 1423 bytes
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
//  IFS Fractal Flame
//  Category: generative
//  Features: procedural, fractal, ifs, flame, audio-reactive, mouse-driven,
//            chromatic-aberration, aces-tonemap, temporal-feedback, depth-aware
//  Complexity: High
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
  return fract(vec2<f32>(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453,
                         sin(dot(p, vec2<f32>(269.5, 183.3))) * 43758.5453));
}

fn varSinusoidal(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(sin(p.x), sin(p.y));
}

fn varSpherical(p: vec2<f32>) -> vec2<f32> {
  let r2 = dot(p, p) + 1e-6;
  return p / r2;
}

fn varSwirl(p: vec2<f32>) -> vec2<f32> {
  let r2 = dot(p, p);
  let c = cos(r2);
  let s = sin(r2);
  return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn flamePalette(t: f32) -> vec3<f32> {
  let c0 = vec3<f32>(0.05, 0.0, 0.02);
  let c1 = vec3<f32>(0.6, 0.0, 0.0);
  let c2 = vec3<f32>(1.0, 0.4, 0.0);
  let c3 = vec3<f32>(1.0, 0.9, 0.2);
  let c4 = vec3<f32>(1.0, 1.0, 0.95);
  if t < 0.25 { return mix(c0, c1, t * 4.0); }
  if t < 0.5  { return mix(c1, c2, (t - 0.25) * 4.0); }
  if t < 0.75 { return mix(c2, c3, (t - 0.5) * 4.0); }
  return mix(c3, c4, (t - 0.75) * 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;

  let iterations = i32(mix(24.0, 56.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
  let spread = mix(0.8, 2.2, u.zoom_params.y);
  let heat = mix(0.5, 2.0, u.zoom_params.z);
  let caAmt = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * spread;

  // Mouse attracts IFS center
  let mAttr = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * spread * 0.4;
  p = p - mAttr * 0.3;

  // Temporal feedback seeds subtle drift
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  p = p + prev.xy * 0.015;

  // Depth from readDepthTexture
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = clamp(depthSample * 1.5, 0.1, 1.0);

  // 4 affine transforms with probabilistic feel via hash
  var accum = vec2<f32>(0.0);
  var density = 0.0;

  for (var i = 0; i < iterations; i = i + 1) {
    let seed = hash2(p + vec2<f32>(f32(i) * 1.618, time * 0.05));
    let idx = i % 4;

    var tp = p;
    if idx == 0 {
      tp = vec2<f32>(0.5 * p.x + 0.0, 0.5 * p.y + 0.25);
    } else if idx == 1 {
      tp = vec2<f32>(0.5 * p.x + 0.433, 0.5 * p.y + 0.25);
    } else if idx == 2 {
      tp = vec2<f32>(0.5 * p.x - 0.433, 0.5 * p.y + 0.25);
    } else {
      tp = vec2<f32>(0.5 * p.x, 0.5 * p.y - 0.5);
    }

    // Non-linear variation selected by seed
    let varSel = seed.x;
    if varSel < 0.33 {
      tp = varSinusoidal(tp * (1.0 + bass * 0.2));
    } else if varSel < 0.66 {
      tp = varSpherical(tp);
    } else {
      tp = varSwirl(tp);
    }

    p = tp;
    let d = length(p);
    density = density + exp(-d * d * 8.0);
    accum = accum + p;
  }

  density = density / f32(iterations) * heat;
  let flameTemp = clamp(density * 3.0, 0.0, 1.0);
  var color = flamePalette(flameTemp) * (0.3 + density * 2.5);

  // HDR bloom on dense regions
  color = color + flamePalette(flameTemp * 0.7) * density * density * 0.8;

  // Chromatic aberration on transform boundaries
  let caMask = smoothstep(0.3, 0.7, density) * caAmt;
  let caR = acesToneMap(vec3<f32>(color.r * 1.15, color.g * 0.95, color.b * 0.85) * 1.5);
  let caB = acesToneMap(vec3<f32>(color.r * 0.85, color.g * 0.95, color.b * 1.15) * 1.5);
  color = mix(acesToneMap(color * 1.5), mix(caR, caB, caMask), caMask * 0.4);

  // Alpha: attractor_density × flame_temperature × depth
  let alpha = clamp(density * flameTemp * depthFactor, 0.0, 1.0);

  // Depth output
  let depthOut = clamp(1.0 - flameTemp * 0.8, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}

```

## Current JSON Definition
```json
{
  "id": "gen-ifs-fractal-flame",
  "name": "IFS Fractal Flame",
  "url": "shaders/gen-ifs-fractal-flame.wgsl",
  "category": "generative",
  "description": "Iterated Function System fractal flame with probabilistic affine transforms, non-linear variations, and flame palette rendering. Features HDR bloom, chromatic aberration, and audio-reactive morphing.",
  "tags": [
    "fractal",
    "flame",
    "ifs",
    "organic",
    "fire",
    "bloom",
    "abstract"
  ],
  "features": [
    "audio-reactive",
    "mouse-driven",
    "temporal",
    "depth-aware"
  ],
  "params": [
    {
      "id": "iterations",
      "name": "Iterations",
      "default": 0.35,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "spread",
      "name": "Spread",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "heat",
      "name": "Heat",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "chromatic",
      "name": "Chromatic Aberration",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
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
