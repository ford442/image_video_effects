# Shader Upgrade Task: `echo-ripple`

## Metadata
- **Shader ID**: echo-ripple
- **Agent Role**: Interactivist
- **Current Size**: 3307 bytes
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
//  Echo Ripple
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, depth-aware, upgraded-rgba
//  Complexity: High
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let beat = bass * exp(-3.0 * fract(time * 3.0));

  // Params
  let frequency = u.zoom_params.x * 30.0 + 2.0;
  let speed = u.zoom_params.y * 8.0 + 0.5;
  let decay = u.zoom_params.z * 0.97 + 0.02;
  let strength = u.zoom_params.w * 0.15 + 0.01;

  // Aspect-correct mouse distance
  let d = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(d);
  let dist2 = dot(d, d) + 0.001;

  // Gravity well (branchless UV pull toward mouse)
  let grav = d * strength * 0.02 / dist2;

  // Ripple wave: bass-driven amplitude + mids-driven phase precession
  let wave = sin(dist * frequency - time * speed + mids * 2.0) * (1.0 + beat * 3.0);
  let atten = smoothstep(0.6, 0.0, dist);

  // Multi-source ripple echoes from click history
  let rippleCount = u32(u.config.y);
  let hasR1 = f32(rippleCount > 1u);
  let hasR2 = f32(rippleCount > 2u);
  let r1 = u.ripples[1];
  let r2 = u.ripples[2];
  let d1 = (uv - r1.xy) * vec2<f32>(aspect, 1.0);
  let d2 = (uv - r2.xy) * vec2<f32>(aspect, 1.0);
  let distR1 = length(d1);
  let distR2 = length(d2);
  let t1 = time - r1.z;
  let t2 = time - r2.z;
  let wave1 = sin(distR1 * frequency - t1 * speed + mids) * smoothstep(0.7, 0.0, distR1) * step(0.0, t1) * hasR1;
  let wave2 = sin(distR2 * frequency - t2 * speed - mids) * smoothstep(0.7, 0.0, distR2) * step(0.0, t2) * hasR2;
  let totalWave = wave + wave1 + wave2;

  // Click shockwave burst
  let clickWave = sin(dist * 50.0 - time * 20.0) * mouseDown * smoothstep(0.25, 0.0, dist);

  // Branchless direction
  let rawDir = uv - mouse;
  let rawDist = length(rawDir) + 0.0001;
  let dir = rawDir / rawDist;

  // Depth-aware parallax: stronger distortion on foreground
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthMod = mix(0.6, 1.2, depth);

  // Total UV distortion
  let distort = (totalWave + clickWave) * strength * atten * depthMod;
  let sampleUV = uv - dir * distort + grav;

  // Sample video input
  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  var color = baseColor.rgb;

  // FFT multi-band color tinting at ripple edges
  let fftTint = vec3<f32>(bass * 0.5, mids * 0.3, treble * 0.6) * totalWave * atten * strength * 10.0;
  color = color + fftTint;

  // Treble sparkle on ripple crests
  let hash = fract(sin(dot(uv * 1000.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let sparkle = treble * step(0.92, hash) * atten * 0.5;
  color = color + vec3<f32>(sparkle);

  // Temporal feedback loop (exponential smoothing via history)
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let mixed = mix(color, history.rgb, decay * (1.0 - atten * 0.25));

  // Alpha: preserve input transparency, blend toward opaque based on ripple intensity
  let finalAlpha = mix(baseColor.a, 1.0, atten * 0.7);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(mixed, finalAlpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(mixed, finalAlpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "echo-ripple",
  "name": "Echo Ripple",
  "url": "shaders/echo-ripple.wgsl",
  "description": "Mouse movement creates expanding ripples that echo and persist in time. Audio reactivity drives ripple amplitude and color splitting, while depth-aware parallax separates foreground and background distortion.",
  "params": [
    {
      "id": "freq",
      "name": "Frequency",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "decay",
      "name": "Echo Decay",
      "default": 0.9,
      "min": 0,
      "max": 1
    },
    {
      "id": "strength",
      "name": "Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "temporal-persistence",
    "audio-reactive",
    "depth-aware",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "audio-reactive",
    "ripple",
    "feedback",
    "interactive"
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
