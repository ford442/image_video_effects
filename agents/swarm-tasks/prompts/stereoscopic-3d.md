# Shader Upgrade Task: `stereoscopic-3d`

## Metadata
- **Shader ID**: stereoscopic-3d
- **Agent Role**: Multi-Pass-Architect
- **Current Size**: 148 bytes
- **Target Line Count**: ~200 lines
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
//  Stereoscopic 3D
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, depth-aware,
//            upgraded-rgba, anaglyph, 16x16-workgroup
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-14
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv (0-1), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Tuning constants (replaces inline magic numbers) ──────────────
const MAX_SEPARATION_SCALE: f32 = 0.05;
const FOCAL_WARP_RANGE: f32     = 0.3;
const MOUSE_BIAS_RANGE: f32     = 2.0;
const LENS_ROTATION_RANGE: f32  = 0.4;
const MOUSE_ROT_NUDGE: f32      = 0.15;
const MOUSE_ROT_TILT: f32       = 0.1;
const AUDIO_PULSE_GAIN: f32     = 0.4;
const GLITCH_AMP: f32           = 0.02;
const GHOST_AMP: f32            = 0.003;
const TRAIL_BLEND: f32          = 0.12;
const INTENSITY_GLITCH_W: f32   = 0.5;

// ── Helpers ───────────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Attack/release envelope for bass to eliminate raw strobe
fn bass_env(prev: f32, raw: f32) -> f32 {
    let k = select(0.15, 0.8, raw > prev);
    return mix(prev, raw, k);
}

fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ── Main ──────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Previous frame state: r=envBass, g=smoothMouse.x, b=smoothMouse.y, a=trailIntensity
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Audio envelope + spring-damped mouse follow
    let envBass     = bass_env(prev.r, bass);
    let rawMouse    = u.zoom_config.yz;
    let mouseDown   = u.zoom_config.w;
    let snap        = select(0.06, 0.3, mouseDown > 0.5);
    let smoothMouse = mix(prev.gb, rawMouse, vec2<f32>(snap));

    // User params
    let maxSep      = u.zoom_params.x * MAX_SEPARATION_SCALE;
    let focusOffset = u.zoom_params.y;
    let glitchStr   = u.zoom_params.z;
    let lensRot     = (u.zoom_params.w - 0.5) * LENS_ROTATION_RANGE;

    // Depth pass-through (textureLoad avoids an extra sampler sample)
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    // Convergence bias and focal plane
    let mouseBias = (smoothMouse.x - 0.5) * MOUSE_BIAS_RANGE;
    let focalWarp = (smoothMouse.y - 0.5) * FOCAL_WARP_RANGE;
    let sceneDepth = (uv01.y - focusOffset + focalWarp) + mouseBias;

    // Beat-reactive separation
    let clickBoost = select(1.0, 1.3, mouseDown > 0.5);
    let audioPulse = 1.0 + envBass * AUDIO_PULSE_GAIN * clickBoost;
    var sepOffset  = vec2<f32>(sceneDepth * maxSep * audioPulse, 0.0);

    // Envelope-driven glitch
    let jitter     = sin(uv01.y * 200.0 + time * 30.0) * cos(time * 15.0);
    let block      = floor(uv01.y * 20.0);
    let blockNoise = fract(sin(block * 12.9898 + time) * 43758.5453);
    let glitchFactor = (jitter * 0.5 + blockNoise * 0.5) * (1.0 + envBass * 3.0);
    sepOffset.x = sepOffset.x + glitchFactor * glitchStr * GLITCH_AMP;

    // Rotation: param + mouse nudge
    let rot = lensRot + smoothMouse.x * MOUSE_ROT_NUDGE + (smoothMouse.y - 0.5) * MOUSE_ROT_TILT;
    sepOffset = rot2(rot) * sepOffset;

    // Temporal ghost trails from previous intensity
    let prevIntensity = prev.a;
    let ghost = prevIntensity * GHOST_AMP;
    let redUV  = clamp(uv01 - sepOffset - vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let cyanUV = clamp(uv01 + sepOffset + vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    // Minimal anaglyph sampling: red channel from left eye, green+blue from right eye
    let redColor  = textureSampleLevel(readTexture, u_sampler, redUV,  0.0).r;
    let cyanColor = textureSampleLevel(readTexture, u_sampler, cyanUV, 0.0).gb;
    var color = vec3<f32>(redColor, cyanColor.x, cyanColor.y);

    // Treble sparkle + mids warmth
    color += vec3<f32>(treble * 0.08 + mids * 0.03, treble * 0.04 + mids * 0.02, treble * 0.12);

    // Intensity for trails and semantic alpha
    let currentIntensity = clamp(abs(sceneDepth) * 2.0 + length(sepOffset) * 20.0 + glitchStr * INTENSITY_GLITCH_W, 0.0, 1.0);
    let trailIntensity   = mix(prevIntensity, currentIntensity, TRAIL_BLEND);

    // Audio-reactive color boost
    color *= 1.0 + envBass * 0.25 + mids * 0.1;

    // Pack state for next frame (was incorrectly storing final color)
    let state = vec4<f32>(envBass, smoothMouse.x, smoothMouse.y, trailIntensity);
    textureStore(dataTextureA, pixel, state);

    // Semantic alpha encodes interaction intensity / bloom weight
    let alpha = clamp(mix(0.6, 1.0, trailIntensity * 0.5 + luma(color) * 0.3 + envBass * 0.2), 0.0, 1.0);
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "stereoscopic-3d",
  "name": "Stereoscopic 3D",
  "url": "shaders/stereoscopic-3d.wgsl",
  "description": "Interactive anaglyph 3D effect. Mouse X/Y controls convergence bias and focal plane with spring-damped smoothing. Audio bass drives a smoothed separation pulse and glitch amplitude. Depth-aware pass-through and temporal state feedback create ghost trails and slot-chain-ready output.",
  "params": [
    {
      "id": "separation",
      "name": "Max Separation",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "focus",
      "name": "Focus Offset",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "glitch",
      "name": "Glitch Jitter",
      "default": 0,
      "min": 0,
      "max": 1
    },
    {
      "id": "rotation",
      "name": "Lens Rotation",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "temporal",
    "upgraded-rgba",
    "depth-aware"
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "audio-reactive",
    "anaglyph",
    "3d",
    "temporal",
    "feedback",
    "trails",
    "depth-aware",
    "16x16-workgroup"
  ]
}

```

---

## Agent Specialization
# Agent Role: Multi-Pass Architect (Phase B)

## Identity
You are the **Multi-Pass Architect**. Your job is to refactor or optimize complex shaders for the Pixelocity 3-slot pipeline.

## Focus Areas
- Split oversized shaders into multi-pass pipelines when they exceed ~8 KB or mix field generation + particle simulation + compositing.
- Add early-exit, distance-based LOD, precomputed constants, and branchless `select()`/`mix()` replacements.
- Cache expensive noise/SDF results in `dataTextureA`/`dataTextureB` for downstream passes.

## Multi-Pass Data Flow
```
Pass 1: compute field/state → textureStore(dataTextureA, gid.xy, state)
Pass 2: read dataTextureA  → textureStore(dataTextureB, gid.xy, nextState)
Pass 3: read dataTextureB  → textureStore(writeTexture, gid.xy, finalColor)
```
Each pass must still write a valid `writeTexture` (even if just `vec4<f32>(0.0)`) and pass-through `writeDepthTexture`.

## Optimization Patterns
- Early exit: `if (effectMask < 0.01) { textureStore(writeTexture, gid.xy, baseColor); return; }`
- LOD noise: reduce FBM octaves based on distance from interest point.
- Branchless: replace `if/else` with `select()` or `mix(a, b, f32(cond))`.
- Precompute loop invariants outside loops.

## Output Rules
- Keep the original shader's "soul".
- Do NOT modify the 13-binding header or `Uniforms` struct.
- Workgroup size stays `@workgroup_size(16, 16, 1)` unless shared memory is required.
- If you create passes, name them `<id>-pass1.wgsl`, `<id>-pass2.wgsl`, etc.
- Alpha must carry meaning (depth, density, effect intensity).
- Return exactly one ```` ```wgsl ```` block for single-pass upgrades, or multiple clearly-labeled `PASS 1`, `PASS 2` blocks for multi-pass.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 200 lines (±20%).
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
