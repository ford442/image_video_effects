# Shader Upgrade Task: `scanline-wave`

## Metadata
- **Shader ID**: scanline-wave
- **Agent Role**: Audio-Reactivity
- **Current Size**: 180 bytes
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
//  Scanline Wave
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-persistence, chromatic-CRT,
//            HDR-color-grading, ACES-tone-map, IGN-dither, premultiplied-alpha
//  Complexity: High
//  Chunks From: scanline-wave, bass_env, temporal-feedback
//  Created: 2024-01-01
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn bass_env(bass: f32, mids: f32) -> f32 {
    return 1.0 + bass * 0.5 + mids * 0.2;
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let lv = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(lv, 1e-4));
    return c * s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l_ = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    let m_ = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    let s_ = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    let l = pow(l_, 1.0 / 3.0); let m = pow(m_, 1.0 / 3.0); let s = pow(s_, 1.0 / 3.0);
    return vec3<f32>(
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    );
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    let l = l_ * l_ * l_; let m = m_ * m_ * m_; let s = s_ * s_ * s_;
    return vec3<f32>(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
       -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
       -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (t <= 66.0) { r = 1.0; }
    else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
    if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
    else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
    if (t >= 66.0) { b = 1.0; }
    else if (t <= 19.0) { b = 0.0; }
    else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    let waveAmount  = u.zoom_params.x * bass_env(bass, mids);
    let lineCount   = mix(50.0, 300.0, u.zoom_params.y);
    let persistence = u.zoom_params.z;
    let rollSpeed   = u.zoom_params.w;

    // Mouse proximity boosts local distortion
    let mouseDist  = distance(uv01, mouse);
    let mouseBoost = (1.0 - smoothstep(0.0, 0.4, mouseDist)) * (0.5 + isMouseDown * 0.5);
    let localWave  = waveAmount * (1.0 + mouseBoost);

    let lineIdx    = floor(uv01.y * lineCount);
    let lineCenter = (lineIdx + 0.5) / lineCount;
    let linePhase  = lineCenter * TAU + time * rollSpeed * 2.0;

    // Horizontal scanline warp
    let offset = sin(linePhase) * localWave * 0.02 * (1.0 + bass * 0.5);
    let waveUV = clamp(uv01 + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic CRT aberration
    let chromaShift = localWave * 0.005 * (1.0 + treble) * (1.0 + mouseBoost);
    let base = textureSampleLevel(readTexture, u_sampler, waveUV, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(waveUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(waveUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var crt = vec3<f32>(r, base.g, b);

    // Temporal persistence with audio-driven blend
    let decay = persistence * 0.85 + 0.1;
    let trail = mix(prev.rgb * decay, crt, 0.15 + isMouseDown * 0.2 + mouseBoost * 0.2);

    // Scanline intensity modulation in OkLab
    let scanline = sin(uv01.y * lineCount * PI) * 0.5 + 0.5;
    let dimColor = trail * mix(1.0, 0.62, scanline * localWave);

    // Audio vertical roll
    let rollOffset = fract(uv01.y + bass * 0.05) - uv01.y;
    let rolledUV   = clamp(uv01 + vec2<f32>(0.0, rollOffset), vec2<f32>(0.0), vec2<f32>(1.0));
    let rolled     = textureSampleLevel(readTexture, u_sampler, rolledUV, 0.0).rgb;

    var color = mixOkLab(dimColor, rolled, bass * 0.25);

    // Blackbody color temperature grading: bass warms, treble cools
    let temp  = mix(2800.0, 7800.0, 0.35 + treble * 0.35 - bass * 0.15);
    let grade = blackbodyRGB(temp);
    color = color * grade * (1.25 + bass * 0.35 + mids * 0.15);

    // Depth-aware atmospheric haze
    let fog = exp(-depth * 2.5);
    color = mix(color, grade * 0.12, (1.0 - fog) * 0.4);

    // HDR clamp, ACES tone map, IGN dither
    color = hue_preserve_clamp(color, 2.4);
    color = aces(color * (0.95 + mids * 0.25));
    let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
    color = color + vec3<f32>(dither);

    // Semantic alpha = bloom weight + effect strength, premultiplied writeback
    let lum         = luma(color);
    let bloomWeight = pow(max(0.0, lum - 0.55), 2.0) * 2.5;
    let effectAlpha = clamp(localWave * 0.25 + bass * 0.08 + bloomWeight, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color * effectAlpha, effectAlpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color * effectAlpha, effectAlpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "scanline-wave",
  "name": "Scanline Wave",
  "url": "shaders/scanline-wave.wgsl",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "temporal-persistence",
    "chromatic-CRT",
    "upgraded-rgba",
    "HDR-color-grading",
    "ACES-tone-map",
    "IGN-dither",
    "premultiplied-alpha"
  ],
  "description": "Temporal scanline persistence with chromatic CRT aberration, audio roll, and HDR color grading. Each scanline undulates with bass-driven amplitude; mouse proximity boosts local distortion. Treble adds per-scanline chromatic shift, bass rolls the entire field vertically, and blackbody color temperature shifts the mood. ACES tone mapping, hue-preserving HDR clamp, and IGN dither finish the image.",
  "params": [
    {
      "id": "waveAmount",
      "name": "Wave Amount",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "lineCount",
      "name": "Line Count",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "persistence",
      "name": "Persistence",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "rollSpeed",
      "name": "Roll Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "distortion",
    "scanlines",
    "CRT",
    "temporal",
    "chromatic",
    "HDR",
    "ACES",
    "dither"
  ]
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
