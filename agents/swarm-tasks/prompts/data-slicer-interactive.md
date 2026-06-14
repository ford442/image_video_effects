# Shader Upgrade Task: `data-slicer-interactive`

## Metadata
- **Shader ID**: data-slicer-interactive
- **Agent Role**: Interactivist
- **Current Size**: 3163 bytes
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
//  Data Slicer Interactive — May 2026 Batch D Upgrade
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal, glitch, upgraded-rgba
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2(0.0,0.0)), hash12(i + vec2(1.0,0.0)), u.x),
               mix(hash12(i + vec2(0.0,1.0)), hash12(i + vec2(1.0,1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        s += a * noise(p * f);
        f *= 2.1;
        a *= 0.5;
    }
    return s;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let sliceCountBase = mix(4.0, 32.0, u.zoom_params.x);
    let sliceCount = sliceCountBase * (1.0 + bass * 0.5);
    let sliceWidth = mix(0.005, 0.08, u.zoom_params.y);
    let fbmWarpAmt = u.zoom_params.z * 0.06;
    let colorShift = u.zoom_params.w * 0.1;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Gravity well: pull slices toward mouse
    let distMouse = length(uv - mouse);
    let gravity = 1.0 - smoothstep(0.0, 0.35, distMouse);

    let sliceIndex = floor(uv.y * sliceCount);
    let sliceY = sliceIndex / sliceCount;
    let nextSliceY = (sliceIndex + 1.0) / sliceCount;

    // FBM warp on slice edges for torn/organic look
    let edgeNoise = fbm(vec2<f32>(uv.x * 8.0, sliceY * 4.0 + time * 0.3));
    let warpedSliceWidth = sliceWidth + edgeNoise * fbmWarpAmt;

    let distToSlice = min(abs(uv.y - sliceY), abs(uv.y - nextSliceY));
    // strength naturally 0 outside boundary — no branch needed
    let strength = 1.0 - smoothstep(0.0, max(warpedSliceWidth, 1e-3), distToSlice);

    // Click-triggered slice bursts — branchless
    var burst = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rDist = length(uv - rp.xy);
        let rAge = time - rp.z;
        let rRad = rAge * 0.5;
        let rBand = abs(rDist - rRad);
        let rippleActive = select(0.0, 1.0, rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
        let rippleDecay = clamp(1.0 - rAge / 1.2, 0.0, 1.0);
        burst += rippleActive * rippleDecay * 0.15 * sin(rDist * 50.0 - rAge * 20.0);
    }

    // Quantized jitter modulated by mids
    let quant = mix(20.0, 70.0, mids);
    let quantY = floor(uv.y * quant) / quant;
    let t = time * 3.0 * (1.0 + treble);
    let n = noise(vec2<f32>(quantY * 10.0, t));

    var offset = (n - 0.5) * 0.3 * strength + burst * strength;
    var split = colorShift * strength * (1.0 + bass * 2.0);
    let alphaMod = 1.0 - strength * 0.35;

    // Gravity deformation on offset
    offset += gravity * 0.02 * sin(uv.x * 20.0 + time);

    // Depth-driven parallax on RGB split
    split *= 1.0 + depth * 0.5;

    // RGB channel sampling with displacement
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset + split, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset - split, 0.0), 0.0).b;

    // Temporal feedback from previous frame
    let feedbackUV = uv + vec2(offset * 0.3, 0.0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0);
    let fbAmt = 0.12 * strength + mouseDown * 0.25;
    var color = vec4<f32>(r, g, b, src.a * alphaMod);
    color = mix(color, prev, fbAmt);

    // Treble sparkle additive
    color.r += treble * strength * 0.25;
    color.g += treble * strength * 0.15;
    color.b += treble * strength * 0.1;

    // Depth-aware intensity boost
    color = mix(color, color * 1.3, depth * strength * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "data-slicer-interactive",
  "name": "Data Slicer",
  "url": "shaders/data-slicer-interactive.wgsl",
  "description": "Glitchy horizontal slicing with FBM-warped torn edges, click-triggered slice bursts from ripple history, bass-modulated slice count, and semantic alpha at slice boundaries.",
  "params": [
    {
      "id": "slice_count",
      "name": "Slice Count",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "slice_width",
      "name": "Slice Width",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "fbm_warp",
      "name": "FBM Warp",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "color_shift",
      "name": "Color Shift",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "glitch",
    "audio-reactive",
    "temporal",
    "upgraded-rgba"
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "audio-reactive",
    "glitch",
    "feedback",
    "temporal",
    "fbm",
    "slice"
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
