# Shader Upgrade Task: `gen-metaball-soft-body`

## Metadata
- **Shader ID**: gen-metaball-soft-body
- **Agent Role**: Interactivist
- **Current Size**: 1321 bytes
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
//  Metaball Soft Body - Organic liquid-metal implicit surfaces
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, temporal, mouse-driven
//  Complexity: Medium
//  Created: 2026-05-30
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

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn fieldAt(p: vec2<f32>, time: f32, bass: f32, mouseUV: vec2<f32>, mouseDown: f32, nBalls: i32) -> f32 {
  var f = 0.0;
  for (var i: i32 = 0; i < 6; i = i + 1) {
    if (i >= nBalls) { break; }
    let fi = f32(i);
    let seed = fi * 17.31;
    let orbitR = 0.2 + hash12(vec2<f32>(seed, 0.0)) * 0.25;
    let spd = 0.25 + hash12(vec2<f32>(seed, 1.0)) * 0.4;
    let phase = seed * 0.7 + time * spd;
    let cx = cos(phase) * orbitR + cos(time * 0.13 + fi) * 0.08;
    let cy = sin(phase * 0.83 + 1.3) * orbitR + sin(time * 0.11 + fi) * 0.08;
    let toMouse = (mouseUV - 0.5) * 2.0 - vec2<f32>(cx, cy);
    let pos = vec2<f32>(cx, cy) + mouseDown * toMouse * 0.25;
    let r = 0.1 + hash12(vec2<f32>(seed, 2.0)) * 0.06 + bass * 0.025;
    let d2 = dot(p - pos, p - pos);
    f = f + (r * r) / (d2 + 0.00005);
  }
  return f;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = step(0.5, u.zoom_config.w);

  let nBalls = 3 + i32(u.zoom_params.x * 3.0);
  let roughness = u.zoom_params.y;
  let metalShift = u.zoom_params.z;
  let causticStr = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let dx = 0.003;
  let f = fieldAt(p, time, bass, mouseUV, mouseDown, nBalls);
  let fx = fieldAt(p + vec2<f32>(dx, 0.0), time, bass, mouseUV, mouseDown, nBalls);
  let fy = fieldAt(p + vec2<f32>(0.0, dx), time, bass, mouseUV, mouseDown, nBalls);

  let grad = vec2<f32>(fx - f, fy - f) / dx;
  let gradLen = length(grad);
  let normal = grad / max(gradLen, 0.001);
  let view = normalize(vec2<f32>(0.0, 0.0) - p);
  let fresnel = pow(1.0 - max(dot(normal, view), 0.0), 3.0);

  let surfaceDist = abs(f - 1.0);
  let surfaceMask = 1.0 - smoothstep(0.0, 0.15, surfaceDist);
  let insideMask = step(1.0, f);

  let lightDir = normalize(vec2<f32>(0.5, 0.8));
  let spec = pow(max(dot(normal, normalize(lightDir + view)), 0.0), mix(32.0, 8.0, roughness));

  let baseMetal = mix(vec3<f32>(0.75, 0.78, 0.82), vec3<f32>(0.9, 0.7, 0.4), metalShift);
  let subSurf = vec3<f32>(0.9, 0.4, 0.2) * insideMask * 0.4;

  let caustic = vec3<f32>(0.2, 0.6, 1.0) * gradLen * causticStr * 0.15;
  let mergeGlow = vec3<f32>(1.0, 0.8, 0.5) * max(f - 1.5, 0.0) * 0.3;

  var generatedColor = vec3<f32>(0.01, 0.01, 0.015);
  generatedColor = generatedColor + baseMetal * surfaceMask * 0.6;
  generatedColor = generatedColor + vec3<f32>(1.0, 0.95, 0.9) * spec * surfaceMask;
  generatedColor = generatedColor + baseMetal * fresnel * surfaceMask * 0.5;
  generatedColor = generatedColor + subSurf;
  generatedColor = generatedColor + caustic;
  generatedColor = generatedColor + mergeGlow;

  generatedColor = acesToneMapping(generatedColor * 1.4);

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  let fieldAlpha = clamp(f * surfaceMask * 0.5 + surfaceMask * 0.3, 0.0, 0.9) * depth;
  let alpha = fieldAlpha * (1.0 + fresnel * 0.3);

  let finalColor = mix(inputColor.rgb, generatedColor, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(surfaceMask * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(generatedColor, alpha));
}

```

## Current JSON Definition
```json
{
  "id": "gen-metaball-soft-body",
  "name": "Metaball Soft Body",
  "url": "shaders/gen-metaball-soft-body.wgsl",
  "description": "Organic liquid-metal metaballs with coupled harmonic oscillators, Fresnel reflections, subsurface scattering, and chromatic caustics in merge regions. Bass pulsates radii, mouse attracts centers.",
  "features": [
    "mouse-driven",
    "depth-aware",
    "upgraded-rgba",
    "audio-reactive",
    "temporal"
  ],
  "tags": [
    "procedural",
    "generative",
    "metaballs",
    "liquid-metal",
    "organic",
    "implicit-surface",
    "audio-reactive",
    "vj"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Ball Count",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Surface Roughness",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Metal Hue",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Caustic Strength",
      "default": 0.5,
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
