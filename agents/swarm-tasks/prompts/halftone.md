# Shader Upgrade Task: `halftone`

## Metadata
- **Shader ID**: halftone
- **Agent Role**: Interactivist
- **Current Size**: 3595 bytes
- **Target Line Count**: ~140 lines
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
//  Retro Halftone
//  Category: retro-glitch
//  Features: mouse-focus, screen-rotation, mouse-velocity-stretch, audio-reactive
//  Complexity: Medium
//  Phase B / Interactivist
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
  zoom_params: vec4<f32>,  // x=DotScale, y=Contrast, z=ColorMode, w=ScreenAngle
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn luminance(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }

// Elliptical "dot" — when stretch ≠ 1, becomes drag-stretched cell
fn ellipDot(uv: vec2<f32>, center: vec2<f32>, radius: f32, axis: vec2<f32>, stretch: f32) -> f32 {
    let d = uv - center;
    // Project along/perpendicular to axis, scale projected component by 1/stretch
    let along = dot(d, axis);
    let perp  = vec2<f32>(d.x - along * axis.x, d.y - along * axis.y);
    let dStretched = sqrt((along * along) / max(stretch * stretch, 1e-3) + dot(perp, perp));
    return smoothstep(radius, max(radius - 0.02, 0.0), dStretched);
}

// One CMYK-rotated screen lookup (single channel)
fn screen_dot(uv: vec2<f32>, scale: f32, angle: f32, sample: vec3<f32>, channelMask: vec3<f32>,
              axis: vec2<f32>, stretch: f32, contrast: f32) -> f32 {
    let c = cos(angle);
    let s = sin(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let rUV = rot * uv * scale;
    let grid = floor(rUV);
    let cellUv = rUV - grid;
    // Sample density from this channel of source
    let density = clamp(dot((1.0 - sample) * channelMask, vec3<f32>(1.0)) * contrast, 0.0, 1.0);
    let radius = density * 0.5;
    return ellipDot(cellUv, vec2<f32>(0.5), radius, axis, stretch);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coords = vec2<i32>(global_id.xy);

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Mouse focus: dot density triples near cursor (high-resolution print zone)
    let dM = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let focus = exp(-dM * dM * 8.0);
    let baseScale = max(mix(6.0, 64.0, clamp(u.zoom_params.x, 0.0, 1.0)), 1.0)
                  * (1.0 + focus * 2.0 + bass * 0.2);

    // Mouse velocity → screen rotation drift, dot stretch along motion
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mouseVel = (mouse - prevMouse) * vec2<f32>(aspect, 1.0);
    let speed = clamp(length(mouseVel) * 60.0, 0.0, 1.5);
    let velAngle = atan2(mouseVel.y + 1e-4, mouseVel.x);
    let baseAngle = u.zoom_params.w * PI + speed * 0.4;
    let velAxis = vec2<f32>(cos(velAngle), sin(velAngle));
    let stretch = mix(1.0, 1.0 + speed * 1.5, focus * 0.7);

    let contrast = mix(0.5, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));

    // Centred sample (one source read)
    let sampleColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    var outColor: vec3<f32>;
    if (u.zoom_params.z < 0.5) {
        // Mono mode: single screen, plasma-tinted ink
        let dot = screen_dot(uv, baseScale, baseAngle, sampleColor, vec3<f32>(0.299, 0.587, 0.114),
                             velAxis, stretch, contrast);
        let palIdx = u32(clamp(luminance(sampleColor) * 255.0, 0.0, 255.0));
        let inkTint = mix(vec3<f32>(0.0), plasmaBuffer[palIdx % 256u].rgb, mouseDown);
        outColor = mix(vec3<f32>(1.0), mix(vec3<f32>(0.0), inkTint, mouseDown), dot);
    } else {
        // CMYK 4-color rosette — canonical screen angles 15°, 75°, 0°, 45°
        let cDot = screen_dot(uv, baseScale, baseAngle + 15.0 * PI / 180.0, sampleColor, vec3<f32>(1.0, 0.0, 0.0), velAxis, stretch, contrast);
        let mDot = screen_dot(uv, baseScale, baseAngle + 75.0 * PI / 180.0, sampleColor, vec3<f32>(0.0, 1.0, 0.0), velAxis, stretch, contrast);
        let yDot = screen_dot(uv, baseScale, baseAngle +  0.0 * PI / 180.0, sampleColor, vec3<f32>(0.0, 0.0, 1.0), velAxis, stretch, contrast);
        let kDot = screen_dot(uv, baseScale * 1.05, baseAngle + 45.0 * PI / 180.0, sampleColor, vec3<f32>(0.299, 0.587, 0.114), velAxis, stretch, contrast);
        let cyan    = vec3<f32>(0.0, 0.7, 0.9);
        let magenta = vec3<f32>(0.9, 0.0, 0.6);
        let yellow  = vec3<f32>(0.95, 0.85, 0.0);
        let black   = vec3<f32>(0.05, 0.05, 0.08);
        // Multiplicative ink stack (subtractive print model)
        outColor = vec3<f32>(1.0);
        outColor *= mix(vec3<f32>(1.0), cyan,    cDot);
        outColor *= mix(vec3<f32>(1.0), magenta, mDot);
        outColor *= mix(vec3<f32>(1.0), yellow,  yDot);
        outColor *= mix(vec3<f32>(1.0), black,   kDot);
    }

    // Alpha: ink coverage drives compositing weight
    let coverage = 1.0 - luminance(outColor);
    let alpha = clamp(coverage * 0.85 + focus * 0.15 + 0.05, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(outColor, alpha));

    if (coords.x == 0 && coords.y == 0) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mouse, speed, 1.0));
    }

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "halftone",
  "name": "Retro Halftone",
  "url": "shaders/halftone.wgsl",
  "category": "retro-glitch",
  "description": "Classic newspaper halftone dot pattern with adjustable scale, contrast, and color mode. Audio-reactive bass pulse modulates dot intensity.",
  "params": [
    {
      "id": "dotScale",
      "name": "Dot Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "contrast",
      "name": "Contrast",
      "default": 1.0,
      "min": 0.0,
      "max": 2.0
    },
    {
      "id": "colorMode",
      "name": "Color Mode",
      "default": 1.0,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "grid_rotation",
      "name": "Grid Rotation",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Rotation angle of halftone grid"
    }
  ],
  "tags": [
    "retro",
    "halftone",
    "print",
    "monochrome",
    "colorful",
    "image-processing",
    "filter"
  ],
  "features": [
    "mouse-driven",
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
4. Ensure the upgraded shader is roughly 140 lines (±20%).
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
