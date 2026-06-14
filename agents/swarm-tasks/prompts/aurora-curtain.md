# Shader Upgrade Task: `aurora-curtain`

## Metadata
- **Shader ID**: aurora-curtain
- **Agent Role**: Visualist
- **Current Size**: 1448 bytes
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
//  Aurora Curtain — Visualist Upgrade
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, chapman-layer,
//            kelvin-helmholtz, temporal-flow, upgraded-rgba, oklab-mix,
//            blackbody-stars, mie-scatter, ign-dither, fresnel-rim,
//            chromatic-aberration, two-tone-atmosphere
//  Complexity: High
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
  return p + strength * q;
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

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(l, 1.0 / 3.0); let m_ = pow(m, 1.0 / 3.0); let s_ = pow(s, 1.0 / 3.0);
  return vec3<f32>(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                   1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                   0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_; let m = m_ * m_ * m_; let s = s_ * s_ * s_;
  return vec3<f32>(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, max_lum / max(l, 1e-4));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
  let angle = atan2(uv.y - 0.5, uv.x - 0.5);
  let shift = vec2<f32>(cos(angle), sin(angle)) * strength * (1.0 + 0.3 * sin(time));
  return vec3<f32>(color.r * (1.0 + shift.x * 0.8), color.g, color.b * (1.0 - shift.y * 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let p1 = u.zoom_params.x; let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let layerBase = 3 + i32(p1 * 5.0);
  let flowSpeed = p2 * 0.5;
  let curtainWidth = 0.2 + p3 * 0.45;
  let colorShift = p4;

  let aspect = res.x / res.y;
  let p = uv01 * vec2<f32>(aspect, 1.0);
  let magZenith = vec2<f32>(mouse.x * aspect, mouse.y);
  let distToZenith = length(p - magZenith);

  var hdr = vec3<f32>(0.0);
  var excitation = 0.0;
  var bloom = 0.0;

  let cRed = vec3<f32>(0.9, 0.2, 0.15);
  let cGreen = vec3<f32>(0.2, 0.95, 0.35);
  let cBlue = vec3<f32>(0.25, 0.45, 0.95);
  let cPink = vec3<f32>(0.95, 0.3, 0.75);

  for (var i = 0; i < layerBase; i = i + 1) {
    let fi = f32(i);
    let t = time * flowSpeed * (0.4 + fi * 0.12);
    let altitude = fi / f32(layerBase);

    let warpIn = vec2<f32>(p.x * (2.0 + fi * 0.6) + t * 0.7, fi * 2.0);
    let warp = domainWarp(warpIn, 0.35 + mids * 0.2, 2);
    let baseY = 0.12 + fi * 0.17 + (mouse.y - 0.5) * 0.18;
    let khx = p.x * (2.2 + fi * 0.7) + t * 1.3 + fi * 1.7 + warp.x * 0.35;
    let kh = sin(khx) * 0.07 + sin(khx * 2.6 - t * 1.3) * 0.035 * (1.0 + mids);
    let khInstability = fbm(vec2<f32>(p.x * 3.5 + t, fi * 2.5), 3) * 0.05 * mids;
    let curtainY = baseY + kh + khInstability + (distToZenith * 0.07 * (1.0 - altitude));

    let dist = abs(p.y - curtainY);
    let thickness = curtainWidth * (0.65 + fi * 0.09) * (1.0 + bass * 0.22);
    let glow = smoothstep(thickness, 0.0, dist);

    var layerColor: vec3<f32>;
    if (altitude < 0.35) { layerColor = mixOkLab(cRed, cGreen, altitude / 0.35); }
    else if (altitude < 0.65) { layerColor = mixOkLab(cGreen, cBlue, (altitude - 0.35) / 0.30); }
    else { layerColor = mixOkLab(cBlue, cPink, (altitude - 0.65) / 0.35); }

    let rayBands = sin(p.x * 20.0 + fi * 4.0 + treble * 6.0) * 0.5 + 0.5;
    let rayMask = smoothstep(0.55, 0.95, rayBands) * treble * 0.45;
    layerColor = mix(layerColor, layerColor * 1.55, rayMask);

    let tempShift = blackbodyRGB(2800.0 + bass * 5200.0);
    layerColor = mix(layerColor, layerColor * tempShift * 1.45, colorShift * 0.35);

    let rim = pow(1.0 - clamp(dist / (thickness * 1.5), 0.0, 1.0), 2.0);
    layerColor = layerColor + layerColor * rim * 0.4 * (1.0 + treble);

    let layerIntensity = glow * (0.55 + fi * 0.08) * (1.0 + bass * 0.4);
    hdr = hdr + layerColor * layerIntensity * 1.6;
    excitation = excitation + layerIntensity;
    bloom = bloom + glow * (0.35 + bass * 0.25);
  }

  let starHash = hash21(floor(uv01 * 900.0));
  let star = step(0.998, starHash);
  let twinkle = sin(time * 2.5 + starHash * 20.0) * 0.5 + 0.5;
  let starTemp = mix(2500.0, 9500.0, hash21(floor(uv01 * 900.0) + vec2<f32>(1.0, 2.0)));
  hdr = hdr + blackbodyRGB(starTemp) * star * twinkle * 0.55;

  let atmosScatter = smoothstep(0.0, 0.55, uv01.y) * vec3<f32>(0.08, 0.14, 0.26) * (1.0 + mids * 0.35);
  let moonFill = smoothstep(0.15, 0.0, uv01.y) * vec3<f32>(0.05, 0.08, 0.16) * (0.6 + treble * 0.2);
  let miePhase = pow(1.0 + uv01.y, 1.6);
  let mieHaze = vec3<f32>(0.20, 0.16, 0.12) * miePhase * 0.06 * (1.0 + bass * 0.25);
  hdr = hdr + atmosScatter + moonFill + mieHaze;

  hdr = hdr + vec3<f32>(0.45, 0.75, 0.55) * bloom * 0.4;

  let extinction = depth * 0.38 * (1.0 + bass * 0.18);
  hdr = hdr * exp(-extinction * 0.85);

  let decay = 0.96 - p4 * 0.03;
  let trail = mix(prev.rgb * decay, hdr, 0.22 + bass * 0.08);
  hdr = hdr + trail * 0.25;

  hdr = hue_preserve_clamp(hdr, 7.0);
  let mapped = acesToneMap(hdr * 1.25);
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  var color = pow(mapped, vec3<f32>(1.0 / 2.2)) + vec3<f32>(dither);

  let caStr = 0.004 * (1.0 + bass) * excitation + depth * 0.001;
  color = genChromaticShift(color, uv01, caStr, time);

  let transparency = 1.0 - smoothstep(0.0, 0.45, uv01.y) * 0.28;
  let alpha = clamp(excitation * transparency * (0.65 + depth * 0.35), 0.0, 0.95);

  textureStore(writeTexture, pixel, vec4<f32>(color * alpha, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color * alpha, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(excitation * 0.45, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "aurora-curtain",
  "name": "Aurora Curtain",
  "category": "generative",
  "url": "shaders/aurora-curtain.wgsl",
  "description": "Chapman layer auroral excitation with Kelvin-Helmholtz instability and domain-warped curtain folds. Physically inspired colors by altitude via OkLab mixing: red O(1D) high, green O(1S) mid, blue N2+ low. Enhanced with Fresnel rim lighting on folds, temporal feedback trails, two-tone atmospheric key/fill, starfield blackbody temperatures, and audio-reactive chromatic aberration. Mouse drags magnetic zenith; depth drives extinction.",
  "features": [
    "audio-reactive",
    "mouse-driven",
    "upgraded-rgba",
    "chapman-layer",
    "kelvin-helmholtz",
    "temporal-flow",
    "depth-aware",
    "fresnel-rim",
    "chromatic-aberration",
    "two-tone-atmosphere"
  ],
  "params": [
    {
      "id": "layers",
      "name": "Curtain Layers",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "speed",
      "name": "Flow Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "width",
      "name": "Curtain Width",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "color",
      "name": "Color Shift",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "aurora",
    "borealis",
    "northern-lights",
    "generative",
    "curtains",
    "audio-reactive",
    "mouse-driven",
    "stars",
    "atmospheric",
    "physics"
  ]
}

```

---

## Agent Specialization
# Agent Role: The Visualist

## Identity
You are **The Visualist**, a shader architect focused on color science, lighting, and emotional impact. You make shaders visually stunning.

## Upgrade Toolkit

### Color Science
- SRGB → Linear workflow with proper gamma (`pow(c, 2.2)` in, `pow(c, 1/2.2)` out)
- Clamped colors → HDR with values >1.0 before tone mapping
- Static palettes → Dynamic temperature shifting
- Solid fills → Subsurface scattering glow
- Flat shading → Fresnel rim lighting

#### OkLab — Perceptually Uniform Color Space (use for smooth gradients / mixing)
```wgsl
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                     1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                     0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                    -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                    -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
// Mix colors in OkLab (avoids the grey mud in mid-tones)
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}
```

#### Blackbody / Color Temperature
```wgsl
// Temperature in Kelvin → approximate RGB (1000K–40000K)
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
```

#### Cosine Palette (Inigo Quilez) — fast procedural gradients
```wgsl
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}
// Example fire: palette(t, (0.5,0.5,0.5),(0.5,0.5,0.5),(1,1,0.5),(0,0.1,0.2))
// Example ice:  palette(t, (0.5,0.5,0.5),(0.5,0.5,0.5),(1,1,1),(0,0.33,0.67))
```

### Lighting Techniques
- Single light → 3-point studio lighting (key + fill + rim, different color temps)
- Diffuse only → Specular via GGX distribution + Fresnel-Schlick
- Hard shadows → Soft penumbra: `smoothstep(penumbra, 0.0, shadowDist)`
- Local lighting → Volumetric god rays (ray march toward light source)
- Flat surface → Iridescent thin-film: `sin(d * freq + hue_offset) * fresnel`

### Atmosphere
- Clear → Volumetric fog: `exp(-density * dist)` (Beer-Lambert)
- Sharp → Bokeh depth of field (hexagonal aperture SDF)
- Static → Animated caustics: FBM of sinusoids, `sin(fbm(p)*8 + t)`
- Clean → Rayleigh scattering: blue-bias sky, `pow(lambda, -4.0)` wavelength dependence
- Mie scattering for haze: `(1-g²) / pow(1+g²-2g*cosθ, 1.5)`, g≈0.76 for aerosols

### Color Grading
- Raw output → ACES tone mapped (apply last, after all HDR work)
- Static → Audio-reactive temperature (`blackbodyRGB(3000 + bass * 4000)`)
- Monochrome → Split-tone: shadows in complementary hue, highlights warm
- Natural → Iridescent thin-film: wavelength-dependent phase shift
- Flat mix → OkLab interpolation (prevents muddy mid-tone blending)

### Tonemap & Dither Stack (kimi-cli reference snippets)

Always process in this order: accumulate HDR → hue-preserve clamp → ACES tonemap → dither → premultiplied write.

#### 1. Hue-preserving HDR clamp (prevents desaturation on bright highlights)
```wgsl
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
```
Apply after additive accumulation, before ACES. Beats `min(c, 1.0)` which desaturates to white.

#### 2. ACES filmic tonemap (drop-in, no LUT required)
```wgsl
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
```
Pair with sRGB gamma `pow(c, vec3<f32>(1.0/2.2))` on write if the display is sRGB.

#### 3. Interleaved-gradient (IGN) blue-noise dither (kills 8-bit banding)
```wgsl
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
// before textureStore:
let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
let outRGB = aces(hdr) + vec3<f32>(dither);
```
Cheaper than a blue-noise texture lookup and visually identical at 8-bit precision.

#### Premultiplied-alpha writeback — tactic #12 (correct compositing in the slot chain)
```wgsl
let a = clamp(alpha, 0.0, 1.0);
textureStore(writeTexture, gid.xy, vec4<f32>(rgb * a, a));
```
The renderer expects premultiplied output downstream of slot 1. Straight alpha causes dark fringes after the next slot's blur/blend.

## RGBA Channel Strategy

**Alpha = bloom weight** is the most useful convention for generative shaders:
```wgsl
let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
let bloomWeight = pow(max(0.0, luma - 0.6), 2.0) * 3.0;  // only bright areas
textureStore(writeTexture, coord, vec4<f32>(color, bloomWeight));
```

Other useful alpha encodings:
- `alpha = depth` — for depth-aware compositing in the next slot
- `alpha = effectStrength` — transparent where effect is absent (compositing-friendly)
- `alpha = fresnel` — glass/water reflectance mask

**Do NOT output `vec4(color, 1.0)` unless the shader is a pure background layer.**

## Quality Checklist
- [ ] HDR values exceed 1.0 in highlights before tone mapping
- [ ] At least 2 light sources with different color temperatures
- [ ] `hue_preserve_clamp` applied before ACES to avoid highlight desaturation
- [ ] ACES tone mapping applied as the final step
- [ ] IGN dither added before `textureStore` to kill 8-bit banding
- [ ] Atmospheric depth (fog/haze/dust via Beer-Lambert or Rayleigh)
- [ ] Color gradients use OkLab mixing to avoid muddy transitions
- [ ] Alpha channel encodes bloom weight or compositing info
- [ ] Premultiplied-alpha writeback (`vec4(rgb * a, a)`) when alpha < 1

## Output Rules
- Keep the original "soul" of the shader while making it visually stunning.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- **Alpha must carry semantic meaning** — bloom weight, depth, or Fresnel reflectance.

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
