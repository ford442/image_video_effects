# Shader Upgrade Task: `gen-von-karman-vortex`

## Metadata
- **Shader ID**: gen-von-karman-vortex
- **Agent Role**: Audio-Reactivity
- **Current Size**: 1420 bytes
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
//  Von Kármán Vortex Street — Upgraded
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, curl-noise,
//            domain-warp, analytic-velocity, temporal-feedback,
//            chromatic-aberration, aces-tone-map, semantic-alpha
//  Complexity: Medium
//  Description: Analytic point-vortex street with divergence-free
//    curl-noise perturbation and fBM domain warping. Velocity is
//    computed analytically from the vortex model rather than by
//    finite differences. Bass drives shedding speed and micro-
//    turbulence; mids control trail decay. Mouse positions the
//    obstacle.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=flow_speed, y=vortex_separation, z=vortex_spacing, w=hue

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=speed, y=separation, z=spacing, w=hue
  ripples: array<vec4<f32>, 50>,
};

const PI: f32      = 3.14159265359;
const TAU: f32     = 6.28318530718;
const INV_TAU: f32 = 0.15915494309;
const N_VTX: i32   = 10;
const CORE_R: f32  = 0.04;

// ── Hash & noise library ──────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

// Divergence-free velocity perturbation for organic, incompressible detail
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let q = p + vec2<f32>(0.0, t);
    let nx = fbm(q + vec2<f32>(0.0, eps), 4) - fbm(q - vec2<f32>(0.0, eps), 4);
    let ny = fbm(q + vec2<f32>(eps, 0.0), 4) - fbm(q - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Color utilities ───────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn streamline_color(t: f32, hueShift: f32, speed: f32) -> vec3<f32> {
    let h = fract(t + hueShift);
    let a = vec3<f32>(0.55, 0.55, 0.55);
    let b = vec3<f32>(0.45, 0.45, 0.45);
    let c = vec3<f32>(1.00, 1.00, 1.00);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    let base = clamp(a + b * cos(TAU * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
    return base * (0.6 + 0.4 * clamp(speed * 0.5, 0.0, 1.0));
}

// ── Analytic vortex street ────────────────────────────────────────
// Returns vec3(psi, velocity_x, velocity_y) for N point-vortex pairs.
// Streamfunction: ψ = U·y + Σ (Γ_i/2π)·ln(r_i)
// Velocity:       u = ∂ψ/∂y,  v = -∂ψ/∂x
fn vortex_field(pos: vec2<f32>, time: f32, U: f32,
                h: f32, spacing: f32, obst: vec2<f32>) -> vec3<f32> {
    var psi = U * pos.y;
    var vel = vec2<f32>(U, 0.0);
    let domainW = f32(N_VTX) * spacing;
    let phase   = fract(U * time / domainW);
    let core2   = CORE_R * CORE_R;

    for (var i = 0; i < N_VTX; i = i + 1) {
        let fi = f32(i);
        let xT = obst.x + (fi / f32(N_VTX) - phase) * domainW - domainW * 0.5;
        let xB = obst.x + ((fi + 0.5) / f32(N_VTX) - phase) * domainW - domainW * 0.5;
        let yT = obst.y + h;
        let yB = obst.y - h;

        let dT = pos - vec2<f32>(xT, yT);
        let dB = pos - vec2<f32>(xB, yB);
        let rT2 = max(dot(dT, dT), core2);
        let rB2 = max(dot(dB, dB), core2);

        // Top row Γ = +1, bottom row Γ = -1
        psi += log(rT2) * INV_TAU * 0.5;
        psi -= log(rB2) * INV_TAU * 0.5;
        vel += vec2<f32>(dT.y, -dT.x) / (TAU * rT2);
        vel -= vec2<f32>(dB.y, -dB.x) / (TAU * rB2);
    }
    return vec3<f32>(psi, vel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv01   = vec2<f32>(gid.xy) / res;
    let time   = u.config.x;
    let mouse  = u.zoom_config.yz;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    // UI parameters
    let U        = (0.20 + u.zoom_params.x * 0.50) * (1.0 + bass * 0.6);
    let h        = 0.10 + u.zoom_params.y * 0.25 + mids * 0.05;
    let spacing  = 0.35 + u.zoom_params.z * 0.40;
    let hueShift = u.zoom_params.w;

    // Aspect-correct physical coordinates; mouse drives obstacle position
    let aspect  = res.x / res.y;
    let physPos = (uv01 - 0.5) * vec2<f32>(2.0 * aspect, 2.0);
    let obst    = vec2<f32>((mouse.x - 0.5) * 2.0 * aspect,
                            (0.5 - mouse.y) * 2.0);

    // Divergence-free curl-noise perturbation + fBM domain warp
    let noiseCoord = physPos * 2.5 + vec2<f32>(time * 0.13, -time * 0.07);
    let turb       = curl2D(noiseCoord, time * 0.2);
    let warpStr    = 0.015 + mids * 0.025 + bass * 0.015;
    let warpedPos  = physPos + turb * warpStr + vec2<f32>(
        fbm(physPos * 3.0 + vec2<f32>(time * 0.05, 1.3), 3) - 0.5,
        fbm(physPos * 3.0 + vec2<f32>(5.2, -time * 0.04), 3) - 0.5
    ) * 0.02;

    // Evaluate streamfunction and analytic velocity
    let field = vortex_field(warpedPos, time, U, h, spacing, obst);
    let psi   = field.x;
    let vel   = field.yz;
    let spd   = length(vel);

    // Obstacle mask — darken the immediate disk around the mouse
    let obstDist = length(physPos - obst);
    let obstMask = smoothstep(0.05, 0.09, obstDist);

    // Streamline contours; treble injects extra fine lines
    let nLines   = 6.0 + treble * 4.0;
    let psiNorm  = fract(psi * nLines * 0.15);
    let lineW    = 0.05 + 0.05 * mids;
    let lineGlow = exp(-abs(psiNorm - 0.5) / lineW);

    // Base streamline colour with speed-dependent saturation
    var col = streamline_color(psi * 0.05 + spd * 0.02, hueShift, spd);
    col *= lineGlow * obstMask;

    // Speed halo around vortex cores
    let speedHalo = clamp(spd * 0.12, 0.0, 1.0);
    col = clamp(col + vec3<f32>(speedHalo * 0.25 * (1.0 + bass)), vec3<f32>(0.0), vec3<f32>(1.0));

    // Temporal feedback: decaying trails blended with current frame
    let decay = 0.96 - mids * 0.03;
    col = mix(prev.rgb * decay, col, 0.18 + bass * 0.12);

    // Chromatic aberration radiating from screen centre, driven by bass + depth
    let caStr = 0.003 * (1.0 + bass) + depth * 0.0015;
    let dir   = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    col = vec3<f32>(
        col.r + dir.x * caStr,
        col.g,
        col.b - dir.y * caStr * 0.5
    );

    // Tone map and semantic alpha (intensity + depth compositing)
    col = acesToneMap(col * 1.15);
    let alpha = clamp(luma(col) * 1.4 + speedHalo * 0.2 + bass * 0.06, 0.0, 0.95)
                * (0.75 + depth * 0.25);
    let outCol = vec4<f32>(col, alpha);

    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "name": "Von K\u00e1rm\u00e1n Vortex Street",
  "category": "generative",
  "tags": [
    "fluid-dynamics",
    "vortex",
    "karman",
    "analytic",
    "physics",
    "audio-reactive"
  ],
  "description": "Analytic vortex-street flow visualization. Ten alternating point-vortex pairs shed behind the mouse-driven obstacle; their combined streamfunction \u03c8 = U\u00b7y + \u03a3 \u00b1(\u0393/2\u03c0)\u00b7ln(r) produces isocontours tracing the classic K\u00e1rm\u00e1n street wake. Bass drives shedding speed; mids vary vortex separation for staggered or aligned rows.",
  "workgroup_size": [
    16,
    16,
    1
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Flow Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Vortex Separation",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Vortex Spacing",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Colour Hue",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "updated": true,
  "id": "gen-von-karman-vortex",
  "url": "shaders/gen-von-karman-vortex.wgsl",
  "features": []
}
```

---

## Agent Specialization
# Agent Role: Audio Reactivity Specialist (Phase B)

## Identity
You are the **Audio Reactivity Specialist**. Your job is to make shaders respond musically to the audio stream already bound to `plasmaBuffer`.

## Audio Binding (canonical)
```wgsl
let bass   = plasmaBuffer[0].x;  // 20–200 Hz, ~0–2
let mids   = plasmaBuffer[0].y;  // 200–2000 Hz, ~0–2
let treble = plasmaBuffer[0].z;  // 2k–20k Hz, ~0–2
```

## Patterns
- **Bass pulse**: scale/brightness/intensity *= `1.0 + bass * 0.5`.
- **Mids morph**: rotation speed, pattern evolution, color cycling *= `1.0 + mids * 0.5`.
- **Treble sparkle**: add high-frequency detail or shimmer.
- **Envelope smoothing** (preferred over raw bass):
  ```wgsl
  fn bass_env(prev: f32, bass: f32) -> f32 {
      let k = select(0.15, 0.8, bass > prev);
      return mix(prev, bass, k);
  }
  ```
  Store `prev` in `dataTextureA.r` if the shader has free feedback.

## Output Rules
- Add at least one musically coherent audio-driven parameter.
- Update JSON `features` to include `audio-reactive`.
- Do NOT modify the 13-binding header or `Uniforms` struct.
- Workgroup size stays `@workgroup_size(16, 16, 1)`.
- Return exactly one ```` ```wgsl ```` block.


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
