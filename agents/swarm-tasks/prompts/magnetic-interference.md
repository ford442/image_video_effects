# Shader Upgrade Task: `magnetic-interference`

## Metadata
- **Shader ID**: magnetic-interference
- **Agent Role**: Interactivist
- **Current Size**: 3355 bytes
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
//  Magnetic Interference - Alpha Translucency Edition
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, ripple-integration, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Transform: Replaced per-channel magnetic pull with unified
//             displacement field. Alpha encodes magnetic field
//             strength * distance falloff. Added ripple shockwave
//             interference and gravity-well mouse attraction.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ Audio envelope (smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ═══ Gravity well (mouse attraction) ═══
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}

// ═══ Tent alpha curve ═══
fn tentAlpha(x: f32) -> f32 {
    return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let bass = plasmaBuffer[0].x;

    // ─── Audio envelope with attack/release (read from feedback pixel 0,0) ───
    let prevEnv = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).r;
    let env = bass_env(prevEnv, bass, 0.8, 0.15);

    let aspect = resolution.x / resolution.y;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

    let dist = distance(uv_corrected, mouse_corrected);

    let strength = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let scanline_intensity = u.zoom_params.w;

    // Mouse X modulates magnetic radius
    let mouseRadiusMod = 1.0 + mousePos.x * 0.3;
    let effectiveRadius = radius * mouseRadiusMod;

    let audioStrength = strength * (1.0 + env * 0.3);
    let audioScanlines = scanline_intensity * (1.0 + env * 0.5);

    // ─── Single magnetic displacement field ───
    let pull = audioStrength * 0.05 / (pow(dist, 2.0) + 0.01);
    let influence = smoothstep(effectiveRadius, 0.0, dist);

    var dir = uv - mousePos;
    let magneticDisp = dir * pull * influence;

    // ─── Ripple system integration for shockwave interference ───
    var rippleDisp = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, rPos);
            let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            rippleDisp = rippleDisp + (uv - rPos) * rWave * smoothstep(0.3, 0.0, rDist) * 0.5;
        }
    }

    // ─── Gravity well attracts pixels when mouse is down ───
    let gWell = gravityWell(uv, mousePos, select(0.0, 0.03, isMouseDown));
    let gravityDisp = gWell * influence * 0.02;

    // Unified displacement (NO per-channel splitting)
    let totalDisp = magneticDisp + rippleDisp + gravityDisp;
    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

    // Single sample from unified UV
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // ─── Temporal feedback for smearing ───
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let fieldMag = length(totalDisp) * 20.0;
    let feedbackMix = tentAlpha(fieldMag) * 0.1;
    let feedbackColor = mix(baseColor, prevColor, feedbackMix);

    // Spectral tint via mix(), NOT per-channel sampling
    let tint = vec3<f32>(1.0 + aberration * 0.3, 1.0, 1.0 - aberration * 0.3);
    let tintedColor = mix(feedbackColor, feedbackColor * tint, fieldMag * 0.5);

    // Scanlines modulated by field magnitude
    let scanline_uv_y = uv.y + fieldMag * 0.5;
    let scanline = sin(scanline_uv_y * resolution.y * 0.5 + time * 5.0);
    let scanline_mask = 1.0 - (scanline * 0.5 + 0.5) * audioScanlines;
    let color = tintedColor * scanline_mask;

    // ─── Alpha = magnetic field strength * distance falloff ───
    let fieldMagnetic = length(magneticDisp) * 10.0;
    let alpha = clamp(fieldMagnetic * influence + env * 0.2, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));

    if (coord.x == 0 && coord.y == 0) {
        textureStore(dataTextureA, coord, vec4<f32>(env, 0.0, 0.0, 0.0));
    } else {
        textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
    }
}

```

## Current JSON Definition
```json
{
  "id": "magnetic-interference",
  "name": "Magnetic Interference",
  "url": "shaders/magnetic-interference.wgsl",
  "description": "Simulates magnetic distortion using unified displacement fields and alpha translucency blending. Features ripple shockwave interference, gravity-well mouse attraction, audio-reactive bass envelope, and temporal feedback smearing.",
  "params": [
    {
      "id": "strength",
      "name": "Strength",
      "default": 1,
      "min": 0,
      "max": 2
    },
    {
      "id": "radius",
      "name": "Radius",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "aberration",
      "name": "Aberration",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "scanlines",
      "name": "Scanlines",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "ripple-integration",
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
