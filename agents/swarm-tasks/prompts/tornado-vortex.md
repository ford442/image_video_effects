# Shader Upgrade Task: `tornado-vortex`

## Metadata
- **Shader ID**: tornado-vortex
- **Agent Role**: Visualist
- **Current Size**: 1406 bytes
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
//  Tornado Vortex
//  Category: generative
//  Features: generative, audio-reactive, rankine-vortex, lagrangian-debris,
//            lightning-illumination, upgraded-rgba
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let intensity = u.zoom_params.x;
  let spinSpeed = u.zoom_params.y * 5.0;
  let debrisAmt = u.zoom_params.z;
  let lightningAmt = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let dist = length(p);
  let angle = atan2(p.y, p.x);

  // Rankine vortex: viscous core + potential flow outside
  let coreRadius = 0.04 * (1.0 + mids * 0.5);
  let circulation = 0.15 * intensity * (1.0 + bass * 0.4);
  let vTheta = select(circulation / (6.28318530718 * dist), circulation * dist / (6.28318530718 * coreRadius * coreRadius), dist > coreRadius);
  let vRadial = -0.02 * intensity * smoothstep(0.3, 0.0, dist);
  let vVertical = 0.1 * intensity * smoothstep(-0.3, 0.4, uv.y) * smoothstep(0.0, 0.1, dist);

  var color = vec3<f32>(0.04, 0.06, 0.09);
  var debrisDensity = 0.0;
  var condensation = 0.0;

  // Funnel condensation with subsurface scattering
  let funnelWidth = coreRadius + (uv.y + 0.5) * 0.22 * (1.0 + mids * 0.4);
  let funnelDist = abs(dist - funnelWidth * (0.55 + sin(uv.y * 12.0 + time * 0.8) * 0.08 * intensity));
  condensation = smoothstep(0.045 * intensity, 0.0, funnelDist) * smoothstep(-0.5, 0.5, uv.y);
  let sss = condensation * condensation * vec3<f32>(0.35, 0.42, 0.48) * 0.6;

  // Spiral streaks from vorticity
  let spiralPhase = angle + vTheta * time * spinSpeed * 40.0 + uv.y * 18.0;
  let spiral = sin(spiralPhase) * 0.5 + 0.5;
  let spiralMask = condensation * spiral * (0.4 + mids * 0.4);
  color = color + vec3<f32>(0.35, 0.40, 0.45) * spiralMask;

  // Lagrangian debris advection
  let debrisCount = 24;
  for (var di = 0; di < debrisCount; di = di + 1) {
    let df = f32(di);
    let seed = hash21(vec2<f32>(df, 0.0));
    let dh = fract(df / f32(debrisCount) + time * 0.08 * (1.0 + bass) + seed * 0.3);
    let dAngle = df * 2.39996 + dh * 8.0 + time * spinSpeed * 0.25 + vTheta * 10.0;
    let dRadius = 0.015 + dh * funnelWidth * 1.1;
    let dPos = vec2<f32>(cos(dAngle), sin(dAngle)) * dRadius;
    let dd = length(p - dPos);
    let dSize = 0.0025 * (1.0 + debrisAmt) * (1.0 + depth * 0.5);
    let particle = smoothstep(dSize, 0.0, dd);
    let sizeFade = 1.0 - smoothstep(0.0, 0.35, dh);
    debrisDensity = debrisDensity + particle * sizeFade;
    color = color + vec3<f32>(0.55, 0.50, 0.45) * particle * debrisAmt * sizeFade;
  }

  // Mouse probe flung by vortex
  let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseWorld);
  let fling = smoothstep(0.12, 0.0, mouseDist) * vTheta * 3.0 * intensity;
  color = color + vec3<f32>(0.7, 0.65, 0.55) * fling;

  // Lightning flashes triggered by treble
  let flashTime = floor(time * (6.0 + treble * 8.0));
  let flash = hash31(vec3<f32>(flashTime, 0.0, 0.0));
  var lightning = step(1.0 - lightningAmt * 0.12 - treble * 0.08, flash) * smoothstep(0.35, 0.0, dist);
  let lightningBranch = sin(angle * 9.0 + flashTime * 3.7) * 0.5 + 0.5;
  lightning = lightning * (0.4 + lightningBranch * 0.6);
  color = color + vec3<f32>(0.92, 0.96, 1.0) * lightning * (1.0 + treble);

  // Ground dust
  let dust = hash21(uv * 55.0 + time * 0.4) * smoothstep(0.0, -0.25, uv.y) * 0.25 * intensity;
  color = color + vec3<f32>(0.38, 0.33, 0.28) * dust;

  // HDR bloom on electrical discharge
  color = color + vec3<f32>(0.5, 0.6, 0.7) * lightning * lightning * 0.4;

  // ACES tone mapping
  color = acesToneMap(color * 1.4);

  // Depth controls debris size perspective (already in dSize)
  let depthFade = 1.0 - depth * 0.2;
  color = color * depthFade;

  // Alpha: debris density * condensation_opacity * depth
  let condOpacity = condensation * 0.85 + spiralMask * 0.4;
  let alpha = clamp((debrisDensity * 0.3 + condOpacity) * (0.5 + depth * 0.5), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(condensation * 0.5 + debrisDensity * 0.2, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "tornado-vortex",
  "name": "Tornado Vortex",
  "category": "generative",
  "url": "shaders/tornado-vortex.wgsl",
  "description": "Rankine vortex model with viscous core, radial inflow, and vertical updraft. Lagrangian debris advection with condensation funnel and subsurface scattering. Lightning flash illumination. Audio drives Fujita-scale intensity. Mouse acts as a probe flung by vorticity. Depth controls debris perspective.",
  "features": [
    "audio-reactive",
    "generative",
    "rankine-vortex",
    "lagrangian-debris",
    "upgraded-rgba",
    "lightning",
    "depth-aware"
  ],
  "params": [
    {
      "id": "intensity",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "spin",
      "name": "Spin Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "debris",
      "name": "Debris Amount",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "lightning",
      "name": "Lightning",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "generative",
    "tornado",
    "vortex",
    "storm",
    "spiral",
    "debris",
    "lightning",
    "audio-reactive",
    "physics",
    "rankine"
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
