# Shader Upgrade Task: `quantum-ripples`

## Metadata
- **Shader ID**: quantum-ripples
- **Agent Role**: Advanced-Hybrid
- **Current Size**: 181 bytes
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
//  Quantum Ripples
//  Category: image
//  Features: mouse-driven, interactive, audio-reactive, temporal-feedback,
//            depth-aware, chromatic-aberration, domain-warped-fbm, curl-turbulence
//  Complexity: Medium
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

// ── Canonical hash / noise ────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
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
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}
fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Divergence-free velocity field ────────────────────────────────
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps + t * 0.0);
}

// ── Chromatic aberration for texture-backed shaders ───────────────
fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let offset = dir * max(amount, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

// ── Wave source with domain-warped FBM turbulence ─────────────────
fn waveField(uv: vec2<f32>, center: vec2<f32>, aspect: f32, t: f32,
             freq: f32, spd: f32, turb: f32) -> vec2<f32> {
    let dx = (uv.x - center.x) * aspect;
    let dy = uv.y - center.y;
    let d = sqrt(dx * dx + dy * dy);
    let dir = select(normalize(vec2<f32>(dx, dy)), vec2<f32>(0.0, 0.0), d < 0.001);
    let warpedUv = domainWarp(uv * 3.0 + dir * 2.0, 0.35, 3);
    let warp = fbm(warpedUv + t * 0.15, 3) * turb;
    let phase = d * freq - t * spd + warp;
    let harmonic = sin(phase * PHI + TAU * 0.25) * 0.5;
    let w = (sin(phase) + harmonic) * exp(-d * 3.0) * 0.666;
    return dir * w;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let uv    = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time  = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = res.x / res.y;

    let freq = u.zoom_params.x * 24.0 + 2.0;
    let spd  = u.zoom_params.y * 6.0;
    let amp  = u.zoom_params.z * 0.12;
    let csh  = u.zoom_params.w;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    // Curl-noise advection for organic, divergence-free turbulence
    let curl = curl2D(uv * 4.0 + time * 0.1, time) * (0.02 + bass * 0.02);
    let sampleUv = clamp(uv01 + curl, vec2<f32>(0.0), vec2<f32>(1.0));

    var disp = waveField(sampleUv, mouse, aspect, time, freq, spd, 0.5 + bass * 0.2);

    // Superpose historical ripple sources (max 8 for performance)
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < min(rippleCount, 8u); i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let rf = freq * (1.0 + hash21(rp.xy) * 0.3);
        disp += waveField(sampleUv, rp.xy, aspect, time, rf, spd * 0.7, 0.25) *
                exp(-age * 2.0) * 0.5;
    }

    let activeAmp = select(1.0, 2.0, u.zoom_config.w > 0.5);
    disp *= amp * activeAmp;

    // Depth-aware refraction sharpens the lensing at foreground edges
    let depthOffset = (uv01 - vec2<f32>(0.5)) * depth * 0.02;
    let srcUV = clamp(uv01 - disp + depthOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Color from displaced source + chromatic aberration
    let base = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);
    var color = base.rgb;
    let caAmt = 0.003 * (1.0 + bass) + depth * 0.002 + length(disp) * 0.5;
    let ca = chromaticAberration(srcUV, caAmt);
    color = mix(color, ca, clamp(csh + depth * 0.3, 0.0, 1.0));

    // Energy-based hue shift + audio glow
    let energy = length(disp) / (amp * activeAmp + 0.001);
    let shift = energy * csh * sin(time * 0.5) * 0.3;
    color.r += shift + energy * treble * 0.08;
    color.b -= shift;
    color += vec3<f32>(energy * bass * 0.12);

    // Temporal feedback with decay
    let decay = 0.97 - csh * 0.03;
    let blend = 0.18 + bass * 0.08;
    color = mix(prev.rgb * decay, color, blend);

    // ACES tone map + semantic alpha
    color = acesToneMap(color * (0.9 + mids * 0.2));
    let effectIntensity = energy * (0.5 + bass * 0.5);
    let alpha = mix(base.a, clamp(effectIntensity, 0.0, 0.95), 0.7);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}

```

## Current JSON Definition
```json
{
  "id": "quantum-ripples",
  "name": "Quantum Ripples",
  "url": "shaders/quantum-ripples.wgsl",
  "description": "Mouse-driven quantum interference waves with domain-warped FBM, divergence-free curl turbulence, temporal feedback, depth-aware chromatic aberration and audio reactivity.",
  "params": [
    {
      "id": "waveFreq",
      "name": "Wave Freq",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "waveSpeed",
      "name": "Propagate Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "distortionStr",
      "name": "Distortion",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "colorShift",
      "name": "Color Shift",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "interactive",
    "audio-reactive",
    "temporal-feedback",
    "depth-aware",
    "chromatic-aberration"
  ],
  "tags": [
    "filter",
    "image-processing",
    "waves",
    "interference",
    "turbulence",
    "domain-warp",
    "curl-noise"
  ]
}

```

---

## Agent Specialization
# Agent Role: Advanced Hybrid Creator (Phase B)

## Identity
You are the **Advanced Hybrid Creator**. Your job is to upgrade the shader by combining two or more distinct techniques into a single, cohesive effect.

## Hybrid Strategies
- Combine the base effect with a second technique from this list: reaction-diffusion, domain-warped FBM, SDF masking, chromatic aberration, feedback echo, Voronoi displacement, or audio-driven palette.
- Reuse existing chunks/patterns already in the codebase (`smin`, `kaleido`, `warppedFBM`, `bass_env`).
- Keep the result slot-chain safe: write meaningful alpha and respect the 13-binding contract.

## Output Rules
- The upgraded shader must show ≥2 clearly identifiable techniques working together.
- Add a header comment listing the combined techniques.
- Update JSON `features` and `tags` to reflect new techniques.
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
