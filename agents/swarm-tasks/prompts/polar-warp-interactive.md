# Shader Upgrade Task: `polar-warp-interactive`

## Metadata
- **Shader ID**: polar-warp-interactive
- **Agent Role**: Interactivist
- **Current Size**: 3287 bytes
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
//  Polar Warp Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba, audio-reactive, depth-aware, multi-ripple
//  Complexity: Medium
//  Upgraded: bass-driven warp, spiral component, ripple bursts, semantic alpha
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

const PI: f32 = 3.14159265;
const TAU: f32 = 6.2831853;
const EPS: f32 = 1e-3;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let gid = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    let mouseRaw = u.zoom_config.yz;
    let mouse = select(mouseRaw, vec2<f32>(0.5), mouseRaw.x < 0.0);

    let bass = plasmaBuffer[0].x;
    let bassPulse = 1.0 + bass * 0.4;

    let warpStrength = u.zoom_params.x * bassPulse;
    let spiralAmount = u.zoom_params.y * 5.0;
    let rippleDecay = u.zoom_params.z;
    let pinchExpand = u.zoom_params.w;

    var diff = uv - mouse;
    diff.x *= aspect;

    let radius = length(diff);
    let angle = atan2(diff.y, diff.x);

    // Early exit: hide center singularity
    if (radius < EPS) {
        textureStore(writeTexture, gid, vec4<f32>(0.0));
        textureStore(writeDepthTexture, gid, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        return;
    }

    // Polar distortion
    let zoom = 0.1 + warpStrength * 2.0;
    let r_new = pow(radius, 1.0 / zoom) - pinchExpand;
    var a_new = angle + radius * spiralAmount;

    // Click-triggered ripple bursts from u.ripples
    for (var i: i32 = 0; i < 50; i = i + 1) {
        let rp = u.ripples[i];
        if (rp.z > 0.0) {
            let age = time - rp.z;
            if (age > 0.0 && age < 3.0) {
                let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
                let rippleWave = sin(rd * 30.0 - age * 10.0) * exp(-age * rippleDecay * 3.0);
                a_new = a_new + rippleWave * 0.1 * rp.w;
            }
        }
    }

    // Map polar back to UV space with time rotation
    let tunnel_u = (a_new / PI) * 2.0 + time * 0.1;
    let tunnel_v = 1.0 / (r_new + EPS);

    // Mirrored-repeat UV sampling for seamless edges
    let fuv = fract(vec2<f32>(tunnel_u, tunnel_v));
    let sampleUV = abs(fuv * 2.0 - 1.0);

    // Single texture sample
    let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Radial fade at the singularity
    let fade = smoothstep(0.0, 0.1, radius);

    // Depth-aware fade
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(0.7, 1.0, depth);

    // Semantic alpha: reduce at extreme warp distortion
    let warpDistort = abs(r_new - radius) + abs(a_new - angle);
    let alpha = mix(col.a, 0.85, smoothstep(0.5, 1.5, warpDistort));
    let finalAlpha = alpha * fade * depthFade;

    textureStore(writeTexture, gid, vec4<f32>(col.rgb * fade * depthFade, finalAlpha));
    textureStore(writeDepthTexture, gid, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "polar-warp-interactive",
  "name": "Polar Warp",
  "url": "shaders/polar-warp-interactive.wgsl",
  "description": "Maps the image to polar coordinates centered on the mouse with bass-driven warp strength, spiral twist, click-triggered ripple bursts, and depth-aware fading.",
  "features": [
    "mouse-driven",
    "upgraded-rgba",
    "audio-reactive",
    "depth-aware",
    "multi-ripple"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Warp Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Spiral Amount",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Ripple Decay",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Pinch/Expand",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "tags": [
    "filter",
    "image-processing",
    "interactive",
    "polar",
    "warp",
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
