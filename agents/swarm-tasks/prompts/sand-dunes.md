# Shader Upgrade Task: `sand-dunes`

## Metadata
- **Shader ID**: sand-dunes
- **Agent Role**: Visualist
- **Current Size**: 1401 bytes
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
//  Sand Dunes — Visualist Upgrade
//  Category: generative
//  Features: generative, audio-reactive, bagnold-physics, anisotropic-fbm,
//            wind-erosion, separation-bubble, domain-warp, ggx-specular,
//            rayleigh-mie-sky, temporal-feedback, oklab-palette,
//            blackbody-sun, aces-tone-map, ign-dither, semantic-alpha
//  Complexity: High
//  Created: 2026-05-31
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// ── Noise ────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  return p + strength * vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
}

// ── Color science ────────────────────────────────────────────────
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

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 1.0; var g = 0.0; var b = 1.0;
  if (t > 66.0) {
    r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
    g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
  } else {
    g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
    b = select(clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0);
  }
  return vec3<f32>(r, g, b);
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  return c * min(1.0, max_lum / max(dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)), 1e-4));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

// ── Microfacet specular ──────────────────────────────────────────
fn D_GGX(NoH: f32, roughness: f32) -> f32 {
  let a = max(roughness * roughness, 0.001);
  let d = NoH * NoH * (a - 1.0) + 1.0;
  return a / (PI * d * d);
}

