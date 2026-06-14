# Shader Upgrade Task: `supernova-core`

## Metadata
- **Shader ID**: supernova-core
- **Agent Role**: Visualist
- **Current Size**: 1466 bytes
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
// ═══ Supernova Core — Visualist Upgrade ═══
// Category: generative
// Features: generative, audio-reactive, sedov-taylor, rayleigh-taylor,
//   radioactive-decay, chromatic-aberration, upgraded-rgba,
//   blackbody-cooling, volumetric-fog, ign-dither

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

const TAU: f32 = 6.28318530718;

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
  for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = pow(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 1.0 / 3.0);
  let m = pow(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 1.0 / 3.0);
  let s = pow(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 1.0 / 3.0);
  return vec3<f32>(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
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

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  return c * min(1.0, max_lum / max(dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)), 1e-4));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = vec2<f32>(pixel) / res; let time = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let expansion = u.zoom_params.x; let rayCount = 6 + i32(u.zoom_params.y * 18.0);
  let shockwaves = u.zoom_params.z; let chromatic = u.zoom_params.w;
  let aspect = res.x / res.y;
  let p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0); let dist = length(p); let angle = atan2(p.y, p.x);
  let blastRadius = pow(time * 0.12 * (1.0 + shockwaves) * (1.0 + bass), 0.4) * 0.5 * (1.0 + expansion);
  let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let asymmetry = 1.0 + smoothstep(0.15, 0.0, length(p - mouseWorld)) * 0.6;
  let decayTime = fract(time * 0.08); let nickelMass = 1.0 - decayTime * 0.7;
  let cobaltLum = sin(decayTime * TAU) * 0.5 + 0.5;
  let flareTrigger = step(1.0 - treble * 0.15, hash21(vec2<f32>(floor(time * 5.0), 0.0))) * cobaltLum;
  var hdr = vec3<f32>(0.0); var ejectaDensity = 0.0; var shockTemp = 0.0;
  let coreTemp = 30000.0 * nickelMass * (1.0 + bass * 0.5);
  let core = smoothstep(0.025 * asymmetry, 0.0, dist) * (1.0 + flareTrigger * 2.0);
  hdr += blackbodyRGB(coreTemp) * 2.5 * core; shockTemp += core * coreTemp; ejectaDensity += core;
  for (var wi = 0; wi < 4; wi++) {
    let wf = f32(wi);
    let waveRadius = blastRadius * (0.25 + wf * 0.25); let waveWidth = 0.006 * (1.0 + treble * 0.5) * asymmetry;
    let wave = smoothstep(waveRadius + waveWidth, waveRadius, dist) * smoothstep(waveRadius - waveWidth, waveRadius, dist);
    let cooling = 1.0 - wf / 4.0 - dist * 0.8; let tempK = mix(15000.0, 2500.0, smoothstep(0.0, 1.0, cooling));
    let shell = mixOkLab(blackbodyRGB(tempK), blackbodyRGB(tempK * 0.6), wf / 4.0) * (1.2 + mids * 0.8);
    hdr += shell * wave; shockTemp += wave * coreTemp * (1.0 - wf * 0.2); ejectaDensity += wave * 0.3;
  }
  let rtCoord = vec2<f32>(angle * 3.0, dist * 8.0 - time * 0.5);
  let rtFingers = smoothstep(0.45, 0.65, fbm(rtCoord * vec2<f32>(1.0, 2.0 + mids * 2.0), 3)) * smoothstep(blastRadius + 0.05, blastRadius - 0.05, dist);
  let ironColor = mixOkLab(vec3<f32>(0.55, 0.75, 0.85), vec3<f32>(0.25, 0.45, 0.65), mids);
  hdr += ironColor * rtFingers * mids * 1.5; ejectaDensity += rtFingers * 0.2;
  let cellMask = smoothstep(0.08, 0.0, abs(dist - blastRadius * 0.6)) * fbm(p * 6.0 + vec2<f32>(cos(time * 0.3), sin(time * 0.25)) * 0.5, 3) * fbm(p * 13.8 + vec2<f32>(10.0, 20.0), 2);
  hdr += vec3<f32>(0.45, 0.25, 0.65) * cellMask * 0.45;
  let toCompanion = normalize(mouseWorld - p + vec2<f32>(0.001)); let normal = normalize(p + vec2<f32>(0.001));
  let rim = pow(max(0.0, 1.0 + dot(normal, toCompanion)), 3.0) * smoothstep(blastRadius + 0.04, blastRadius - 0.04, dist) * (1.0 + treble);
  hdr += blackbodyRGB(6500.0) * rim * 0.9;
  for (var ri = 0; ri < rayCount; ri++) {
    let rf = f32(ri);
    let rayAngle = rf / f32(rayCount) * TAU + hash21(vec2<f32>(rf, 0.0)) * 0.35;
    let angleDiff = abs(fract((angle - rayAngle) / TAU + 0.5) - 0.5) * TAU;
    let rayWidth = 0.015 + hash21(vec2<f32>(rf, 1.0)) * 0.035;
    let ray = smoothstep(rayWidth, 0.0, angleDiff) * smoothstep(0.35 * (1.0 + expansion) * asymmetry, 0.0, dist) * (0.3 + hash21(vec2<f32>(rf, time)) * 0.7);
    let cs = chromatic * 0.025 * dist * (1.0 + treble);
    let rayR = smoothstep(rayWidth * 1.3, 0.0, angleDiff + cs) * ray; let rayB = smoothstep(rayWidth * 1.3, 0.0, angleDiff - cs) * ray;
    let h = abs(fract(vec3<f32>(fract(rf / f32(rayCount) + bass * 0.12 + decayTime * 0.2)) + vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - vec3<f32>(3.0));
    hdr += clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)) * vec3<f32>(rayR, ray, rayB) * (1.0 + treble * 0.5);
    ejectaDensity += ray * 0.08;
  }
  hdr += blackbodyRGB(8000.0) * flareTrigger * core * 1.2; shockTemp += flareTrigger * coreTemp * 0.5;
  hdr += vec3<f32>(0.5, 0.55, 0.65) * smoothstep(0.02, 0.0, abs(dist - blastRadius)) * bass * 0.8;
  let fogDensity = ejectaDensity * 2.5; let fogAtten = exp(-fogDensity * dist * (1.0 + depth));
  let fogColor = mixOkLab(blackbodyRGB(4000.0), blackbodyRGB(12000.0), nickelMass);
  hdr = hdr * fogAtten + fogColor * (1.0 - fogAtten) * 0.4;
  hdr += vec3<f32>(0.25, 0.20, 0.35) * smoothstep(0.0, 0.5, depth) * 0.2 * (1.0 + bass * 0.2);
  hdr = hue_preserve_clamp(hdr, 8.0);
  let mapped = acesToneMap(hdr * 1.5); let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  let color = pow(mapped, vec3<f32>(1.0 / 2.2)) + vec3<f32>(dither);
  let tempNorm = clamp(shockTemp / 30000.0, 0.0, 1.0);
  let bloomWeight = clamp(ejectaDensity * (0.3 + tempNorm * 0.7) * (0.5 + depth * 0.5), 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(color * bloomWeight, bloomWeight));
  textureStore(dataTextureA, pixel, vec4<f32>(color * bloomWeight, bloomWeight));
  textureStore(writeDepthTexture, pixel, vec4<f32>(ejectaDensity * 0.5 + tempNorm * 0.3, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "supernova-core",
  "name": "Supernova Core",
  "category": "generative",
  "url": "shaders/supernova-core.wgsl",
  "description": "Sedov-Taylor blast wave with radioactive decay luminosity (56Ni->56Co->56Fe). Rayleigh-Taylor instability fingers and neutrino-driven convection cells. Blackbody cooling sequence with iron emission lines and chromatic aberration. Audio drives shock expansion. Mouse creates asymmetric ejecta. Depth controls light echo perspective.",
  "features": [
    "audio-reactive",
    "generative",
    "sedov-taylor",
    "rayleigh-taylor",
    "upgraded-rgba",
    "chromatic-aberration",
    "depth-aware"
  ],
  "params": [
    {
      "id": "expansion",
      "name": "Expansion",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "rays",
      "name": "Ray Count",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "shockwaves",
      "name": "Shockwave Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "chromatic",
      "name": "Chromatic Shift",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "generative",
    "supernova",
    "space",
    "explosion",
    "rays",
    "shockwave",
    "audio-reactive",
    "chromatic",
    "physics",
    "sedov-taylor"
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
