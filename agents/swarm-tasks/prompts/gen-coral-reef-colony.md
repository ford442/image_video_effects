# Shader Upgrade Task: `gen-coral-reef-colony`

## Metadata
- **Shader ID**: gen-coral-reef-colony
- **Agent Role**: Interactivist
- **Current Size**: 1624 bytes
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
//  Coral Reef Colony
//  Category: generative
//  Features: coral, organic, generative, audio-reactive, mouse-interactive, semantic-alpha, simulation-like
//  Complexity: Very High
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (4-Agent Swarm Upgrade)
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

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let h = hash21(pp + vec2<f32>(f32(i) * 7.3, time * 0.01));
    v += a * h;
    pp = pp * 2.1 + vec2<f32>(3.2, 1.7);
    a *= 0.5;
  }
  return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let growth = u.zoom_params.x;
  let polypSize = u.zoom_params.y;
  let colorVariety = u.zoom_params.z;
  let mouseAttraction = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let depth = smoothstep(0.0, 1.0, uv.y);

  let nutrient = growth * (0.6 + bass * 0.8);
  let current = vec2<f32>(sin(time * 0.2 + mids * 2.0), cos(time * 0.15 - mids * 1.5)) * 0.3;
  let spawnPulse = step(0.82, treble);

  let colonyUV = uv * 6.0 + current * time * 0.08;
  let branchNoise = fbm(colonyUV, time);
  let branchAngle = branchNoise * 6.2831;

  let nodePos = fract(colonyUV) - 0.5;
  let rotNode = vec2<f32>(
    nodePos.x * cos(branchAngle) - nodePos.y * sin(branchAngle),
    nodePos.x * sin(branchAngle) + nodePos.y * cos(branchAngle)
  );

  let branch = smoothstep(0.45, 0.12, abs(rotNode.x)) * smoothstep(0.5, 0.0, abs(rotNode.y));
  let dla = fbm(uv * 12.0 + hash21(floor(colonyUV)) * 3.0, time * 0.5);
  let dlaBranch = smoothstep(0.35, 0.7, dla) * nutrient;

  let mousePull = (1.0 - smoothstep(0.0, 0.55, length(uv - mouse))) * mouseAttraction;
  let coralDensity = clamp((branch * 0.7 + dlaBranch * 0.5 + spawnPulse * 0.3) * nutrient + mousePull, 0.0, 1.0);

  let polypGrid = fract(uv * (18.0 + polypSize * 14.0)) - 0.5;
  let polypDist = length(polypGrid);
  let polyp = smoothstep(polypSize * 0.5, polypSize * 0.08, polypDist) * coralDensity;

  let caustics = abs(sin(uv.x * 40.0 + time * 0.6) + sin(uv.y * 35.0 - time * 0.4)) * 0.5;
  let causticLight = caustics * (0.15 + depth * 0.25) * (1.0 + treble * 0.5);

  let hue = fract(uv.x * 0.35 + uv.y * 0.25 + time * 0.015 + colorVariety * 0.6 + mids * 0.12);
  var coral = vec3<f32>(
    0.5 + 0.5 * sin(hue * 6.28),
    0.25 + 0.55 * sin(hue * 6.28 + 2.2),
    0.35 + 0.65 * sin(hue * 6.28 + 4.1)
  );
  coral = mix(coral, vec3<f32>(0.1, 0.9, 0.7), spawnPulse * 0.4);

  let sss = smoothstep(0.0, 0.4, coralDensity) * 0.35;
  var color = coral * (coralDensity * 0.8 + polyp * 1.4 + sss);

  let bloom = polyp * vec3<f32>(0.6, 1.0, 0.8) * (0.5 + bass * 0.6);
  color += bloom * 0.6;
  color += vec3<f32>(0.1, 0.3, 0.5) * causticLight;

  let waterTint = vec3<f32>(0.02, 0.08, 0.14);
  let depthAtten = mix(0.25, 0.85, depth);
  color = mix(waterTint * depthAtten, color, clamp(coralDensity + polyp * 0.5, 0.0, 1.0));

  color = acesToneMap(color * (1.0 + bass * 0.25));

  let biolum = polyp * (0.4 + bass * 0.5);
  let semantic_alpha = clamp(coralDensity * biolum * depthAtten, 0.2, 0.98);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(coralDensity * depthAtten, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "gen-coral-reef-colony",
  "name": "Coral Reef Colony",
  "url": "shaders/gen-coral-reef-colony.wgsl",
  "category": "generative",
  "description": "Upgraded coral reef with space colonization branching, DLA patterns, fBm polyp detail, bioluminescent fluorescent proteins, subsurface scattering, caustic light, HDR bloom, and ACES tone mapping. Bass drives nutrient availability, mids steer current, treble triggers spawning. Mouse attracts growth; depth filters water color.",
  "tags": [
    "coral",
    "organic",
    "generative",
    "audio-reactive",
    "mouse-interactive",
    "underwater",
    "bioluminescence",
    "DLA",
    "caustics",
    "HDR"
  ],
  "features": [
    "audio-reactive",
    "mouse-driven",
    "semantic-alpha"
  ],
  "params": [
    {
      "id": "growth",
      "name": "Growth Speed",
      "default": 0.65,
      "min": 0,
      "max": 1.4,
      "step": 0.01,
      "param": "zoom_params.x",
      "mapping": "zoom_params.x"
    },
    {
      "id": "polypSize",
      "name": "Polyp Size",
      "default": 0.55,
      "min": 0.2,
      "max": 1,
      "step": 0.01,
      "param": "zoom_params.y",
      "mapping": "zoom_params.y"
    },
    {
      "id": "colorVariety",
      "name": "Color Variety",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "param": "zoom_params.z",
      "mapping": "zoom_params.z"
    },
    {
      "id": "mouseAttraction",
      "name": "Mouse Attraction",
      "default": 0.6,
      "min": 0,
      "max": 1.3,
      "step": 0.01,
      "param": "zoom_params.w",
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