fn F_Schlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x; let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let duneScale = u.zoom_params.x * 4.0 + 2.0; let windBase = u.zoom_params.y * 0.5;
  let erosion = u.zoom_params.z; let shadowDepth = u.zoom_params.w;

  let windAngle = (mouse.x - 0.5) * 1.5 + (mids - 0.5) * 0.8;
  let windDir = vec2<f32>(cos(windAngle), sin(windAngle));
  let windSpeed = windBase + bass * 0.3;
  let t = time * windSpeed;

  let p = uv01 * duneScale;
  let warped = domainWarp(p + windDir * t * 0.05, 0.4 + mids * 0.3, 4);
  let aniso = vec2<f32>(dot(warped, windDir), dot(warped, vec2<f32>(-windDir.y, windDir.x))) * vec2<f32>(2.5, 1.0);
  let height = fbm(aniso + vec2<f32>(t * 0.3, 0.0), 5) * 0.5 + 0.5;

  let slope = (fbm(aniso + vec2<f32>(0.01, 0.0) + vec2<f32>(t * 0.3, 0.0), 5)
             - fbm(aniso - vec2<f32>(0.01, 0.0) + vec2<f32>(t * 0.3, 0.0), 5)) * 25.0;
  let crest = smoothstep(0.3, 0.7, height) * smoothstep(0.0, -0.4, slope);
  let bubble = crest * 0.25 * (1.0 + bass * 0.5);

  let rippleCoord = p * 8.0 + windDir * t * 2.0;
  let ripple1 = sin(rippleCoord.x * 3.0 + rippleCoord.y * 1.5) * 0.5 + 0.5;
  let ripple2 = sin(rippleCoord.x * 5.0 - rippleCoord.y * 2.0 + t * 1.5) * 0.5 + 0.5;
  let rippleMask = smoothstep(0.6, 0.9, ripple1 * ripple2) * erosion * (0.5 + abs(slope) * 2.0);

  let lit = vec3<f32>(0.92, 0.72, 0.42);
  let mid = vec3<f32>(0.72, 0.45, 0.22);
  let shadow = vec3<f32>(0.42, 0.28, 0.14);
  let umber = vec3<f32>(0.28, 0.18, 0.10);

  let sunTemp = 4500.0 + bass * 2500.0;
  let keyLight = blackbodyRGB(sunTemp);
  let fillLight = blackbodyRGB(8000.0) * 0.35;
  let rimLight = blackbodyRGB(6000.0) * 0.5;

  let shadowMask = smoothstep(0.2, -0.6, slope) * shadowDepth;
  let duneColor = mixOkLab(lit, mixOkLab(mid, shadow, shadowMask * 0.7), shadowMask);

  let normalApprox = normalize(vec3<f32>(-slope * 2.0, 1.0, 0.5));
  let sunDir = normalize(vec3<f32>(0.6, 0.8, 0.2));
  let viewDir = normalize(vec3<f32>(uv * 1.5, 1.0));
  let halfDir = normalize(sunDir + viewDir);
  let NoL = max(0.0, dot(normalApprox, sunDir));
  let NoH = max(0.0, dot(normalApprox, halfDir));
  let NoV = max(0.0, dot(normalApprox, viewDir));
  let roughness = 0.6 - windBase * 0.35;
  let spec = keyLight * F_Schlick(NoV, vec3<f32>(0.04)) * D_GGX(NoH, roughness) * NoL * 0.25;
  let fill = max(0.0, dot(normalApprox, normalize(vec3<f32>(-0.4, 0.6, 0.3)))) * 0.6;
  let rim = pow(1.0 - max(0.0, dot(normalApprox, vec3<f32>(0.0, 0.0, 1.0))), 3.0);
  var hdr = duneColor * (keyLight * NoL + fillLight * fill) + rimLight * rim * crest + spec;

  let sss = smoothstep(-0.8, -0.2, slope) * crest * vec3<f32>(0.55, 0.30, 0.12) * 0.5;
  hdr = hdr + sss;

  let sparkleCoord = uv01 * 120.0 + windDir * t * 10.0;
  let sparkle = step(0.997 - treble * 0.003, fract(sin(dot(sparkleCoord, vec2<f32>(12.9898, 78.233))) * 43758.5453));
  let sparkleColor = vec3<f32>(1.0, 0.95, 0.85) * sparkle * treble * (0.5 + smoothstep(0.0, -0.3, slope));
  hdr = hdr + sparkleColor * 2.0;

  let mouseDist = length(uv01 - mouse);
  let windShadow = smoothstep(0.15, 0.0, mouseDist) * smoothstep(0.0, 0.5, dot(normalize(uv01 - mouse), windDir));
  hdr = hdr * (1.0 - windShadow * 0.4);

  hdr = mix(hdr, mixOkLab(umber, shadow, 0.5) * keyLight, rippleMask * 0.6);

  let mu = dot(viewDir, sunDir);
  let rayleigh = 0.15 * (1.0 + mu * mu);
  let g = 0.76;
  let mie = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);
  let skyBase = mixOkLab(vec3<f32>(0.82, 0.72, 0.58), vec3<f32>(0.55, 0.65, 0.85), 0.3);
  let skyColor = skyBase * rayleigh + keyLight * mie * 0.03;
  let hazeDensity = depth * 0.45 * (1.0 + bass * 0.2);
  let transmittance = exp(-hazeDensity * 1.5);
  hdr = hdr * transmittance + skyColor * (1.0 - transmittance) * 0.5;

  let decay = 0.96 - shadowDepth * 0.03;
  let trail = mix(prev.rgb * decay, hdr, 0.18 + bass * 0.05);

  let mapped = acesToneMap(hue_preserve_clamp(trail, 5.0) * 1.3);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  let color = pow(mapped, vec3<f32>(1.0 / 2.2)) + vec3<f32>(dither);

  let sandDensity = 0.75 + height * 0.2 + rippleMask * 0.1;
  let windExposure = 0.6 + windSpeed * 0.4;
  let bloomWeight = clamp(sandDensity * windExposure * transmittance, 0.0, 1.0);
  let a = bloomWeight;

  textureStore(writeTexture, pixel, vec4<f32>(color * a, a));
  textureStore(dataTextureA, pixel, vec4<f32>(trail * a, a));
  textureStore(writeDepthTexture, pixel, vec4<f32>(height * 0.5 + bubble, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "sand-dunes",
  "name": "Sand Dunes",
  "category": "generative",
  "url": "shaders/sand-dunes.wgsl",
  "description": "Bagnold dune physics with domain-warped anisotropic fBm, GGX sun glints on grain faces, Rayleigh-Mie atmospheric haze, and temporal sand-drift feedback. Separation bubbles at crests, ripple superposition on slip faces, OkLab desert palette, subsurface scattering and HDR saltation sparkles. Audio drives wind migration, treble sparkles and temporal blend. Mouse creates wind shadows. Depth controls atmospheric haze.",
  "features": [
    "audio-reactive",
    "generative",
    "bagnold-physics",
    "anisotropic-fbm",
    "wind-erosion",
    "separation-bubble",
    "domain-warp",
    "ggx-specular",
    "rayleigh-mie-sky",
    "temporal-feedback",
    "upgraded-rgba",
    "depth-aware"
  ],
  "params": [
    {
      "id": "scale",
      "name": "Dune Scale",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "wind",
      "name": "Wind Speed",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "erosion",
      "name": "Erosion",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "shadows",
      "name": "Shadow Depth",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "generative",
    "desert",
    "dunes",
    "sand",
    "landscape",
    "wind",
    "audio-reactive",
    "nature",
    "bagnold",
    "physics",
    "domain-warp",
    "ggx",
    "atmospheric"
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
