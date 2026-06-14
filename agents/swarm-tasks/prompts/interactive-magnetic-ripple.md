# Shader Upgrade Task: `interactive-magnetic-ripple`

## Metadata
- **Shader ID**: interactive-magnetic-ripple
- **Agent Role**: Interactivist
- **Current Size**: 3166 bytes
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
//  Interactive Magnetic Ripple — May 2026 Batch D Upgrade
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-05-10
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973);
  pp = pp + dot(pp, pp.yzx + 33.33);
  return fract((pp.xx + pp.yz) * pp.zy);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
             mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
             u.y);
}

fn fbm(p: vec2<f32>, t: f32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    s += a * valueNoise(p * f + t * 0.12 * f32(i + 1));
    f *= 2.1;
    a *= 0.5;
  }
  return s;
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.008;
  let n0 = fbm(p + vec2<f32>(0.0,  e), t);
  let n1 = fbm(p + vec2<f32>(0.0, -e), t);
  let n2 = fbm(p + vec2<f32>( e, 0.0), t);
  let n3 = fbm(p + vec2<f32>(-e, 0.0), t);
  return vec2<f32>(n0 - n1, n3 - n2) / (2.0 * e);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let freq = u.zoom_params.x * 40.0;
  let decay = u.zoom_params.y * 3.0 + 0.5;
  let fieldStrength = u.zoom_params.z;
  let chromaticSplit = u.zoom_params.w * 0.08;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Bass → field strength pulse
  let pulseStrength = fieldStrength * (1.0 + bass * 0.6);

  var totalDisp = vec2<f32>(0.0);
  var rippleIntensity = 0.0;

  // ── Mouse-driven magnetic field ──
  if (mouse.x >= 0.0) {
    let dMouse = mouse - uv;
    let dAspect = vec2<f32>(dMouse.x * aspect, dMouse.y);
    let dist = length(dAspect);
    let dir = select(vec2<f32>(0.0), dMouse / dist, dist > 0.001);

    // Curl-noise velocity field (divergence-free)
    let curl = curlNoise(uv * 3.0 + time * 0.3, time) * 0.25;

    // Multi-octave ripple with FBM phase warp
    let phase = dist * freq - time * 4.0;
    let fbmWarp = fbm(vec2<f32>(dist * 4.0, time * 0.4), time) * 2.5;
    let ripple = cos(phase + fbmWarp) * 0.55 + sin(phase * 1.618) * 0.45;
    let rippleAtten = exp(-dist * decay);
    totalDisp += dir * ripple * rippleAtten * 0.06;
    rippleIntensity += abs(ripple) * rippleAtten;

    // Magnetic pull with FBM-modulated radial falloff
    let magFalloff = fbm(vec2<f32>(dist * 6.0, time * 0.2), time) * 0.3 + 0.7;
    let magPull = dir * pulseStrength * magFalloff / (dist * dist + 0.04) * 0.06;
    totalDisp += magPull + curl * 0.04;
    rippleIntensity += length(magPull) * 10.0;

    // Magnetic field lines using curl noise
    let fieldLineFreq = 12.0;
    let fieldLine = sin(atan2(dAspect.y, dAspect.x) * fieldLineFreq + fbm(uv * 5.0, time) * 3.0);
    let fieldLineMask = smoothstep(0.3, 0.0, abs(fieldLine)) * exp(-dist * 3.0);
    totalDisp += dir * fieldLineMask * pulseStrength * 0.02;
    rippleIntensity += fieldLineMask * pulseStrength;
  }

  // ── Process all 50 ripple points for multi-click accumulation ──
  for (var i: u32 = 0u; i < 50u; i = i + 1u) {
    let rp = u.ripples[i];
    if (rp.z <= 0.0) { continue; }
    let rPos = rp.xy;
    let rAge = time - rp.z;
    let rDiff = vec2<f32>((rPos.x - uv.x) * aspect, rPos.y - uv.y);
    let rDist = length(rDiff);
    let rDir = select(vec2<f32>(0.0), vec2<f32>(rDiff.x / aspect, rDiff.y) / rDist, rDist > 0.001);
    let rRipple = cos(rDist * freq * 0.6 - rAge * 5.0) * exp(-rDist * decay - rAge * 1.2);
    totalDisp += rDir * rRipple * 0.035;
    rippleIntensity += abs(rRipple) * 0.5;
  }

  // Domain-warped displacement amplification
  let warp = fbm(uv * 4.0 + time * 0.2, time) * 0.015;
  totalDisp = totalDisp + totalDisp * warp;

  // Chromatic aberration with noise-driven asymmetry
  let abNoise = fbm(uv * 6.0 + vec2<f32>(time * 0.1, 0.0), time) * 0.015;
  let abScale = 1.0 + chromaticSplit + abNoise;
  let rUV = uv - totalDisp * abScale;
  let gUV = uv - totalDisp;
  let bUV = uv - totalDisp * (2.0 - abScale);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  // Alpha: preserves src.a, adds glow at high-intensity ripple peaks
  let glow = smoothstep(0.2, 0.8, rippleIntensity) * (1.0 + bass * 0.5);
  let alpha = mix(src.a, min(src.a + glow * 0.3, 1.0), glow);

  var color = vec3<f32>(r, g, b);
  // Add glow color at peaks modulated by mids/treble
  color += vec3<f32>(0.3 + mids * 0.3, 0.5 + treble * 0.3, 0.8) * glow * 0.4;

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "interactive-magnetic-ripple",
  "name": "Magnetic Ripple",
  "url": "shaders/interactive-magnetic-ripple.wgsl",
  "description": "Magnetic field distortion with curl-noise field lines, all 50 ripple point accumulation, FBM domain warping, chromatic split, and glow-alpha at ripple peaks.",
  "params": [
    {
      "id": "ripple_freq",
      "name": "Ripple Frequency",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "ripple_decay",
      "name": "Ripple Decay",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "field_strength",
      "name": "Field Strength",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "chromatic_split",
      "name": "Chromatic Split",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "distortion",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "fbm",
    "curl-noise",
    "worley",
    "domain-warp",
    "fractal",
    "magnetic",
    "field-lines"
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
