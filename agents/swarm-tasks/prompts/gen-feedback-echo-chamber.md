# Shader Upgrade Task: `gen-feedback-echo-chamber`

## Metadata
- **Shader ID**: gen-feedback-echo-chamber
- **Agent Role**: Interactivist
- **Current Size**: 1370 bytes
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
// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Feedback Echo Chamber - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Effect Intensity
//  Features: advanced-alpha, generative-feedback, temporal-echo
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    
    return vec4<f32>(color, totalAlpha);
}

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(color: vec3<f32>, brightness: f32, intensity: f32, accumulationRate: f32) -> f32 {
    // Tunable parameters from zoom_params
    let echoCount = u.zoom_params.x;      // Echo Count
    let decayRate = u.zoom_params.y;      // Decay Rate
    let spacing = u.zoom_params.z;        // Echo Spacing
    let colorShift = u.zoom_params.w;     // Color Shift
    
    // Effect intensity alpha: brighter = more opaque
    let intensityAlpha = mix(0.3, 1.0, brightness * intensity);
    
    // Accumulation-driven alpha: more echoes = stronger alpha buildup
    let accumBoost = echoCount * 0.3 + decayRate * 0.4;
    
    // Temporal persistence: spacing affects how quickly alpha decays
    let persistence = 1.0 - spacing * 0.3;
    
    // Combine: base intensity + accumulation boost, modulated by persistence
    let alpha = intensityAlpha * (1.0 + accumBoost) * persistence;
    
    return clamp(alpha, 0.1, 1.0);
}

// Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
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
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = plasmaBuffer[0].x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let accumulationRate = u.zoom_params.x;
    let echoScale = u.zoom_params.y * 0.05;
    let intensity = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    
    // Current frame
    let current = textureLoad(readTexture, coord, 0);
    
    // Previous accumulated frame
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Generative pattern
    let patternUV = uv * 10.0;
    let pattern = hash(floor(patternUV) + time * 0.1 * audioReactivity);
    
    // Echo displacement
    let echoUV = uv + vec2<f32>(
        sin(time * 0.5 * audioReactivity + uv.y * 5.0) * echoScale,
        cos(time * 0.3 * audioReactivity + uv.x * 5.0) * echoScale
    );
    
    // Sample echo
    let echo = textureSampleLevel(dataTextureC, u_sampler, fract(echoUV), 0.0);
    
    // Generative color
    let genColor = vec3<f32>(
        0.5 + 0.5 * sin(time + uv.x * 5.0 + pattern),
        0.5 + 0.5 * sin(time * 0.8 * audioReactivity + uv.y * 5.0 + pattern + 2.0),
        0.5 + 0.5 * sin(time * 0.6 * audioReactivity + (uv.x + uv.y) * 3.0 + pattern + 4.0)
    );
    
    // Blend
    let blended = mix(echo.rgb, genColor * intensity, 0.3);
    let finalColor = mix(blended, current.rgb, 0.2);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let brightness = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = calculateAdvancedAlpha(finalColor, brightness, intensity, accumulationRate);
    
    let accumulated = accumulativeAlpha(
        finalColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    let caStr = 0.003 * (1.0 + audioOverall) + 0.001;
    let chromaticRGB = vec3<f32>(accumulated.r + caStr, accumulated.g, accumulated.b - caStr * 0.5);
    let finalRGB = acesToneMap(chromaticRGB * 1.1);
    let output = vec4<f32>(finalRGB, accumulated.a);

    textureStore(dataTextureA, coord, output);
    textureStore(writeTexture, global_id.xy, output);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "gen-feedback-echo-chamber",
  "name": "Feedback Echo Chamber",
  "url": "shaders/gen-feedback-echo-chamber.wgsl",
  "description": "Multi-layer temporal echo with feedback decay, creating ghost images of previous frames fading into depth with color grading per layer",
  "tags": [
    "temporal",
    "echo",
    "feedback",
    "multi-layer",
    "ghosting",
    "audio",
    "music",
    "reactive",
    "alpha",
    "accumulative"
  ],
  "features": [
    "aces-tone-map",
    "advanced-alpha",
    "audio-driven",
    "audio-reactive",
    "chromatic-aberration",
    "depth-aware",
    "multi-pass",
    "temporal",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "echoCount",
      "name": "Echo Count",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "decayRate",
      "name": "Decay Rate",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "spacing",
      "name": "Echo Spacing",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "colorShift",
      "name": "Color Shift",
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
