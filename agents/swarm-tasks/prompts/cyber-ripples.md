# Shader Upgrade Task: `cyber-ripples`

## Metadata
- **Shader ID**: cyber-ripples
- **Agent Role**: Interactivist
- **Current Size**: 3390 bytes
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
//  Cyber Ripples
//  Category: interactive-mouse
//  Features: mouse-driven, wave, neon, audio-reactive, upgraded-rgba
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

const QUANT_STEP: f32 = 24.0;
const ATTEN_SCALE: f32 = 5.0;
const DISP_AMP: f32 = 0.01;
const EPS: f32 = 0.001;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) {
    return;
  }

  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Audio reactivity: bass drives ripple intensity, mids add warmth, treble sharpens edges
  let audioBoost = 1.0 + bass * 0.5 + mids * 0.2;
  let sparkle = treble * 0.15;

  // Param unpack
  let speed = u.zoom_params.x * 5.0 + 1.0;
  let blockSize = u.zoom_params.y * 0.1;
  let aberration = u.zoom_params.z * 0.05;
  let frequency = u.zoom_params.w * 50.0 + 10.0;

  // Mouse-driven ripple origin
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  // Radial distance and normalized direction
  let delta = uvCorrected - mouseCorrected;
  let dist = length(delta);
  let dir = delta / max(dist, 1e-6);

  // Quantized digital wave — adaptive step reduces moiré shimmer
  let quant = floor(dist * QUANT_STEP) / QUANT_STEP;
  let wave = sin(quant * frequency - time * speed);

  // Attenuate and displace radially from cursor
  let strength = 1.0 / (dist * ATTEN_SCALE + 0.5);
  let displacement = dir * wave * strength * DISP_AMP * audioBoost;
  var displacedUV = uv + displacement;

  // Branchless pixelation: mix() + step() replaces per-pixel if
  let activePixel = step(EPS, blockSize);
  let blocks = 1.0 / max(blockSize, EPS);
  let pixelated = floor(displacedUV * blocks) / blocks;
  displacedUV = mix(displacedUV, pixelated, activePixel);

  // Clamp displaced UVs before sampling
  displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

  // Anti-moiré LOD bias: higher lod when displacement magnitude is large
  let lod = clamp(length(displacement) * resolution.x * 0.25, 0.0, 2.0);

  // 2-sample chromatic aberration
  let offset = vec2<f32>(aberration, 0.0);
  let sR = textureSampleLevel(readTexture, u_sampler, displacedUV + offset, lod);
  let sB = textureSampleLevel(readTexture, u_sampler, displacedUV - offset, lod);

  // Reconstruct green from both taps for a balanced chromatic split
  let r = sR.r;
  let g = mix(sR.g, sB.g, 0.5);
  let b = sB.b;

  var color = vec3<f32>(r, g, b);

  // Treble sparkle on highlights
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = color + vec3<f32>(sparkle * luma);

  // Semantic alpha: effect strength fades with distance and displacement magnitude
  let effectStrength = clamp(strength * 2.0 + length(displacement) * 50.0 + luma * 0.3, 0.0, 1.0);
  let alpha = clamp(mix(0.5, 1.0, effectStrength), 0.0, 1.0);

  let finalColor = vec4<f32>(color, alpha);

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "cyber-ripples",
  "name": "Cyber Ripples",
  "url": "shaders/cyber-ripples.wgsl",
  "description": "Digital ripples with chromatic aberration and pixelation emanating from cursor. Audio-reactive bass boost.",
  "params": [
    {
      "id": "speed",
      "name": "Ripple Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "pixelation",
      "name": "Block Size",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "aberration",
      "name": "Chromatic Aberration",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "frequency",
      "name": "Wave Density",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "wave",
    "neon",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "audio-reactive"
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
